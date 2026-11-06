import XCTest
@testable import Orbit

final class FormattingTests: XCTestCase {
    func testSizes() {
        XCTAssertEqual(Formatting.size(0), "0 B")
        XCTAssertEqual(Formatting.size(512), "512 B")
        XCTAssertEqual(Formatting.size(1536), "1.5 KB")
        XCTAssertEqual(Formatting.size(5 * 1024 * 1024), "5.0 MB")
    }

    func testRelativeDates() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertEqual(Formatting.relative(now, now: now), "Just now")
        XCTAssertEqual(Formatting.relative(now.addingTimeInterval(-300), now: now), "5m ago")
        XCTAssertEqual(Formatting.relative(now.addingTimeInterval(-3 * 3600), now: now), "3h ago")
        XCTAssertEqual(Formatting.relative(now.addingTimeInterval(-2 * 86400), now: now), "2d ago")
        let old = now.addingTimeInterval(-10 * 86400)
        XCTAssertEqual(Formatting.relative(old, now: now), old.formatted(.dateTime.month(.abbreviated).day()))
    }

    func testFileKinds() {
        XCTAssertEqual(FileKind(mime: "image/heic"), .image)
        XCTAssertTrue(FileKind.canConvert(mime: "image/heic", status: .none))
        XCTAssertFalse(FileKind.canConvert(mime: "image/png", status: .none))
        XCTAssertTrue(FileKind.canConvert(mime: "video/quicktime", status: .failed))
        XCTAssertFalse(FileKind.canConvert(mime: "video/mp4", status: .done))
        XCTAssertFalse(FileKind.canConvert(mime: "video/mp4", status: .pending))
        XCTAssertEqual(FileKind(mime: "application/zip"), .archive)
        XCTAssertEqual(FileKind(mime: "application/json"), .code)
        XCTAssertEqual(FileKind(mime: "text/plain"), .text)
        XCTAssertEqual(FileKind(mime: "application/pdf"), .pdf)
        XCTAssertEqual(FileKind(mime: "audio/mpeg"), .audio)
        XCTAssertEqual(FileKind(mime: "application/octet-stream"), .other)
        XCTAssertTrue(FileKind(mime: "application/x-yaml").hasTextPreview)
    }
}
