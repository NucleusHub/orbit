import XCTest
@testable import Orbit

final class DragTests: XCTestCase {
    func testPayloadRoundTrip() {
        let file = OrbitFile(id: "f1", filename: "a.txt", mimeType: "text/plain", size: 1, folderId: "x")
        let folder = OrbitFolder(id: "d1", name: "Docs", parentId: nil)
        XCTAssertEqual(DragPayload(.file(file)).text, "orbit-item:file:f1")
        XCTAssertEqual(DragPayload(text: "orbit-item:folder:d1"), DragPayload(kind: .folder, id: "d1"))
        XCTAssertEqual(DragPayload(.folder(folder)), DragPayload(kind: .folder, id: "d1"))
        XCTAssertNil(DragPayload(text: "hello"), "text dragged in from another app is ignored")
        XCTAssertNil(DragPayload(text: "orbit-item:thing:1"))
    }

    func testDropTargetsRejectSelfAndNoOps() {
        let folder = OrbitFolder(id: "d1", name: "Docs")
        XCTAssertFalse(DragPayload(kind: .folder, id: "d1").canDrop(into: "d1"), "not into itself")
        XCTAssertTrue(DragPayload(kind: .folder, id: "d1").canDrop(into: "d2"))
        XCTAssertTrue(DragPayload(kind: .file, id: "f1").canDrop(into: folder.id))
        XCTAssertTrue(DragPayload(kind: .file, id: "f1").canDrop(into: nil), "Home is a target")
    }
}
