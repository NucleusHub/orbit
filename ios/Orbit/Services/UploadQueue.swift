import CoreTransferable
import Foundation
import Observation
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct UploadItem: Identifiable, Equatable {
    enum State: Equatable {
        case waiting, uploading, done
        case failed(String)

        var isFailed: Bool { if case .failed = self { true } else { false } }
    }

    let id = UUID()
    let filename: String
    let folderID: String?
    /// A private copy, so picker and security-scoped URLs don't have to outlive the picker.
    let source: URL
    var state: State = .waiting
    var sent: Int64 = 0
    var total: Int64 = 0
    /// Bytes per second, smoothed like the web's upload panel.
    var speed: Double = 0

    var progress: Double { total > 0 ? Double(sent) / Double(total) : 0 }
    var eta: Double? { speed > 0 && total > sent ? Double(total - sent) / speed : nil }
}

/// Uploads, four at a time (the web's useUpload). They run while the app is open, with a short grace period after.
@MainActor
@Observable
final class UploadQueue {
    private(set) var items: [UploadItem] = []
    /// Copying picked files or creating a folder upload's folders.
    private(set) var isPreparing = false
    private let store: FilesStore
    private let maxConcurrent: Int
    private let doneLinger: Duration
    @ObservationIgnored private var samples: [UUID: (at: Date, sent: Int64)] = [:]
    @ObservationIgnored private var tasks: [UUID: Task<Void, Never>] = [:]

    init(store: FilesStore, maxConcurrent: Int = 4, doneLinger: Duration = .seconds(2.5)) {
        self.store = store
        self.maxConcurrent = maxConcurrent
        self.doneLinger = doneLinger
    }

    nonisolated static var inbox: URL { FileManager.default.temporaryDirectory.appending(path: "uploads") }

    // MARK: Adding

    func enqueue(_ urls: [URL], into folderID: String?) {
        isPreparing = true
        Task {
            defer { isPreparing = false }
            for url in urls {
                do { add(try Self.copy(url), into: folderID) } catch { failed(url.lastPathComponent, error) }
            }
        }
    }

    func enqueuePhotos(_ picks: [PhotosPickerItem], into folderID: String?) {
        isPreparing = true
        Task {
            defer { isPreparing = false }
            for pick in picks {
                do {
                    guard let media = try await pick.loadTransferable(type: PickedMedia.self) else { continue }
                    add(media.url, into: folderID)
                } catch {
                    failed(String(localized: "Photo"), error)
                }
            }
        }
    }

    /// Recreates the folder's tree on the server, shallowest first, then uploads each file into its folder.
    func enqueueFolder(_ root: URL, into folderID: String?) {
        isPreparing = true
        Task {
            defer { isPreparing = false }
            let scoped = root.startAccessingSecurityScopedResource()
            var copies: [(URL, [String])] = []
            let plan: FolderUploadPlan
            do {
                let found = Self.files(in: root)
                plan = FolderUploadPlan(root: root, files: found)
                for file in found { copies.append((try Self.copy(file), plan.folderPath(for: file))) }
            } catch {
                if scoped { root.stopAccessingSecurityScopedResource() }
                failed(root.lastPathComponent, error)
                return
            }
            if scoped { root.stopAccessingSecurityScopedResource() }
            var ids: [[String]: String] = [:]
            do {
                for path in plan.folders {
                    let parent = path.count == 1 ? folderID : ids[Array(path.dropLast())]
                    ids[path] = try await store.service.createFolder(name: path.last!, parentID: parent).id
                }
            } catch {
                failed(root.lastPathComponent, error)
                return
            }
            await store.refresh(folderID)
            for (copy, path) in copies { add(copy, into: ids[path] ?? folderID) }
        }
    }

    /// Signing out: nothing more goes to that account.
    func cancelAll() {
        for task in tasks.values { task.cancel() }
        tasks = [:]
        for item in items { try? FileManager.default.removeItem(at: item.source.deletingLastPathComponent()) }
        items = []
    }

    func dismiss(_ id: UUID) {
        tasks[id]?.cancel()
        tasks[id] = nil
        if let item = items.first(where: { $0.id == id }) { try? FileManager.default.removeItem(at: item.source.deletingLastPathComponent()) }
        items.removeAll { $0.id == id }
        pump()
    }

