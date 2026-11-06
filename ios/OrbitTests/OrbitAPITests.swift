import XCTest
@testable import Orbit

final class OrbitAPITests: XCTestCase {
    static let browse = Data(#"""
    {"folders":[{"_id":"f1","profileId":"p","name":"Work","parentId":null,"userId":"u","groupId":null,"ownerId":null,
      "isGroupRoot":false,"createdAt":"2026-11-01T10:00:00.000Z","updatedAt":"2026-11-01T10:00:00.000Z","__v":0,
      "protected":true,"shared":false,"locked":false,"canEdit":true}],
     "files":[{"_id":"a1","profileId":"p","filename":"Žluťoučký.pdf","objectKey":"uploads/p/x.pdf","mimeType":"application/pdf",
      "size":1536,"folderId":"f0","userId":"u","groupId":null,"ownerId":null,"transcodeStatus":"none",
      "createdAt":"2026-11-02T08:30:00.123Z","updatedAt":"2026-11-02T08:30:00.123Z","__v":0,"shared":false,"canEdit":true,
      "url":"/api/orbit/files/a1/raw"},
      {"_id":"a2","filename":"secret.mov","mimeType":"video/quicktime","size":10,"folderId":null,"transcodeStatus":"processing",
      "transcodeProgress":42,"transcodeEta":12.5,"createdAt":"2026-11-02T08:30:00Z","updatedAt":"2026-11-02T08:30:00Z",
      "shared":true,"canEdit":false,"protected":true}],
     "breadcrumbs":[{"_id":"f0","name":"Home stuff"}]}
    """#.utf8)

    func testDecodesBrowse() throws {
        let listing = try OrbitAPI.listing(Self.browse)
        XCTAssertEqual(listing.folders.map(\.id), ["f1"])
        XCTAssertTrue(listing.folders[0].protected)
        XCTAssertFalse(listing.folders[0].isGroupRoot)
        XCTAssertEqual(listing.files[0].filename, "Žluťoučký.pdf")
        XCTAssertEqual(listing.files[0].size, 1536)
        XCTAssertNil(listing.files[0].transcodeProgress)
        XCTAssertFalse(listing.files[0].isLocked)
        XCTAssertEqual(listing.files[0].folderId, "f0")
        XCTAssertEqual(listing.files[1].transcodeStatus, .processing)
        XCTAssertEqual(listing.files[1].transcodeProgress, 42)
        XCTAssertTrue(listing.files[1].isLocked)
        XCTAssertEqual(listing.breadcrumbs, [Breadcrumb(id: "f0", name: "Home stuff")])
        XCTAssertEqual(listing.files[0].createdAt.timeIntervalSince1970, 1_793_608_200.123, accuracy: 0.01)
    }

    func testErrorShapes() {
        func err(_ status: Int, _ body: String) -> OrbitError { OrbitAPI.error(status: status, data: Data(body.utf8)) }
        XCTAssertEqual(err(401, #"{"locked":true}"#), .folderLocked)
        XCTAssertEqual(err(401, #"{"error":"Wrong password"}"#), .wrongPassword)
        XCTAssertEqual(err(403, #"{"error":{"code":"forbidden","message":"x"}}"#), .forbidden)
        XCTAssertEqual(err(403, #"{"error":"Locked"}"#), .forbidden)
        XCTAssertEqual(err(404, #"{"error":"Not found"}"#), .notFound)
        XCTAssertEqual(err(413, ""), .tooLarge)
        XCTAssertEqual(err(500, #"{"error":"boom"}"#), .server(500, "boom"))
        XCTAssertEqual(err(400, #"{"error":{"code":"bad","message":"Nope"}}"#), .server(400, "Nope"))
        XCTAssertEqual(err(502, "<html>"), .server(502, "HTTP 502"))
    }

    func testResolvesRelativeURLs() {
        let origin = URL(string: "http://nas.local:8080")!
        XCTAssertEqual(OrbitAPI.absolute("/api/orbit/files/a1/raw?t=abc", origin: origin).absoluteString,
                       "http://nas.local:8080/api/orbit/files/a1/raw?t=abc")
    }

    func testOnlyAuth401sRefreshTheToken() {
        XCTAssertFalse(OrbitAPI.shouldRefresh(after: Data(#"{"locked":true}"#.utf8)))
        XCTAssertFalse(OrbitAPI.shouldRefresh(after: Data(#"{"error":"Wrong password"}"#.utf8)))
        XCTAssertTrue(OrbitAPI.shouldRefresh(after: Data(#"{"error":{"code":"unauthorized","message":"Token expired"}}"#.utf8)))
        XCTAssertTrue(OrbitAPI.shouldRefresh(after: Data()))
    }
}
