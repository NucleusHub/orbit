import Foundation
import Observation

/// What the app has loaded from the server, and the passwords given this session (the web keeps them in sessionStorage).
@MainActor
@Observable
final class FilesStore {
    var service: FilesService
    private(set) var listings: [String: Listing] = [:]
    /// Search hits as the server sent them; `searchResults` hides what sits inside a locked folder.
    private var rawSearch: Listing?
    var searchResults: Listing? {
        guard var l = rawSearch else { return nil }
        l.folders.removeAll { isFaceIDLocked(folderID: $0.parentId) }
        l.files.removeAll { isFaceIDLocked(folderID: $0.folderId) }
        return l
    }
    private(set) var settings: OrbitSettings?
    private(set) var lastSynced: Date?
    private(set) var syncing = false
    var syncError: String?
    /// Raw URLs with unlock tokens, by file id.
    private(set) var unlockedURLs: [String: String] = [:]

    let authenticator: Authenticator
    /// Locks passed with Face ID (or their fallback) since the app last went to the background.
    private(set) var faceIDPassed: Set<String> = []
    /// Folder id -> parent id (nil at the root), from listings and the full tree, to find inherited locks.
    private var parents: [String: String?] = [:]
    @ObservationIgnored private var treeLoadedAt: Date?

    @ObservationIgnored private var folderPasswords: [String: String] = [:]
    @ObservationIgnored private var verifiedFolders: Set<String> = []
    /// Files whose plain URL the server refused (a search hit inside a protected folder).
    private var forbidden: Set<String> = []

    @ObservationIgnored private let vault: PasswordVault

    init(service: FilesService, authenticator: Authenticator = LocalAuthenticator(), vault: PasswordVault = KeychainVault()) {
        self.service = service
        self.authenticator = authenticator
        self.vault = vault
    }

    static func key(_ folderID: String?) -> String { folderID ?? "root" }

    func listing(_ folderID: String?) -> Listing? { listings[Self.key(folderID)] }

    // MARK: Loading

    /// Throws `.folderLocked` when the folder wants a password this session doesn't have.
    func load(_ folderID: String?) async throws {
        try await requireLocks()
        // Face ID passed for this folder: its saved password stands in for typing it.
        var fromVault = false
        if let folderID, folderPasswords[folderID] == nil, canUseVault(folderID: folderID), let saved = vault.password(for: folderID) {
            folderPasswords[folderID] = saved
            verifiedFolders.insert(folderID)
            fromVault = true
        }
        do {
            let listing = try await service.browse(folderID, password: folderID.flatMap { folderPasswords[$0] })
            learn(listing, in: folderID)
            listings[Self.key(folderID)] = listing
        } catch OrbitError.folderLocked {
            // A saved password the server no longer takes (changed elsewhere) is dropped.
            if fromVault, let folderID { vault.remove(folderID) }
            // The password changed elsewhere: what it protected mustn't stay on screen.
            listings[Self.key(folderID)] = nil
            if let folderID {
                folderPasswords[folderID] = nil
                verifiedFolders.remove(folderID)
            }
            throw OrbitError.folderLocked
        }
    }

    /// The folder a file lives in, fetched again (a search hit's conversion progress).
    func refreshFolder(of file: OrbitFile) async {
        await refresh(file.folderId)
        if let q = lastQuery, searchResults != nil { try? await search(q) }
    }

    /// Opens a protected folder; a wrong password is `.wrongPassword` and isn't remembered.
    func open(folderID: String, password: String) async throws {
        do {
            let listing = try await service.browse(folderID, password: password)
            folderPasswords[folderID] = password
            verifiedFolders.insert(folderID)
            learn(listing, in: folderID)
            listings[Self.key(folderID)] = listing
            passRelaxedLocks(folderID: folderID)
            if !lockChain(folderID: folderID).isEmpty { vault.save(password, for: folderID) }
        } catch OrbitError.folderLocked {
            throw OrbitError.wrongPassword
        }
    }

