import AVFoundation
import XCTest
@testable import Orbit

@MainActor
final class SampleVideoTests: XCTestCase {
    func testSampleClipIsPlayable() async throws {
        let url = try await SampleVideo.url()
        let duration = try await AVURLAsset(url: url).load(.duration)
        XCTAssertEqual(duration.seconds, 4, accuracy: 0.2)
    }
}
