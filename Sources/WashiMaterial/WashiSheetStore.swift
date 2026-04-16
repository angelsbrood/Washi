import CoreGraphics
import Foundation
import ImageIO

// MARK: - Synchronous Sheet Store

/// Thread-safe synchronous sheet store.
/// Backs both the synchronous `WashiSheet.create()` path and the
/// async `WashiTextureCache` convenience path.
internal final class WashiSheetStore: @unchecked Sendable {
    static let shared = WashiSheetStore()

    private let memoryCache = NSCache<NSString, CachedImage>()
    private let lock = NSLock()  // protects disk write races
    private let textureSize = 1024

    func resolve(
        weight: WashiWeight,
        identity: String,
        displayScale: CGFloat
    ) -> WashiSheet {
        let cacheKey = "\(weight)-\(identity)" as NSString

        // 1. Memory cache — microseconds
        if let cached = memoryCache.object(forKey: cacheKey) {
            return WashiSheet(
                image: cached.image,
                weight: weight,
                identity: identity,
                displayScale: displayScale
            )
        }

        // 2. Disk cache — ~1-5ms
        if let diskImage = loadFromDisk(key: cacheKey as String) {
            memoryCache.setObject(CachedImage(diskImage), forKey: cacheKey)
            return WashiSheet(
                image: diskImage,
                weight: weight,
                identity: identity,
                displayScale: displayScale
            )
        }

        // 3. Generate — ~50-100ms cold
        var params = weight.simulationParams
        params.seed = WashiTextureCache.stableHash("\(identity)-\(weight)")
        params.textureScale = 1.0  // always 1.0 in the sheet model

        let image = FiberSimulator.generate(params: params, size: textureSize)

        // 4. Cache to memory and disk
        memoryCache.setObject(CachedImage(image), forKey: cacheKey)
        saveToDisk(image: image, key: cacheKey as String)

        return WashiSheet(
            image: image,
            weight: weight,
            identity: identity,
            displayScale: displayScale
        )
    }

    // MARK: - Disk Cache

    private func diskCacheURL(for key: String) -> URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = caches.appendingPathComponent("WashiTextures-v23", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let safe = key.replacingOccurrences(of: "/", with: "_")
                      .replacingOccurrences(of: ":", with: "_")
        return dir.appendingPathComponent("\(safe).png")
    }

    private func loadFromDisk(key: String) -> CGImage? {
        let url = diskCacheURL(for: key)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }
        return image
    }

    private func saveToDisk(image: CGImage, key: String) {
        let url = diskCacheURL(for: key)
        lock.lock()
        defer { lock.unlock() }
        guard let dest = CGImageDestinationCreateWithURL(
            url as CFURL, "public.png" as CFString, 1, nil
        ) else { return }
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
    }
}

// MARK: - Cache Wrapper

private class CachedImage {
    let image: CGImage
    init(_ image: CGImage) { self.image = image }
}