    func refresh(_ folderID: String?) async {
        try? await load(folderID)
    }

    func search(_ query: String) async throws {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { clearSearch(); return }
        try await requireLocks()
        let hits = try await service.search(q)
        // Hits can sit deep inside a Face ID folder; without the tree they'd show before that's known.
        if settings?.faceIdLocks.isEmpty == false {
            if treeLoadedAt.map({ Date().timeIntervalSince($0) > 30 }) ?? true { try await loadTreeOrThrow() }
        }
        lastQuery = q
        rawSearch = hits
    }

    func clearSearch() {
        rawSearch = nil
        lastQuery = nil
    }

    /// "Sync now": everything on screen and the settings, fetched again.
    func syncNow() async {
        guard !syncing else { return }
        syncing = true
        defer { syncing = false }
        ThumbnailCache.shared.clear()
        do {
            settings = try await service.settings()
            for key in listings.keys {
                let id = key == "root" ? nil : key
                if isFaceIDLocked(folderID: id) { listings[key] = nil; continue }
                do {
                    try await load(id)
                } catch OrbitError.folderLocked, OrbitError.notFound {
                    listings[key] = nil
                }
            }
            if listings["root"] == nil { try await load(nil) }
            settings = try await service.settings()
            await loadTree()
            syncError = nil
            lastSynced = Date()
        } catch {
            syncError = error.orbitMessage
        }
    }

    func needsPolling(_ folderID: String?) -> Bool {
        listing(folderID)?.files.contains { $0.transcodeStatus.isActive } ?? false
    }

    // MARK: Locked files

    func resolvedURL(for file: OrbitFile) -> String? {
        if let url = unlockedURLs[file.id] { return url }
        if forbidden.contains(file.id) { return nil }
        return file.url
    }

    func data(for file: OrbitFile) async throws -> Data {
        guard let url = resolvedURL(for: file) else { throw OrbitError.forbidden }
        do {
            return try await service.data(at: url)
        } catch OrbitError.forbidden {
            forbidden.insert(file.id)
            unlockedURLs[file.id] = nil
            throw OrbitError.forbidden
        }
    }

    /// Whether a stream will open; a refused one goes through the unlock prompt.
    func probe(_ file: OrbitFile) async throws {
        guard let url = resolvedURL(for: file) else { throw OrbitError.forbidden }
        do {
            try await service.probe(at: url)
        } catch OrbitError.forbidden {
            forbidden.insert(file.id)
            unlockedURLs[file.id] = nil
            throw OrbitError.forbidden
        }
    }

