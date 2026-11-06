import UIKit

/// An in-memory Orbit server that follows the real one's rules, for previews, screenshots and tests.
final class SampleFiles: FilesService, @unchecked Sendable {
    private struct Item {
        var file: OrbitFile
        var data: Data
        var password: String?
    }

    private struct Folder {
        var folder: OrbitFolder
        var password: String?
    }

    private let lock = NSLock()
    private var folders: [String: Folder] = [:]
    private var items: [String: Item] = [:]
    private var current = OrbitSettings(transcodeVideos: true, convertImages: true)
    /// Makes `settings()` fail, to test that locks fail closed.
    var failSettings = false
    /// Simulated network time per request.
    var delay: Duration = .zero
    private var nextID = 0

    init(seeded: Bool = true) {
        if seeded { seed() }
    }

    // MARK: FilesService

    func browse(_ folderID: String?, password: String?) async throws -> Listing {
        try await pause()
        return try lock.withLock {
            var crumbs: [Breadcrumb] = []
            if let folderID {
                guard let f = folders[folderID] else { throw OrbitError.notFound }
                if let pw = f.password, pw != password { throw OrbitError.folderLocked }
                var at: String? = folderID
                while let id = at, let node = folders[id] {
                    crumbs.insert(Breadcrumb(id: id, name: node.folder.name), at: 0)
                    at = node.folder.parentId
                }
            }
            advanceTranscodes()
            let unlocked = folderID.flatMap { folders[$0]?.password } != nil
            let subfolders = folders.values.filter { $0.folder.parentId == folderID }.map(serialize)
                .sorted { ($0.isGroupRoot ? 0 : 1, $0.name.lowercased()) < ($1.isGroupRoot ? 0 : 1, $1.name.lowercased()) }
            let files = items.values.filter { $0.file.folderId == folderID }.map { serialize($0, token: unlocked) }
                .sorted { $0.createdAt > $1.createdAt }
            return Listing(folders: subfolders, files: files, breadcrumbs: crumbs)
        }
    }

    func search(_ query: String) async throws -> Listing {
        try await pause()
        return lock.withLock {
            let q = query.lowercased()
            let fs = folders.values.filter { $0.folder.name.lowercased().contains(q) }.map(serialize).sorted { $0.name < $1.name }
            let files = items.values.filter { $0.file.filename.lowercased().contains(q) }.map { serialize($0, token: false) }
                .sorted { $0.createdAt > $1.createdAt }
            return Listing(folders: fs, files: files)
        }
    }

    func allFolders() async throws -> [OrbitFolder] {
        try await pause()
        return lock.withLock { folders.values.map(serialize).sorted { $0.name.lowercased() < $1.name.lowercased() } }
    }

    func createFolder(name: String, parentID: String?) async throws -> OrbitFolder {
        try await pause()
        return lock.withLock {
            let parent = parentID.flatMap { folders[$0]?.folder }
            let f = OrbitFolder(id: newID(), name: name, parentId: parentID, shared: parent?.shared ?? false)
            folders[f.id] = Folder(folder: f)
            return serialize(folders[f.id]!)
        }
    }

    func renameFolder(_ id: String, to name: String) async throws -> OrbitFolder {
        try await pause()
        return try lock.withLock {
            guard var f = folders[id], f.folder.canEdit else { throw OrbitError.notFound }
            f.folder.name = name
            folders[id] = f
            return serialize(f)
        }
    }

    func moveFolder(_ id: String, to parentID: String?) async throws {
        try await pause()
        try lock.withLock {
            guard var f = folders[id], f.folder.canEdit else { throw OrbitError.notFound }
            var at = parentID
            while let a = at {
                if a == id { throw OrbitError.server(400, "Cannot move a folder into itself or its subfolder") }
                at = folders[a]?.folder.parentId
            }
            f.folder.parentId = parentID
            folders[id] = f
        }
    }

    func setFolderPassword(_ id: String, _ password: String?) async throws -> OrbitFolder {
        try await pause()
        return try lock.withLock {
            guard var f = folders[id], f.folder.canEdit else { throw OrbitError.notFound }
            f.password = password?.isEmpty == false ? password : nil
            folders[id] = f
            return serialize(f)
        }
    }

