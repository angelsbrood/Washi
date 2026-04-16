import CoreGraphics

/// A seamlessly tileable sheet of simulated washi paper.
///
/// Create synchronously via `WashiSheet.create(weight:identity:displayScale:)`
/// for guaranteed availability at first frame, or asynchronously via
/// `WashiTextureCache.shared.sheet(weight:identity:displayScale:)` for
/// the convenience API path where a brief fade-in is acceptable.
///
/// Apply to views via `.washiMaterial(_:offset:)`.
///
/// The underlying 1024x1024 texture wraps seamlessly at all edges.
/// Different views sample different regions of the same infinite sheet
/// by passing different offsets.
public final class WashiSheet: @unchecked Sendable {
    public let image: CGImage
    public let weight: WashiWeight
    public let identity: String

    /// Tile size in points for the current display scale.
    /// 1024 / displayScale. Used by the shader for fmod wrapping.
    public let tilePts: CGFloat

    init(image: CGImage, weight: WashiWeight, identity: String, displayScale: CGFloat) {
        self.image = image
        self.weight = weight
        self.identity = identity
        self.tilePts = 1024.0 / displayScale
    }

    // MARK: - Synchronous Creation

    /// Create a sheet synchronously, bypassing actor isolation.
    ///
    /// This is the primary creation path for performance-critical consumers
    /// (like Threshold) that need the sheet available before the first frame.
    /// Safe to call during view init or anywhere on the main thread.
    ///
    /// Resolution order:
    /// 1. Shared memory cache (NSCache, thread-safe) — microseconds
    /// 2. Disk cache (CGImageSource) — ~1-5ms
    /// 3. Generate (FiberSimulator, pure CPU) — ~50-100ms cold
    ///
    /// Result is cached to both memory and disk for subsequent calls.
    public static func create(
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
}
