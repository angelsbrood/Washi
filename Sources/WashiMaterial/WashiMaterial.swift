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
                seed: 0,  // overridden by identity
                choshiScoops: 4
            )
        case .standard:
            FiberSimulator.FiberParams(
                fiberLength: 0.60,
                fiberFineness: 0.55,
                fiberCount: 4200,
                formationAlignment: 0.28,
                kumo: 0.25,
                kumoScale: 0.40,
                seed: 0,
                choshiScoops: 5
            )
        case .thick:
            FiberSimulator.FiberParams(
                fiberLength: 0.65,
                fiberFineness: 0.45,
                fiberCount: 6300,
                formationAlignment: 0.30,
                kumo: 0.35,
                kumoScale: 0.40,
                seed: 0,
                choshiScoops: 6
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

    let sheet: WashiSheet

    init(weight: WashiWeight, identity: String?) {
        self.sheet = WashiSheet.create(
            weight: weight,
            identity: identity ?? "default",
            displayScale: Self.currentDisplayScale
        )
    }

    public func body(content: Content) -> some View {
        content.washiMaterial(sheet)
    }

    private static var currentDisplayScale: CGFloat {
        #if os(iOS)
        UIScreen.main.scale
        #elseif os(macOS)
        NSScreen.main?.backingScaleFactor ?? 2.0
        #else
        2.0
        #endif
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
