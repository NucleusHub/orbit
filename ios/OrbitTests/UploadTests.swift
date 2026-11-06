import XCTest
@testable import Orbit

final class FolderUploadPlanTests: XCTestCase {
    func testFoldersShallowestFirst() {
        let root = URL(fileURLWithPath: "/tmp/Trip")
        let plan = FolderUploadPlan(root: root, files: [
            root.appending(path: "b/c.txt"), root.appending(path: "d.txt"), root.appending(path: "b/e/f.jpg"),
        ])
        XCTAssertEqual(plan.folders, [["Trip"], ["Trip", "b"], ["Trip", "b", "e"]])
        XCTAssertEqual(plan.folderPath(for: root.appending(path: "b/e/f.jpg")), ["Trip", "b", "e"])
        XCTAssertEqual(plan.folderPath(for: root.appending(path: "d.txt")), ["Trip"])
    }
}

@MainActor
final class UploadQueueTests: XCTestCase {
    private func temp(_ name: String, bytes: Int = 10) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appending(path: name)
        try Data(repeating: 7, count: bytes).write(to: url)
        return url
    }

    private func waitUntil(_ timeout: TimeInterval = 10, _ condition: () -> Bool) async {
        let end = Date().addingTimeInterval(timeout)
        while !condition(), Date() < end { try? await Task.sleep(for: .milliseconds(20)) }
    }

    func testRunsAtMostFourAndRefreshesFolder() async throws {
        let service = SampleFiles(seeded: false)
        service.delay = .milliseconds(60)
        let store = FilesStore(service: service)
        try await store.load(nil)
        let queue = UploadQueue(store: store, maxConcurrent: 4, doneLinger: .milliseconds(50))
        queue.enqueue(try (0..<7).map { try temp("f\($0).txt") }, into: nil)
        var peak = 0
        await waitUntil {
            peak = max(peak, queue.items.filter { $0.state == .uploading }.count)
            return queue.items.isEmpty && !queue.isPreparing
        }
        XCTAssertEqual(peak, 4)
        XCTAssertEqual(store.listing(nil)?.files.count, 7)
    }

    func testFailureStaysWithMessage() async throws {
        let store = FilesStore(service: SampleFiles(seeded: false))
        let queue = UploadQueue(store: store, doneLinger: .milliseconds(50))
        queue.enqueue([try temp("empty.txt", bytes: 0)], into: nil)
        await waitUntil { queue.items.first?.state.isFailed == true }
        guard case .failed(let message) = queue.items.first?.state else { return XCTFail("not failed") }
        XCTAssertFalse(message.isEmpty)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(queue.items.count, 1, "failed uploads wait to be dismissed")
        queue.dismiss(queue.items[0].id)
        XCTAssertTrue(queue.items.isEmpty)
    }

    func testFolderUploadRecreatesHierarchy() async throws {
        let service = SampleFiles(seeded: false)
        let store = FilesStore(service: service)
        let root = FileManager.default.temporaryDirectory.appending(path: "Trip-\(UUID().uuidString.prefix(4))")
        try FileManager.default.createDirectory(at: root.appending(path: "day1"), withIntermediateDirectories: true)
        try Data("a".utf8).write(to: root.appending(path: "notes.txt"))
        try Data("b".utf8).write(to: root.appending(path: "day1/photo.jpg"))
        let queue = UploadQueue(store: store, doneLinger: .milliseconds(10))
        queue.enqueueFolder(root, into: nil)
        await waitUntil { queue.items.isEmpty && !queue.isPreparing }
        let top = try await service.browse(nil, password: nil)
        let trip = try XCTUnwrap(top.folders.first)
        XCTAssertEqual(trip.name, root.lastPathComponent)
        let inside = try await service.browse(trip.id, password: nil)
        XCTAssertEqual(inside.files.map(\.filename), ["notes.txt"])
        XCTAssertEqual(inside.folders.map(\.name), ["day1"])
        let day1 = try await service.browse(inside.folders[0].id, password: nil)
        XCTAssertEqual(day1.files.map(\.filename), ["photo.jpg"])
    }

    func testSignOutDropsPendingUploads() async throws {
        let service = SampleFiles(seeded: false)
        service.delay = .milliseconds(300)
        let store = FilesStore(service: service)
        let queue = UploadQueue(store: store, maxConcurrent: 1)
        queue.enqueue(try (0..<3).map { try temp("p\($0).txt") }, into: nil)
        await waitUntil { queue.items.count == 3 }
        queue.cancelAll()
        XCTAssertTrue(queue.items.isEmpty)
        try await Task.sleep(for: .milliseconds(1500))
        let root = try await service.browse(nil, password: nil)
        XCTAssertTrue(root.files.isEmpty, "nothing reached the server after sign-out")
    }
}