    func verifyFolder(_ id: String, password: String) async throws {
        try await pause()
        try lock.withLock {
            guard let f = folders[id] else { throw OrbitError.notFound }
            if let pw = f.password, pw != password { throw OrbitError.wrongPassword }
        }
    }

    func deleteFolder(_ id: String) async throws {
        try await pause()
        try lock.withLock {
            guard folders[id]?.folder.canEdit == true else { throw OrbitError.notFound }
            var doomed: Set<String> = [id]
            var grew = true
            while grew {
                let next = Set(folders.values.filter { $0.folder.parentId.map(doomed.contains) == true }.map(\.folder.id)).union(doomed)
                grew = next.count > doomed.count
                doomed = next
            }
            doomed.forEach { folders[$0] = nil }
            items = items.filter { !($0.value.file.folderId.map(doomed.contains) ?? false) }
        }
    }

    func renameFile(_ id: String, to name: String) async throws -> OrbitFile {
        try await editFile(id) { $0.file.filename = name }
    }

    func moveFile(_ id: String, to folderID: String?) async throws {
        _ = try await editFile(id) { $0.file.folderId = folderID }
    }

    func setFilePassword(_ id: String, _ password: String?) async throws -> OrbitFile {
        try await editFile(id) { $0.password = password?.isEmpty == false ? password : nil }
    }

    func unlockFile(_ id: String, password: String) async throws -> String {
        try await pause()
        return try lock.withLock {
            guard let item = items[id] else { throw OrbitError.notFound }
            guard let pw = lockPassword(item) else { return rawURL(id, token: false) }
            guard pw == password else { throw OrbitError.wrongPassword }
            return rawURL(id, token: true)
        }
    }

    func transcode(_ id: String) async throws -> OrbitFile {
        try await editFile(id) { item in
            guard FileKind.canConvert(mime: item.file.mimeType, status: .none) else { return }
            item.file.transcodeStatus = .pending
        }
    }

    func convertAll() async throws -> Int {
        try await pause()
        return lock.withLock {
            let ids = items.values.filter(\.file.canConvert).map(\.file.id)
            ids.forEach { items[$0]?.file.transcodeStatus = .pending }
            return ids.count
        }
    }

    func deleteFile(_ id: String) async throws {
        try await pause()
        try lock.withLock {
            guard items[id]?.file.canEdit == true else { throw OrbitError.notFound }
            items[id] = nil
        }
    }

    func settings() async throws -> OrbitSettings {
        try await pause()
        if failSettings { throw OrbitError.server(500, "Settings unavailable") }
        return lock.withLock { current }
    }

    func saveSettings(_ settings: OrbitSettings) async throws -> OrbitSettings {
        try await pause()
        return lock.withLock { current = settings; return current }
    }

    func setFaceIDLock(_ itemID: String, strict: Bool?) async throws -> OrbitSettings {
        try await pause()
        return lock.withLock {
            current.faceIdLocks[itemID] = strict.map(FaceIDLock.init)
            return current
        }
    }

    func upload(_ file: URL, filename: String, mimeType: String, folderID: String?,
                progress: @escaping @Sendable (Int64, Int64) -> Void) async throws -> OrbitFile {
        let data = try Data(contentsOf: file)
        if data.isEmpty { throw OrbitError.server(400, String(localized: "The file is empty.")) }
        let total = Int64(data.count)
        for step in 1...4 {
            try await pause()
            try Task.checkCancellation()
            progress(total * Int64(step) / 4, total)
        }
        return lock.withLock {
            let shared = folderID.flatMap { folders[$0]?.folder.shared } ?? false
            var f = OrbitFile(id: newID(), filename: filename, mimeType: mimeType, size: total, folderId: folderID, shared: shared)
            if current.convertImages, FileKind.canConvert(mime: mimeType, status: .none), mimeType.hasPrefix("image/") { f.transcodeStatus = .pending }
            if current.transcodeVideos, mimeType.hasPrefix("video/") { f.transcodeStatus = .pending }
            items[f.id] = Item(file: f, data: data)
            return serialize(items[f.id]!, token: false)
        }
    }

    func probe(at path: String) async throws { _ = try await data(at: path) }

    func download(at path: String) async throws -> URL {
        let bytes = try await data(at: path)
        let url = FileManager.default.temporaryDirectory.appending(path: "download-\(UUID().uuidString)")
        try bytes.write(to: url)
        return url
    }

