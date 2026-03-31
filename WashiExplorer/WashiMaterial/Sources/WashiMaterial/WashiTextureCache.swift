import CoreGraphics
import Foundation
import ImageIO

// MARK: - Texture Cache

public actor WashiTextureCache {

    public static let shared = WashiTextureCache()

    private let memoryCache = NSCache<NSString, CachedImage>()
    private let textureSize = 1024

    // MARK: - Public API

    /// Retrieves or generates a density texture for the given identity and weight.
    public func texture(
        for key: String,
        weight: WashiWeight,
        identity: String?
    ) -> CGImage {
        // 1. Check memory cache
        if let cached = memoryCache.object(forKey: key as NSString) {
            return cached.image
        }

        // 2. Check disk cache
        if let diskImage = loadFromDisk(key: key) {
            memoryCache.setObject(CachedImage(diskImage), forKey: key as NSString)
            return diskImage
        }

        // 3. Generate
        var params = weight.simulationParams
        params.seed = Self.stableHash("\(identity ?? "default")-\(weight)")

        let image = FiberSimulator.generate(params: params, size: textureSize)

        // 4. Cache to memory and disk
        memoryCache.setObject(CachedImage(image), forKey: key as NSString)
        saveToDisk(image: image, key: key)

        return image
    }

    /// Pre-generate textures for known surface identities.
    /// Call at app launch to avoid generation delay on first display.
    public func prewarm(identities: [(String, WashiWeight)]) {
        for (identity, weight) in identities {
            let key = "\(weight)-\(identity)"
            _ = texture(for: key, weight: weight, identity: identity)
        }
    }

    // MARK: - Deterministic Hashing

    /// Stable hash that produces the same value across launches.
    /// Swift's Hasher is randomly seeded per process — unsuitable for
    /// deterministic texture generation. FNV-1a is simple, fast, and
    /// well-distributed.
    public static func stableHash(_ string: String) -> UInt64 {
        var hash: UInt64 = 14695981039346656037  // FNV-1a offset basis
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1099511628211               // FNV-1a prime
        }
        return hash
    }

    // MARK: - Disk Cache

    private func diskCacheURL(for key: String) -> URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = caches.appendingPathComponent("WashiTextures-v2", isDirectory: true)
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
