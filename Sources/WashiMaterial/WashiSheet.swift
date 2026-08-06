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

    /// Tile width and height in points for the current display scale.
    /// `tileSize / displayScale`. Used by the shader for fmod wrapping.
    public let tilePtsWidth: CGFloat
    public let tilePtsHeight: CGFloat

    /// Square-tile alias for backwards compatibility — equals `tilePtsWidth`.
    public var tilePts: CGFloat { tilePtsWidth }

    init(
        image: CGImage,
        weight: WashiWeight,
        identity: String,
        tileSize: CGSize,
        displayScale: CGFloat
    ) {
        self.image = image
        self.weight = weight
        self.identity = identity
        self.tilePtsWidth = tileSize.width / displayScale
        self.tilePtsHeight = tileSize.height / displayScale
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
    ///
    /// `tileSize` defaults to the legacy 1024² square — pass a larger or
    /// non-square size for sheets that need more unique fiber before the
    /// shader's fmod wrap recurs.
    public static func create(
        weight: WashiWeight,
        identity: String,
        tileSize: CGSize = CGSize(width: 1024, height: 1024),
        displayScale: CGFloat
    ) -> WashiSheet {
        WashiSheetStore.shared.resolve(
            weight: weight,
            identity: identity,
            tileSize: tileSize,
            displayScale: displayScale
        )
    }
}
