import SwiftUI

// MARK: - Weight

/// The visual weight of the washi material, controlling both the system
/// blur level and the physical properties of the simulated paper sheet.
public enum WashiWeight: Sendable, Hashable {
    /// Fewer fibers, finer, more translucent.
    /// For sheets, overlays, transient surfaces.
    case thin

    /// Moderate density, visible fiber crossings. The default.
    /// For cards, panels, persistent surfaces.
    case standard

    /// More fibers, coarser, denser.
    /// For backgrounds, hero surfaces.
    case thick
}

extension WashiWeight {

    var systemMaterial: AnyShapeStyle {
        switch self {
        case .thin:     AnyShapeStyle(.ultraThinMaterial)
        case .standard: AnyShapeStyle(.thinMaterial)
        case .thick:    AnyShapeStyle(.regularMaterial)
        }
    }

    /// Parameters for the fiber deposition simulation.
    /// These control the physical properties of the generated sheet.
    /// Values tuned in WashiExplorer — adjust there, copy here.
    var simulationParams: FiberSimulator.FiberParams {
        switch self {
        case .thin:
            FiberSimulator.FiberParams(
                fiberLength: 0.55,
                fiberFineness: 0.65,
                fiberCount: 2500,
                formationAlignment: 0.25,
                kumo: 0.15,
                kumoScale: 0.45,
                seed: 0  // overridden by identity
            )
        case .standard:
            FiberSimulator.FiberParams(
                fiberLength: 0.60,
                fiberFineness: 0.55,
                fiberCount: 4200,
                formationAlignment: 0.28,
                kumo: 0.25,
                kumoScale: 0.40,
                seed: 0
            )
        case .thick:
            FiberSimulator.FiberParams(
                fiberLength: 0.65,
                fiberFineness: 0.45,
                fiberCount: 6300,
                formationAlignment: 0.30,
                kumo: 0.35,
                kumoScale: 0.40,
                seed: 0
            )
        }
    }

    /// Derive texture scale from surface width.
    /// Reference: 360pt surface = scale 1.0. Larger surfaces show more paper area.
    public func textureScale(for surfaceWidth: CGFloat) -> Float {
        Float(surfaceWidth / 360.0)
    }

    /// Shader parameters — control the modulation overlay, not the simulation.

    var fiberVisibility: Float {
        switch self { case .thin: 0.03; case .standard: 0.05; case .thick: 0.08 }
    }

    func fiberVisibility(for colorScheme: ColorScheme) -> Float {
        fiberVisibility  // 0.03 / 0.05 / 0.08 — same material, both modes
    }

    var surface: Float {
        switch self { case .thin: 0.08; case .standard: 0.12; case .thick: 0.18 }
    }

    var warmth: Float {
        switch self { case .thin: 0.0; case .standard: 0.0; case .thick: 0.3 }
    }

    var tiltBoost: Float {
        switch self { case .thin: 0.04; case .standard: 0.06; case .thick: 0.08 }
    }

    /// Opacity of the warm kozo tint per color scheme.
    /// Light mode: provides tonal contrast for fiber structure to read against.
    /// Dark mode: shifts highlights from cool to warm — subtle material quality.
    func warmTintOpacity(for colorScheme: ColorScheme) -> Double {
        switch (self, colorScheme) {
        case (.thin, .light):     return 0.05
        case (.standard, .light): return 0.10
        case (.thick, .light):    return 0.15
        case (.thin, .dark):      return 0.0
        case (.standard, .dark):  return 0.0
        case (.thick, .dark):     return 0.0
        default:                  return 0.04
        }
    }
}

// MARK: - Modifier

public struct WashiMaterialModifier: ViewModifier {

    let weight: WashiWeight
    let identity: String?

    @Environment(\.colorScheme) private var colorScheme
    @State private var fiberImage: CGImage?
    @State private var surfaceWidth: CGFloat = 360

    private var motionManager: WashiMotionManager { .shared }

    /// Quantized texture scale (to 0.1) to avoid excessive cache entries.
    private var quantizedTextureScale: Float {
        let raw = weight.textureScale(for: surfaceWidth)
        return (raw * 10).rounded() / 10
    }

    public func body(content: Content) -> some View {
        content
            .background {
                GeometryReader { geo in
                    Rectangle()
                        .fill(weight.systemMaterial)
                        .onAppear { surfaceWidth = geo.size.width }
                        .onChange(of: geo.size.width) { _, w in surfaceWidth = w }
                }
            }
            .overlay {
                Color(red: 0.94, green: 0.92, blue: 0.89)
                    .opacity(weight.warmTintOpacity(for: colorScheme))
                    .allowsHitTesting(false)
            }
            .overlay {
                if let fiberImage {
                    Image(decorative: fiberImage, scale: 1.0)
                        .resizable()
                        .interpolation(.high)
                        .colorEffect(
                            ShaderLibrary.washiSimulated(
                                .boundingRect,
                                .float(weight.fiberVisibility(for: colorScheme)),
                                .float(weight.tiltBoost),
                                .float(motionManager.tiltIntensity),
                                .float(motionManager.tiltAngle),
                                .float(tiltShadowBias),
                                .float(weight.surface),
                                .float(weight.warmth),
                                .float(stableSeedFloat)
                            )
                        )
                        .allowsHitTesting(false)
                }
            }
            .task(id: cacheKey) {
                fiberImage = await WashiTextureCache.shared.texture(
                    for: cacheKey,
                    weight: weight,
                    identity: identity,
                    textureScale: quantizedTextureScale
                )
            }
            .onAppear { motionManager.start() }
            .onDisappear { motionManager.stop() }
    }

    private var cacheKey: String {
        "\(weight)-\(identity ?? "default")-ts\(quantizedTextureScale)"
    }

    private var tiltShadowBias: Float {
        colorScheme == .dark ? 0.0 : 1.0
    }

    /// Stable float seed for the shader's surface noise.
    /// Uses FNV-1a (same as WashiTextureCache) so it's deterministic
    /// across launches. Swift's hashValue is randomly seeded per process.
    private var stableSeedFloat: Float {
        Float(WashiTextureCache.stableHash(cacheKey) & 0xFFFF)
    }
}

// MARK: - View Extension

extension View {
    /// Applies a washi paper material background to this view.
    ///
    /// - Parameters:
    ///   - weight: The visual weight (.thin, .standard, .thick). Controls both
    ///     the blur level and the physical properties of the simulated paper sheet.
    ///   - identity: Optional string identifying this surface. Different identities
    ///     get different simulated sheets. Same identity always gets the same sheet.
    ///     If nil, a shared default sheet is used for this weight.
    public func washiMaterial(
        _ weight: WashiWeight = .standard,
        identity: String? = nil
    ) -> some View {
        modifier(WashiMaterialModifier(weight: weight, identity: identity))
    }
}