    // MARK: Running

    private func add(_ source: URL, into folderID: String?) {
        items.append(UploadItem(filename: source.lastPathComponent, folderID: folderID, source: source))
        pump()
    }

    private func failed(_ name: String, _ error: Error) {
        var item = UploadItem(filename: name, folderID: nil, source: Self.inbox.appending(path: "missing/\(name)"))
        item.state = .failed(error.orbitMessage)
        items.append(item)
    }

    private func pump() {
        while items.filter({ $0.state == .uploading }).count < maxConcurrent, let next = items.firstIndex(where: { $0.state == .waiting }) {
            items[next].state = .uploading
            let item = items[next]
            tasks[item.id] = Task { await run(item) }
        }
    }

    private func run(_ item: UploadItem) async {
        let background = UIApplication.shared.beginBackgroundTask(withName: "upload \(item.filename)")
        defer { UIApplication.shared.endBackgroundTask(background) }
        let mime = UTType(filenameExtension: item.source.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        do {
            _ = try await store.service.upload(item.source, filename: item.filename, mimeType: mime, folderID: item.folderID) { [weak self] sent, total in
                Task { @MainActor in self?.progress(item.id, sent: sent, total: total) }
            }
            update(item.id) { $0.state = .done; $0.sent = $0.total }
            await store.uploaded(into: item.folderID)
            try? FileManager.default.removeItem(at: item.source.deletingLastPathComponent())
            tasks[item.id] = nil
            pump()
            try? await Task.sleep(for: doneLinger)
            items.removeAll { $0.id == item.id }
        } catch {
            if Task.isCancelled { return }
            update(item.id) { $0.state = .failed(error.orbitMessage) }
            tasks[item.id] = nil
            pump()
        }
    }

    private func progress(_ id: UUID, sent: Int64, total: Int64) {
        let now = Date()
        let last = samples[id]
        update(id) { item in
            guard item.state == .uploading else { return }
            item.sent = sent
            item.total = total
            if let last {
                let dt = now.timeIntervalSince(last.at)
                guard dt >= 0.25 else { return }
                let instant = Double(sent - last.sent) / dt
                item.speed = item.speed == 0 ? instant : 0.3 * instant + 0.7 * item.speed
            }
            samples[id] = (now, sent)
        }
        if last == nil { samples[id] = (now, sent) }
    }

    private func update(_ id: UUID, _ change: (inout UploadItem) -> Void) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        change(&items[i])
    }

    // MARK: Files

    nonisolated static func copy(_ url: URL) throws -> URL {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let dir = inbox.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let out = dir.appending(path: url.lastPathComponent)
        try FileManager.default.copyItem(at: url, to: out)
        return out
    }

    nonisolated static func files(in root: URL) -> [URL] {
        let keys: [URLResourceKey] = [.isRegularFileKey]
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        return walker.compactMap { $0 as? URL }.filter { (try? $0.resourceValues(forKeys: Set(keys)).isRegularFile) == true }
    }
}

/// Which folders a folder upload creates, by path from the picked folder's name down.
struct FolderUploadPlan {
    let root: URL
    let folders: [[String]]

    init(root: URL, files: [URL]) {
        self.root = root
        let base = root.standardizedFileURL.pathComponents.count
        var all: Set<[String]> = [[root.lastPathComponent]]
        for file in files {
            let rel = Array(file.standardizedFileURL.pathComponents.dropFirst(base).dropLast())
            for depth in 0...rel.count { all.insert([root.lastPathComponent] + rel.prefix(depth)) }
        }
        folders = all.sorted { $0.count != $1.count ? $0.count < $1.count : $0.joined(separator: "/") < $1.joined(separator: "/") }
    }

    func folderPath(for file: URL) -> [String] {
        let base = root.standardizedFileURL.pathComponents.count
        return [root.lastPathComponent] + file.standardizedFileURL.pathComponents.dropFirst(base).dropLast()
    }
}

/// A photo or video from the Photos picker, as its original file.
struct PickedMedia: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { received in PickedMedia(url: try UploadQueue.copy(received.file)) }
        FileRepresentation(importedContentType: .image) { received in PickedMedia(url: try UploadQueue.copy(received.file)) }
    }
}