    func data(at path: String) async throws -> Data {
        try await pause()
        return try lock.withLock {
            let parts = path.split(separator: "/")
            guard let i = parts.firstIndex(of: "files"), i + 1 < parts.count, let item = items[String(parts[i + 1])] else { throw OrbitError.notFound }
            if lockPassword(item) != nil, !path.contains("?t=") { throw OrbitError.forbidden }
            return item.data
        }
    }

    func streamRequest(for path: String) async throws -> (URL, [String: String]) {
        // Placeholder bytes can't play; every sample stream is a short generated clip.
        _ = try await data(at: path)
        return (try await SampleVideo.url(), [:])
    }

    func renewAccess() async throws {}

    // MARK: Rules

    private func pause() async throws {
        if delay > .zero { try await Task.sleep(for: delay) }
    }

    private func editFile(_ id: String, _ change: (inout Item) -> Void) async throws -> OrbitFile {
        try await pause()
        return try lock.withLock {
            guard var item = items[id], item.file.canEdit else { throw OrbitError.notFound }
            change(&item)
            item.file.updatedAt = Date()
            items[id] = item
            return serialize(item, token: false)
        }
    }

    /// `resolveLock`: the file's own password, else its immediate folder's.
    private func lockPassword(_ item: Item) -> String? {
        item.password ?? item.file.folderId.flatMap { folders[$0]?.password }
    }

    private func rawURL(_ id: String, token: Bool) -> String { "/api/orbit/files/\(id)/raw" + (token ? "?t=sample" : "") }

    private func serialize(_ f: Folder) -> OrbitFolder {
        var out = f.folder
        out.protected = f.password != nil
        return out
    }

    private func serialize(_ item: Item, token: Bool) -> OrbitFile {
        var out = item.file
        out.protected = item.password != nil
        out.url = item.password != nil ? nil : rawURL(out.id, token: token && lockPassword(item) != nil)
        return out
    }

    /// Each look moves a conversion along, so polling shows progress.
    private func advanceTranscodes() {
        for (id, item) in items where item.file.transcodeStatus.isActive {
            var f = item.file
            let next = (f.transcodeProgress ?? 0) + 34
            if next >= 100 {
                f.transcodeStatus = .done
                f.transcodeProgress = nil
                f.transcodeEta = nil
            } else {
                f.transcodeStatus = .processing
                f.transcodeProgress = next
                f.transcodeEta = Double(100 - next) / 10
            }
            items[id]?.file = f
        }
    }

    private func newID() -> String {
        nextID += 1
        return String(format: "s%05d", nextID)
    }

    // MARK: Seed

