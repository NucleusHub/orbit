import XCTest
@testable import Orbit

final class SampleFilesTests: XCTestCase {
    private func folder(_ s: SampleFiles, _ name: String, in parent: String? = nil) async throws -> OrbitFolder {
        try await s.browse(parent, password: nil).folders.first { $0.name == name }!
    }

    func testProtectedFolderNeedsItsPassword() async throws {
        let s = SampleFiles()
        let work = try await folder(s, "Work")
        XCTAssertTrue(work.protected)
        do {
            _ = try await s.browse(work.id, password: nil)
            XCTFail("opened without a password")
        } catch {
            XCTAssertEqual(error as? OrbitError, .folderLocked)
        }
        let inside = try await s.browse(work.id, password: "orbit")
        XCTAssertEqual(inside.breadcrumbs.map(\.name), ["Work"])
        XCTAssertTrue(inside.files.allSatisfy { $0.url?.contains("?t=") == true })
    }

    func testCannotMoveFolderIntoItsSubfolder() async throws {
        let s = SampleFiles()
        let photos = try await folder(s, "Photos")
        let summer = try await folder(s, "Summer 2026", in: photos.id)
        do {
            try await s.moveFolder(photos.id, to: summer.id)
            XCTFail("moved into own subfolder")
        } catch {
            guard case OrbitError.server(400, _) = error else { return XCTFail("\(error)") }
        }
    }

    func testGroupRootComesFirstAndIsReadOnly() async throws {
        let root = try await SampleFiles().browse(nil, password: nil)
        XCTAssertEqual(root.folders.first?.name, "Group - Family")
        XCTAssertEqual(root.folders.first?.canEdit, false)
        XCTAssertEqual(root.files.first?.filename, "Lake at dawn.jpg")
    }

    func testSearchHitInProtectedFolderIsForbiddenRaw() async throws {
        let s = SampleFiles()
        let hit = try await s.search("contract").files.first!
        XCTAssertNotNil(hit.url)
        do {
            _ = try await s.data(at: hit.url!)
            XCTFail("read a locked file")
        } catch {
            XCTAssertEqual(error as? OrbitError, .forbidden)
        }
    }
}
