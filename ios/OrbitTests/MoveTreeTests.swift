import XCTest
@testable import Orbit

final class MoveTreeTests: XCTestCase {
    private let a = OrbitFolder(id: "a", name: "A")
    private let b = OrbitFolder(id: "b", name: "B", parentId: "a")
    private let c = OrbitFolder(id: "c", name: "C")
    private let g = OrbitFolder(id: "g", name: "Group - Family", shared: true, isGroupRoot: true, canEdit: false)

    func testExcludesSubtree() {
        let tree = MoveTree(folders: [a, b, c, g], moving: [.folder(a)])
        XCTAssertEqual(tree.roots.map(\.id), ["c", "g"])
        XCTAssertFalse(tree.contains("b"))
    }

    func testCurrentFolderDisabled() {
        let file = OrbitFile(id: "f", filename: "x.txt", mimeType: "text/plain", size: 1, folderId: "c")
        let tree = MoveTree(folders: [a, b, c], moving: [.file(file)])
        XCTAssertTrue(tree.isDisabled("c"))
        XCTAssertFalse(tree.isDisabled("a"))
        XCTAssertFalse(tree.isDisabled(nil))
        let rootFile = OrbitFile(id: "r", filename: "y.txt", mimeType: "text/plain", size: 1)
        XCTAssertTrue(MoveTree(folders: [a], moving: [.file(rootFile)]).isDisabled(nil))
        // Items from different folders can go anywhere either isn't already.
        XCTAssertFalse(MoveTree(folders: [a, c], moving: [.file(file), .file(rootFile)]).isDisabled(nil))
    }

    func testGroupRootsListedAndNested() {
        let tree = MoveTree(folders: [b, a, g, c], moving: [])
        XCTAssertEqual(tree.roots.map(\.id), ["a", "c", "g"])
        XCTAssertEqual(tree.roots.first?.children.map(\.id), ["b"])
    }

    func testSealedFoldersHideTheirInsides() {
        let tree = MoveTree(folders: [a, b, c], moving: [], sealed: ["a"])
        XCTAssertEqual(tree.roots.first { $0.id == "a" }?.children.count, 0)
        XCTAssertTrue(tree.isDisabled("a"), "a locked folder isn't a target until it's unlocked")
        XCTAssertFalse(tree.contains("b"))
    }
}