    private func seed() {
        let now = Date()
        func folder(_ name: String, in parent: String? = nil, password: String? = nil, group: Bool = false) -> String {
            let f = OrbitFolder(id: newID(), name: name, parentId: parent, shared: group, isGroupRoot: group && parent == nil,
                                canEdit: !(group && parent == nil), createdAt: now)
            folders[f.id] = Folder(folder: f, password: password)
            return f.id
        }
        func file(_ name: String, _ mime: String, in parent: String?, ago hours: Double, data: Data, size: Int64? = nil,
                  status: TranscodeStatus = .none, password: String? = nil, shared: Bool = false) {
            let f = OrbitFile(id: newID(), filename: name, mimeType: mime, size: size ?? Int64(data.count), folderId: parent,
                              transcodeStatus: status, transcodeProgress: status == .processing ? 30 : nil, transcodeEta: status == .processing ? 42 : nil,
                              shared: shared, createdAt: now.addingTimeInterval(-hours * 3600), updatedAt: now)
            items[f.id] = Item(file: f, data: data, password: password)
        }

        let family = folder("Group - Family", group: true)
        let photos = folder("Photos")
        let summer = folder("Summer 2026", in: photos)
        let documents = folder("Documents")
        let invoices = folder("Invoices", in: documents)
        let work = folder("Work", password: "orbit")
        _ = folder("Music")

        file("Lake at dawn.jpg", "image/jpeg", in: nil, ago: 0.2, data: Self.image(0x4F46E5, 0x22D3EE))
        file("Team offsite.mov", "video/quicktime", in: nil, ago: 1, data: Data(count: 2048), size: 184_000_000, status: .processing)
        file("Notes.md", "text/markdown", in: nil, ago: 5, data: Data("# Orbit\n\n- Files from anywhere\n- Private folders\n".utf8))
        file("Budget 2027.pdf", "application/pdf", in: nil, ago: 30, data: Self.pdf("Budget 2027"))
        file("Backup.zip", "application/zip", in: nil, ago: 80, data: Data(count: 4096), size: 52_428_800)
        file("Sunset.heic", "image/heic", in: summer, ago: 50, data: Self.image(0xF97316, 0xDB2777))
        file("Mountains.jpg", "image/jpeg", in: summer, ago: 52, data: Self.image(0x059669, 0x0EA5E9))
        file("Beach.png", "image/png", in: photos, ago: 70, data: Self.image(0x0EA5E9, 0xFDE68A))
        file("Forest.jpg", "image/jpeg", in: photos, ago: 75, data: Self.image(0x166534, 0x84CC16))
        file("Invoice 0042.pdf", "application/pdf", in: invoices, ago: 200, data: Self.pdf("Invoice 0042"))
        file("config.json", "application/json", in: documents, ago: 300, data: Data(#"{ "theme": "midnight", "sync": true }"#.utf8))
        file("Contract.pdf", "application/pdf", in: work, ago: 12, data: Self.pdf("Contract"))
        file("Salaries.csv", "text/csv", in: work, ago: 14, data: Data("name,amount\nHonza,1\n".utf8))
        file("Passport.jpg", "image/jpeg", in: documents, ago: 400, data: Self.image(0x334155, 0x94A3B8), password: "orbit")
        file("Holiday plan.txt", "text/plain", in: family, ago: 3, data: Data("Pack the tent.\n".utf8), shared: true)
        file("Grandma.jpg", "image/jpeg", in: family, ago: 90, data: Self.image(0xE11D48, 0xFBBF24), shared: true)
    }

    private static func image(_ from: UInt32, _ to: UInt32) -> Data {
        func color(_ hex: UInt32) -> UIColor {
            UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        }
        let size = CGSize(width: 480, height: 360)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.pngData { ctx in
            let colors = [color(from).cgColor, color(to).cgColor] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
            ctx.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
            UIColor.white.withAlphaComponent(0.35).setFill()
            ctx.cgContext.fillEllipse(in: CGRect(x: 300, y: 50, width: 90, height: 90))
        }
    }

    private static func pdf(_ title: String) -> Data {
        UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 595, height: 842)).pdfData { ctx in
            ctx.beginPage()
            (title as NSString).draw(at: CGPoint(x: 60, y: 80), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 32)])
            ("A sample document in Orbit." as NSString).draw(at: CGPoint(x: 60, y: 140), withAttributes: [.font: UIFont.systemFont(ofSize: 16)])
        }
    }
}

import AVFoundation

/// A four-second clip of moving color, made once, so sample videos really play.
enum SampleVideo {
    @MainActor private static var made: URL?

    @MainActor
    static func url() async throws -> URL {
        if let made, FileManager.default.fileExists(atPath: made.path) { return made }
        let url = FileManager.default.temporaryDirectory.appending(path: "orbit-sample.mp4")
        try? FileManager.default.removeItem(at: url)
        let size = CGSize(width: 640, height: 360)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: size.width, AVVideoHeightKey: size.height,
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: size.width, kCVPixelBufferHeightKey as String: size.height,
        ])
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        let frames = 4 * 15
        for i in 0..<frames {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
            guard let pool = adaptor.pixelBufferPool else { break }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
            guard let buffer else { break }
            CVPixelBufferLockBaseAddress(buffer, [])
            if let ctx = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
                                   bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpaceCreateDeviceRGB(),
                                   bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue) {
                let t = CGFloat(i) / CGFloat(frames)
                ctx.setFillColor(UIColor(hue: 0.7 - t * 0.4, saturation: 0.7, brightness: 0.8, alpha: 1).cgColor)
                ctx.fill(CGRect(origin: .zero, size: size))
                ctx.setFillColor(UIColor.white.withAlphaComponent(0.8).cgColor)
                ctx.fillEllipse(in: CGRect(x: 40 + t * 480, y: 130, width: 100, height: 100))
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(i), timescale: 15))
        }
        input.markAsFinished()
        await writer.finishWriting()
        made = url
        return url
    }
}
