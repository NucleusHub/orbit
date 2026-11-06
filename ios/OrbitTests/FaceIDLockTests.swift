import XCTest
@testable import Orbit

/// Scripted Face ID: answers with `next` and records what was asked.
final class FakeAuthenticator: Authenticator, @unchecked Sendable {
    var next: BiometricOutcome = .success
    private(set) var asked: [(strict: Bool, passwordFallback: Bool)] = []

    func authenticate(reason: String, strict: Bool, passwordFallback: Bool) async -> BiometricOutcome {
        asked.append((strict, passwordFallback))
        return next
    }
}

@MainActor
final class FaceIDLockTests: XCTestCase {
    private func setup() async throws -> (FilesStore, FakeAuthenticator, SampleFiles) {
        let service = SampleFiles()
        let auth = FakeAuthenticator()
        let store = FilesStore(service: service, authenticator: auth)
        try await store.load(nil)
        return (store, auth, service)
    }

    private func folder(_ store: FilesStore, _ name: String, in parent: String? = nil) async throws -> OrbitFolder {
        try await store.load(parent)
        return store.listing(parent)!.folders.first { $0.name == name }!
    }

    func testSettingsDecodeLocksAndDefaultToNone() throws {
        let with = try OrbitAPI.decoder().decode(OrbitSettings.self, from: Data(#"{"transcodeVideos":true,"convertImages":false,"faceIdLocks":{"abc":{"strict":true}}}"#.utf8))
        XCTAssertEqual(with.faceIdLocks["abc"], FaceIDLock(strict: true))
        let without = try OrbitAPI.decoder().decode(OrbitSettings.self, from: Data(#"{"transcodeVideos":true,"convertImages":true}"#.utf8))
        XCTAssertTrue(without.faceIdLocks.isEmpty)
    }

    func testLockedFolderCoversItsSubfoldersAndFiles() async throws {
        let (store, _, _) = try await setup()
        let photos = try await folder(store, "Photos")
        try await store.setFaceIDLock(.folder(photos), strict: false)
        let summer = try await folder(store, "Summer 2026", in: photos.id)
        let inside = try await store.service.browse(summer.id, password: nil).files.first!
        await store.loadTree()
        XCTAssertTrue(store.isFaceIDLocked(folderID: photos.id))
        XCTAssertTrue(store.isFaceIDLocked(folderID: summer.id), "a subfolder inherits the lock")
        XCTAssertTrue(store.isFaceIDLocked(.file(inside)))
        XCTAssertFalse(store.isFaceIDLocked(folderID: nil))
    }

    func testUnlockLastsUntilBackground() async throws {
        let (store, auth, _) = try await setup()
        let photos = try await folder(store, "Photos")
        try await store.setFaceIDLock(.folder(photos), strict: false)
        let opened = await store.passFaceID(for: .folder(photos))
        XCTAssertEqual(opened, .success)
        XCTAssertFalse(store.isFaceIDLocked(folderID: photos.id))
        XCTAssertEqual(auth.asked.last?.strict, false)
        store.relockFaceID()
        XCTAssertTrue(store.isFaceIDLocked(folderID: photos.id))
    }

    func testStrictLockHasNoFallbackAndStaysLockedOnFailure() async throws {
        let (store, auth, _) = try await setup()
        let work = try await folder(store, "Work")
        try await store.setFaceIDLock(.folder(work), strict: true)
        auth.next = .failed("Face ID is locked")
        let outcome = await store.passFaceID(for: .folder(work))
        XCTAssertEqual(outcome, .failed("Face ID is locked"))
        XCTAssertEqual(auth.asked.last?.strict, true)
        XCTAssertEqual(auth.asked.last?.passwordFallback, false, "strict never offers the Orbit password")
        XCTAssertTrue(store.isFaceIDLocked(folderID: work.id))
    }

    func testRelaxedLockOnPasswordItemOffersPassword() async throws {
        let (store, auth, _) = try await setup()
        let work = try await folder(store, "Work")
        try await store.setFaceIDLock(.folder(work), strict: false)
        auth.next = .usePassword
        let outcome = await store.passFaceID(for: .folder(work))
        XCTAssertEqual(outcome, .usePassword)
        XCTAssertEqual(auth.asked.last?.passwordFallback, true)
        // The password prompt succeeding counts as passing the lock.
        try await store.open(folderID: work.id, password: "orbit")
        XCTAssertFalse(store.isFaceIDLocked(folderID: work.id))
    }

    func testLocksSyncThroughServerSettings() async throws {
        let (store, _, service) = try await setup()
        let photos = try await folder(store, "Photos")
        try await store.setFaceIDLock(.folder(photos), strict: true)
        let other = FilesStore(service: service, authenticator: FakeAuthenticator())
        await other.syncNow()
        XCTAssertEqual(other.faceIDLock(for: photos.id), FaceIDLock(strict: true), "another device sees it")
        _ = await store.passFaceID(for: .folder(photos))
        try await store.setFaceIDLock(.folder(photos), strict: nil)
        await other.syncNow()
        XCTAssertNil(other.faceIDLock(for: photos.id))
    }

    // Review fixes

    func testUnreadableSettingsFailClosed() async throws {
        let service = SampleFiles()
        service.failSettings = true
        let store = FilesStore(service: service, authenticator: FakeAuthenticator())
        do {
            try await store.load(nil)
            XCTFail("browsed without knowing the locks")
        } catch {}
        XCTAssertNil(store.listing(nil))
        do {
            try await store.search("a")
            XCTFail("searched without knowing the locks")
        } catch {}
        XCTAssertNil(store.searchResults)
    }

    func testSearchHidesWhatsInsideLockedFolders() async throws {
        let (store, _, _) = try await setup()
        let photos = try await folder(store, "Photos")
        try await store.setFaceIDLock(.folder(photos), strict: false)
        try await store.search("summer")
        XCTAssertEqual(store.searchResults?.folders.count, 0, "a subfolder's name stays hidden")
        try await store.search("beach")
        XCTAssertEqual(store.searchResults?.files.count, 0)
        _ = await store.passFaceID(for: .folder(photos))
        XCTAssertEqual(store.searchResults?.files.map(\.filename), ["Beach.png"], "passing the lock shows them")
    }

    func testInnerPasswordDoesNotPassOuterLock() async throws {
        let (store, auth, service) = try await setup()
        let documents = try await folder(store, "Documents")
        let invoices = try await folder(store, "Invoices", in: documents.id)
        _ = try await service.setFolderPassword(invoices.id, "inner")
        try await store.load(documents.id)
        let protectedInvoices = store.listing(documents.id)!.folders.first { $0.id == invoices.id }!
        try await store.setFaceIDLock(.folder(documents), strict: false)
        auth.next = .usePassword
        _ = await store.passFaceID(for: .folder(protectedInvoices))
        XCTAssertEqual(auth.asked.last?.passwordFallback, false, "the password only stands in for the item's own lock")
        try await store.open(folderID: invoices.id, password: "inner")
        XCTAssertTrue(store.isFaceIDLocked(folderID: documents.id))
    }

    func testRelockDropsLockedListings() async throws {
        let (store, _, _) = try await setup()
        let photos = try await folder(store, "Photos")
        try await store.setFaceIDLock(.folder(photos), strict: false)
        _ = await store.passFaceID(for: .folder(photos))
        try await store.load(photos.id)
        XCTAssertNotNil(store.listing(photos.id))
        store.relockFaceID()
        XCTAssertNil(store.listing(photos.id), "nothing from a locked folder stays in memory")
        XCTAssertNotNil(store.listing(nil))
    }

    func testDeletingAnItemDropsItsLock() async throws {
        let (store, _, _) = try await setup()
        let music = try await folder(store, "Music")
        try await store.setFaceIDLock(.folder(music), strict: false)
        _ = await store.passFaceID(for: .folder(music))
        try await store.delete([.folder(music)], from: nil)
        XCTAssertNil(store.faceIDLock(for: music.id))
    }

    // Face ID stands in for a saved Orbit password

    private func vaulted() async throws -> (FilesStore, MemoryVault, SampleFiles, OrbitFolder) {
        let service = SampleFiles()
        let vault = MemoryVault()
        let store = FilesStore(service: service, authenticator: FakeAuthenticator(), vault: vault)
        try await store.load(nil)
        let work = store.listing(nil)!.folders.first { $0.name == "Work" }!
        try await store.setFaceIDLock(.folder(work), strict: true)
        return (store, vault, service, work)
    }

    func testFaceIDFillsInTheSavedPassword() async throws {
        let (store, vault, _, work) = try await vaulted()
        _ = await store.passFaceID(for: .folder(work))
        do {
            try await store.load(work.id)
            XCTFail("the first time needs the password")
        } catch {
            XCTAssertEqual(error as? OrbitError, .folderLocked)
        }
        try await store.open(folderID: work.id, password: "orbit")
        XCTAssertEqual(vault.password(for: work.id), "orbit", "kept on this device for next time")

        store.relockFaceID()
        do {
            try await store.load(work.id)
            XCTFail("relocked, so the saved password mustn't open it without Face ID")
        } catch {}
        _ = await store.passFaceID(for: .folder(work))
        try await store.load(work.id)
        XCTAssertEqual(store.listing(work.id)?.files.count, 2, "Face ID alone opened it")
        XCTAssertFalse(store.needsVerification(.folder(work)), "edits don't ask for the password either")
    }

    func testStaleSavedPasswordIsForgotten() async throws {
        let (store, vault, service, work) = try await vaulted()
        _ = await store.passFaceID(for: .folder(work))
        try await store.open(folderID: work.id, password: "orbit")
        _ = try await service.setFolderPassword(work.id, "changed")
        store.relockFaceID()
        _ = await store.passFaceID(for: .folder(work))
        do {
            try await store.load(work.id)
            XCTFail("old password opened it")
        } catch {
            XCTAssertEqual(error as? OrbitError, .folderLocked)
        }
        XCTAssertNil(vault.password(for: work.id))
    }

    func testFaceIDUnlocksSavedFilePassword() async throws {
        let service = SampleFiles()
        let vault = MemoryVault()
        let store = FilesStore(service: service, authenticator: FakeAuthenticator(), vault: vault)
        try await store.load(nil)
        let documents = store.listing(nil)!.folders.first { $0.name == "Documents" }!
        try await store.load(documents.id)
        let passport = store.listing(documents.id)!.files.first { $0.filename == "Passport.jpg" }!
        try await store.setFaceIDLock(.file(passport), strict: false)
        _ = await store.passFaceID(for: .file(passport))
        try await store.unlock(passport, password: "orbit")
        store.relockFaceID()
        XCTAssertNil(store.resolvedURL(for: passport))
        _ = await store.passFaceID(for: .file(passport))
        let opened = await store.autoUnlock(.file(passport))
        XCTAssertTrue(opened)
        XCTAssertNotNil(store.resolvedURL(for: passport))
    }

    func testSignOutForgetsSavedPasswords() async throws {
        let (store, vault, _, work) = try await vaulted()
        _ = await store.passFaceID(for: .folder(work))
        try await store.open(folderID: work.id, password: "orbit")
        store.forget()
        XCTAssertNil(vault.password(for: work.id))
    }
}
