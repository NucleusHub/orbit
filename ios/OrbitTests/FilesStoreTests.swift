import XCTest
@testable import Orbit

@MainActor
final class FilesStoreTests: XCTestCase {
    private func work(_ store: FilesStore) async throws -> OrbitFolder {
        try await store.load(nil)
        return store.listing(nil)!.folders.first { $0.name == "Work" }!
    }

    func testWrongFolderPasswordKeepsPromptWithError() async throws {
        let store = FilesStore(service: SampleFiles())
        let work = try await work(store)
        do {
            try await store.load(work.id)
            XCTFail("opened a protected folder")
        } catch {
            XCTAssertEqual(error as? OrbitError, .folderLocked)
        }
        do {
            try await store.open(folderID: work.id, password: "nope")
            XCTFail("wrong password accepted")
        } catch {
            XCTAssertEqual(error as? OrbitError, .wrongPassword)
        }
        XCTAssertNil(store.listing(work.id))
        XCTAssertTrue(store.needsVerification(.folder(work)))
        try await store.open(folderID: work.id, password: "orbit")
        XCTAssertEqual(store.listing(work.id)?.files.count, 2)
        XCTAssertFalse(store.needsVerification(.folder(work)))
        // Later loads reuse the remembered password, like the web's sessionStorage.
        try await store.load(work.id)
    }

    func testForbiddenRawFallsBackToUnlock() async throws {
        let store = FilesStore(service: SampleFiles())
        try await store.search("contract")
        let hit = store.searchResults!.files.first!
        XCTAssertNotNil(store.resolvedURL(for: hit))
        do {
            _ = try await store.data(for: hit)
            XCTFail("read a locked file")
        } catch {
            XCTAssertEqual(error as? OrbitError, .forbidden)
        }
        XCTAssertNil(store.resolvedURL(for: hit), "a forbidden file goes through the unlock prompt")
        try await store.unlock(hit, password: "orbit")
        XCTAssertTrue(store.resolvedURL(for: hit)!.contains("?t="))
        let data = try await store.data(for: hit)
        XCTAssertFalse(data.isEmpty)
    }

    func testSyncNowReloadsLoadedListings() async throws {
        let service = SampleFiles()
        let store = FilesStore(service: service)
        try await store.load(nil)
        let before = store.listing(nil)!.folders.count
        _ = try await service.createFolder(name: "From another device", parentID: nil)
        XCTAssertEqual(store.listing(nil)!.folders.count, before)
        await store.syncNow()
        XCTAssertEqual(store.listing(nil)!.folders.count, before + 1)
        XCTAssertNotNil(store.lastSynced)
        XCTAssertNil(store.syncError)
        XCTAssertNotNil(store.settings)
    }

    func testForgetClearsSecrets() async throws {
        let store = FilesStore(service: SampleFiles())
        let work = try await work(store)
        try await store.open(folderID: work.id, password: "orbit")
        store.forget()
        XCTAssertNil(store.listing(nil))
        XCTAssertTrue(store.needsVerification(.folder(work)))
        do {
            try await store.load(work.id)
            XCTFail("password survived sign-out")
        } catch {
            XCTAssertEqual(error as? OrbitError, .folderLocked)
        }
    }

    func testMutationReloadsFolderAndPollingFollowsTranscodes() async throws {
        let store = FilesStore(service: SampleFiles())
        try await store.load(nil)
        XCTAssertTrue(store.needsPolling(nil), "the sample video is converting")
        let folder = try await store.createFolder(name: "New", in: nil)
        XCTAssertTrue(store.listing(nil)!.folders.contains(folder))
        try await store.delete([.folder(folder)], from: nil)
        XCTAssertFalse(store.listing(nil)!.folders.contains { $0.id == folder.id })
    }

    // Final review fixes

    func testForbiddenProbeRoutesMediaToUnlock() async throws {
        let store = FilesStore(service: SampleFiles())
        try await store.search("contract")
        let hit = store.searchResults!.files.first!
        do {
            try await store.probe(hit)
            XCTFail("probe passed on a locked file")
        } catch {
            XCTAssertEqual(error as? OrbitError, .forbidden)
        }
        XCTAssertNil(store.resolvedURL(for: hit))
    }

    func testDownloadWritesFileToDisk() async throws {
        let store = FilesStore(service: SampleFiles())
        try await store.load(nil)
        let notes = store.listing(nil)!.files.first { $0.filename == "Notes.md" }!
        let url = try await store.download(notes)
        XCTAssertEqual(url.lastPathComponent, "Notes.md")
        XCTAssertTrue(String(decoding: try Data(contentsOf: url), as: UTF8.self).hasPrefix("# Orbit"))
    }

    func testRefreshFolderOfSearchHitMovesConversion() async throws {
        let store = FilesStore(service: SampleFiles())
        try await store.search("offsite")
        let video = store.searchResults!.files.first!
        let before = video.transcodeProgress ?? 0
        await store.refreshFolder(of: video)
        XCTAssertGreaterThan(store.file(video.id)?.transcodeProgress ?? 100, before)
    }

    func testPartialBulkFailureStillRefreshes() async throws {
        let store = FilesStore(service: SampleFiles())
        try await store.load(nil)
        let root = store.listing(nil)!
        let group = root.folders.first { $0.isGroupRoot }!
        let music = root.folders.first { $0.name == "Music" }!
        do {
            try await store.delete([.folder(music), .folder(group)], from: nil)
            XCTFail("deleting a group root should fail")
        } catch {}
        XCTAssertFalse(store.listing(nil)!.folders.contains { $0.id == music.id }, "the delete that worked shows")
    }

    func testLostPasswordDropsCachedListing() async throws {
        let service = SampleFiles()
        let store = FilesStore(service: service)
        let work = try await work(store)
        try await store.open(folderID: work.id, password: "orbit")
        _ = try await service.setFolderPassword(work.id, "changed")
        do {
            try await store.load(work.id)
            XCTFail("old password still opened it")
        } catch {}
        XCTAssertNil(store.listing(work.id), "nothing protected stays on screen")
    }
}
