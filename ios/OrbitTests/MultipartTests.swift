import XCTest
@testable import Orbit

final class MultipartTests: XCTestCase {
    func testUTF8Filename() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appending(path: "in.bin")
        try Data("hello".utf8).write(to: file)
        let out = dir.appending(path: "body")
        try Multipart.write(file: file, filename: "Žluťoučký kůň.jpg", mimeType: "image/jpeg",
                            fields: ["folderId": "f1"], boundary: "XYZ", to: out)
        let body = String(decoding: try Data(contentsOf: out), as: UTF8.self)
        XCTAssertTrue(body.hasPrefix("--XYZ\r\nContent-Disposition: form-data; name=\"folderId\"\r\n\r\nf1\r\n"))
        // The server re-decodes multer's latin1 name as UTF-8, so a decoded `filename*` would come out garbled.
        XCTAssertFalse(body.contains("filename*"))
        XCTAssertTrue(body.contains("name=\"file\"; filename=\"Žluťoučký kůň.jpg\""))
        XCTAssertTrue(body.contains("Content-Type: image/jpeg\r\n\r\nhello\r\n"))
        XCTAssertTrue(body.hasSuffix("--XYZ--\r\n"))
    }
}
