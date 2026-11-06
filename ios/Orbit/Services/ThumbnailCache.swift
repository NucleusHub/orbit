import ImageIO
import UIKit

/// Downsampled image thumbnails, loaded through the service so they carry the sign-in.
@MainActor
final class ThumbnailCache {
    static let shared = ThumbnailCache()
    private let cache = NSCache<NSString, UIImage>()

    init() { cache.totalCostLimit = 64 * 1024 * 1024 }

    func cached(_ key: String) -> UIImage? { cache.object(forKey: key as NSString) }

    func image(for file: OrbitFile, store: FilesStore, maxPixel: CGFloat) async -> UIImage? {
        let key = "\(file.id)-\(file.updatedAt.timeIntervalSince1970)-\(Int(maxPixel))"
        if let hit = cached(key) { return hit }
        guard let data = try? await store.data(for: file) else { return nil }
        let image = await Task.detached { Self.downsample(data, maxPixel: maxPixel) }.value
        if let image { cache.setObject(image, forKey: key as NSString, cost: Int(image.size.width * image.size.height * image.scale * image.scale * 4)) }
        return image
    }

    func clear() { cache.removeAllObjects() }

    nonisolated static func downsample(_ data: Data, maxPixel: CGFloat) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary).map { UIImage(cgImage: $0) }
    }
}