    /// The file on disk under its own name, for the share sheet.
    func download(_ file: OrbitFile) async throws -> URL {
        guard let url = resolvedURL(for: file) else { throw OrbitError.forbidden }
        let temp: URL
        do {
            temp = try await service.download(at: url)
        } catch OrbitError.forbidden {
            forbidden.insert(file.id)
            unlockedURLs[file.id] = nil
            throw OrbitError.forbidden
        }
        let dir = FileManager.default.temporaryDirectory.appending(path: "share/\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let out = dir.appending(path: file.filename)
        try FileManager.default.moveItem(at: temp, to: out)
        return out
    }

    func unlock(_ file: OrbitFile, password: String) async throws {
        unlockedURLs[file.id] = try await service.unlockFile(file.id, password: password)
        forbidden.remove(file.id)
        passRelaxedLocks(file: file)
        if !lockChain(.file(file)).isEmpty { vault.save(password, for: file.id) }
    }

    /// The password gate before editing a protected item (`withAuth` on the web).
    func needsVerification(_ item: ItemRef) -> Bool {
        guard item.isProtected else { return false }
        switch item {
        case .file(let f): return unlockedURLs[f.id] == nil
        case .folder(let f):
            if verifiedFolders.contains(f.id) { return false }
            if canUseVault(folderID: f.id), let saved = vault.password(for: f.id) {
                // Face ID passed and the password is saved: no prompt for edits either.
                folderPasswords[f.id] = saved
                verifiedFolders.insert(f.id)
                return false
            }
            return true
        }
    }

    func verify(_ item: ItemRef, password: String) async throws {
        switch item {
        case .file(let f): try await unlock(f, password: password)
        case .folder(let f):
            try await service.verifyFolder(f.id, password: password)
            verifiedFolders.insert(f.id)
            folderPasswords[f.id] = password
        }
    }

    /// Signing out: nothing from the account stays.
    func forget() {
        listings = [:]
        rawSearch = nil
        lastQuery = nil
        settings = nil
        lastSynced = nil
        unlockedURLs = [:]
        forbidden = []
        folderPasswords = [:]
        verifiedFolders = []
        faceIDPassed = []
        parents = [:]
        treeLoadedAt = nil
        vault.removeAll()
        ThumbnailCache.shared.clear()
    }

    // MARK: Face ID locks

    func faceIDLock(for itemID: String) -> FaceIDLock? { settings?.faceIdLocks[itemID] }

    /// Locks live in the settings; without them a locked folder would look open, so nothing shows until they're known.
    func requireLocks() async throws {
        if settings == nil { settings = try await service.settings() }
    }

    /// A folder reached without its parents (a deep link, a search hit) learns them before its lock is checked.
    func ensureKnown(_ folderID: String?) async throws {
        try await requireLocks()
        guard let folderID, parents[folderID] == nil, settings?.faceIdLocks.isEmpty == false else { return }
        try await loadTreeOrThrow()
    }

    /// Every folder's parent, so a lock on an outer folder covers what's deep inside it.
    func loadTree() async { try? await loadTreeOrThrow() }

    private func loadTreeOrThrow() async throws {
        let all = try await service.allFolders()
        for f in all {
            parents[f.id] = .some(f.parentId)
            names[f.id] = f.name
        }
        treeLoadedAt = Date()
    }

    /// Folder names from the tree, for a deep-linked folder's title and Face ID prompt.
    private var names: [String: String] = [:]
    func folderName(_ id: String) -> String? { folder(id)?.name ?? names[id] }

    private func learn(_ listing: Listing, in folderID: String?) {
        for f in listing.folders { parents[f.id] = .some(f.parentId) }
        for (i, crumb) in listing.breadcrumbs.enumerated() { parents[crumb.id] = .some(i == 0 ? nil : listing.breadcrumbs[i - 1].id) }
    }

    /// The locked ids above (and including) a folder, innermost first.
    private func lockChain(folderID: String?) -> [String] {
        var out: [String] = []
        var at = folderID
        var seen: Set<String> = []
        while let id = at, seen.insert(id).inserted {
            if faceIDLock(for: id) != nil { out.append(id) }
            guard let parent = parents[id] else { break }
            at = parent
        }
        return out
    }

    private func lockChain(_ item: ItemRef) -> [String] {
        switch item {
        case .folder(let f): lockChain(folderID: f.id)
        case .file(let f): (faceIDLock(for: f.id) != nil ? [f.id] : []) + lockChain(folderID: f.folderId)
        }
    }

    private func pending(_ chain: [String]) -> [String] { chain.filter { !faceIDPassed.contains($0) } }

    func isFaceIDLocked(folderID: String?) -> Bool { !pending(lockChain(folderID: folderID)).isEmpty }
    func isFaceIDLocked(_ item: ItemRef) -> Bool { !pending(lockChain(item)).isEmpty }
    /// The item's own lock (not an inherited one), for its badge and menu.
    func ownFaceIDLock(_ item: ItemRef) -> FaceIDLock? { faceIDLock(for: item.rawID) }

    /// Asks for Face ID for every lock still in the way. `.usePassword` means: show the Orbit password prompt.
    func passFaceID(for item: ItemRef) async -> BiometricOutcome {
        let locks = pending(lockChain(item))
        guard !locks.isEmpty else { return .success }
        let strict = locks.contains { faceIDLock(for: $0)?.strict == true }
        // The item's password can only stand in for the item's own lock, never an outer folder's.
        let fallback = !strict && item.isProtected && locks == [item.rawID]
        let outcome = await authenticator.authenticate(reason: String(localized: "Open “\(item.name)”"), strict: strict,
                                                       passwordFallback: fallback)
        if outcome == .success { faceIDPassed.formUnion(locks) }
        return outcome
    }

    func passFaceID(folderID: String, name: String) async -> BiometricOutcome {
        await passFaceID(for: .folder(OrbitFolder(id: folderID, name: name)))
    }

    /// The Orbit password is the fallback for relaxed locks only.
    private func passRelaxedLocks(folderID: String) {
        if faceIDLock(for: folderID)?.strict == false, pending(lockChain(folderID: folderID)) == [folderID] { faceIDPassed.insert(folderID) }
    }

    private func passRelaxedLocks(file: OrbitFile) {
        if faceIDLock(for: file.id)?.strict == false, pending(lockChain(.file(file))) == [file.id] { faceIDPassed.insert(file.id) }
    }

    /// Back from the background: every lock asks again, and what was behind one leaves memory.
    func relockFaceID() {
        faceIDPassed = []
        for key in listings.keys where key != "root" && isFaceIDLocked(folderID: key) { listings[key] = nil }
        for id in unlockedURLs.keys where faceIDLock(for: id) != nil { unlockedURLs[id] = nil }
        // Passwords behind a lock come back from the vault only through Face ID.
        for id in folderPasswords.keys where !lockChain(folderID: id).isEmpty {
            folderPasswords[id] = nil
            verifiedFolders.remove(id)
        }
    }

    /// Whether Face ID has been passed for everything covering this folder (so its saved password may be used).
    private func canUseVault(folderID: String) -> Bool {
        let chain = lockChain(folderID: folderID)
        return !chain.isEmpty && pending(chain).isEmpty
    }

    /// Opens a protected item with its saved password after Face ID, instead of asking for it.
    func autoUnlock(_ item: ItemRef) async -> Bool {
        let chain = lockChain(item)
        guard item.isProtected, !chain.isEmpty, pending(chain).isEmpty, let saved = vault.password(for: item.rawID) else { return false }
        do {
            switch item {
            case .file(let f): try await unlock(f, password: saved)
            case .folder(let f):
                try await service.verifyFolder(f.id, password: saved)
                folderPasswords[f.id] = saved
                verifiedFolders.insert(f.id)
            }
            return true
        } catch {
            vault.remove(item.rawID)
            return false
        }
    }

    /// Folders to seal in the Move tree: locked and not passed.
    var sealedFolders: Set<String> {
        Set((settings?.faceIdLocks.keys).map(Array.init) ?? []).subtracting(faceIDPassed)
    }

    func setFaceIDLock(_ item: ItemRef, strict: Bool?) async throws {
        settings = try await service.setFaceIDLock(item.rawID, strict: strict)
        if strict == nil {
            faceIDPassed.remove(item.rawID)
            vault.remove(item.rawID)
        }
    }

    // MARK: Changes

    /// Runs a change, then reloads the folders it touched (and the search, if one is showing).
    private func change(_ affected: [String?], _ op: () async throws -> Void) async throws {
        do {
            try await op()
        } catch {
            // Part of a bulk change may have gone through; show what the server has now.
            await reload(affected)
            throw error
        }
        await reload(affected)
    }

    private func reload(_ affected: [String?]) async {
        for id in Set(affected.map(Self.key)) {
            await refresh(id == "root" ? nil : id)
        }
        if let q = lastQuery, searchResults != nil { try? await search(q) }
    }

    @ObservationIgnored var lastQuery: String?

    func createFolder(name: String, in parentID: String?) async throws -> OrbitFolder {
        var made: OrbitFolder?
        try await change([parentID]) { made = try await service.createFolder(name: name, parentID: parentID) }
        return made!
    }

    func rename(_ item: ItemRef, to name: String, in folderID: String?) async throws {
        try await change([folderID]) {
            switch item {
            case .file(let f): _ = try await service.renameFile(f.id, to: name)
            case .folder(let f): _ = try await service.renameFolder(f.id, to: name)
            }
        }
    }

    func move(_ items: [ItemRef], to target: String?, from folderID: String?) async throws {
        try await change([folderID, target]) {
            try await withThrowingTaskGroup(of: Void.self) { group in
                for item in items {
                    group.addTask { [service] in
                        switch item {
                        case .file(let f): try await service.moveFile(f.id, to: target)
                        case .folder(let f): try await service.moveFolder(f.id, to: target)
                        }
                    }
                }
                var failure: Error?
                while let result = await group.nextResult() { if case .failure(let e) = result { failure = failure ?? e } }
                if let failure { throw failure }
            }
        }
        // Moved folders now live elsewhere; their cached listings would show stale breadcrumbs.
        for case .folder(let f) in items { listings[f.id] = nil }
    }

    func setPassword(_ items: [ItemRef], _ password: String?, in folderID: String?) async throws {
        try await change([folderID]) {
            try await withThrowingTaskGroup(of: Void.self) { group in
                for item in items {
                    group.addTask { [service] in
                        switch item {
                        case .file(let f): _ = try await service.setFilePassword(f.id, password)
                        case .folder(let f): _ = try await service.setFolderPassword(f.id, password)
                        }
                    }
                }
                var failure: Error?
                while let result = await group.nextResult() { if case .failure(let e) = result { failure = failure ?? e } }
                if let failure { throw failure }
            }
        }
        for item in items {
            switch item {
            case .file(let f): unlockedURLs[f.id] = nil
            case .folder(let f):
                if let password { folderPasswords[f.id] = password; verifiedFolders.insert(f.id) } else { folderPasswords[f.id] = nil }
            }
        }
    }

    func delete(_ items: [ItemRef], from folderID: String?) async throws {
        try await change([folderID]) {
            try await withThrowingTaskGroup(of: Void.self) { group in
                for item in items {
                    group.addTask { [service] in
                        switch item {
                        case .file(let f): try await service.deleteFile(f.id)
                        case .folder(let f): try await service.deleteFolder(f.id)
                        }
                    }
                }
                var failure: Error?
                while let result = await group.nextResult() { if case .failure(let e) = result { failure = failure ?? e } }
                if let failure { throw failure }
            }
        }
        for item in items {
            unlockedURLs[item.rawID] = nil
            listings[item.rawID] = nil
            // A deleted item's lock would only grow the map.
            if faceIDLock(for: item.rawID) != nil { try? await setFaceIDLock(item, strict: nil) }
        }
    }

    func transcode(_ file: OrbitFile, in folderID: String?) async throws {
        try await change([folderID]) { _ = try await service.transcode(file.id) }
    }

    func convertAll() async throws -> Int {
        let n = try await service.convertAll()
        for key in listings.keys { await refresh(key == "root" ? nil : key) }
        return n
    }

    func loadSettings() async {
        if let s = try? await service.settings() { settings = s }
    }

    func saveSettings(_ next: OrbitSettings) async throws {
        let previous = settings
        settings = next
        do {
            settings = try await service.saveSettings(next)
        } catch {
            settings = previous
            throw error
        }
    }

    /// A finished upload shows up in its folder.
    func uploaded(into folderID: String?) async {
        await refresh(folderID)
    }

    /// A folder as last listed anywhere, for its name and password state.
    func folder(_ id: String) -> OrbitFolder? {
        for l in listings.values { if let f = l.folders.first(where: { $0.id == id }) { return f } }
        return searchResults?.folders.first { $0.id == id }
    }

    /// The freshest copy of a file, for a preview that follows a conversion.
    func file(_ id: String) -> OrbitFile? {
        for l in listings.values { if let f = l.files.first(where: { $0.id == id }) { return f } }
        return searchResults?.files.first { $0.id == id }
    }
}
