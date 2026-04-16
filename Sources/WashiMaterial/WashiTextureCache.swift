import CoreGraphics
import Foundation

// MARK: - Texture Cache

public actor WashiTextureCache {

    public static let shared = WashiTextureCache()

    // MARK: - Public API

    /// Async sheet creation — for the convenience API where a brief
    /// fade-in is acceptable. Delegates to WashiSheetStore.
    public func sheet(
        weight: WashiWeight,
        identity: String,
        displayScale: CGFloat
    ) -> WashiSheet {
        WashiSheetStore.shared.resolve(
            weight: weight,
            identity: identity,
            displayScale: displayScale
        )
    }

    /// Retrieves or generates a density texture for the given identity and weight.
    /// Retained for backward compatibility — delegates to WashiSheetStore.
    public func texture(
        for key: String,
        weight: WashiWeight,
        identity: String?,
        textureScale: Float = 1.0
    ) -> CGImage {
        WashiSheetStore.shared.resolve(
            weight: weight,
            identity: identity ?? "default",
            displayScale: 2.0  // default; textureScale ignored in sheet model
        ).image
    }

    /// Prewarm sheets into cache.
    public func prewarm(sheets: [(identity: String, weight: WashiWeight)], displayScale: CGFloat) {
        for (identity, weight) in sheets {
            _ = WashiSheetStore.shared.resolve(
                weight: weight,
                identity: identity,
                displayScale: displayScale
            )
        }
    }

    /// Pre-generate textures for known surface identities.
    /// Retained for backward compatibility.
    public func prewarm(identities: [(String, WashiWeight)]) {
        for (identity, weight) in identities {
            _ = WashiSheetStore.shared.resolve(
                weight: weight,
                identity: identity,
                displayScale: 2.0
            )
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

}
