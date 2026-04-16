import SwiftUI

// MARK: - Sheet Modifier

public struct WashiSheetModifier: ViewModifier {
    let sheet: WashiSheet
    let offset: CGPoint

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale

    private var motionManager: WashiMotionManager { .shared }

    public func body(content: Content) -> some View {
        content
            .background {
                Rectangle().fill(sheet.weight.systemMaterial)
            }
            .overlay {
                Color(red: 0.94, green: 0.92, blue: 0.89)
                    .opacity(sheet.weight.warmTintOpacity(for: colorScheme))
                    .allowsHitTesting(false)
            }
            .overlay {
                Canvas { context, size in
                    let resolved = context.resolve(
                        Image(decorative: sheet.image, scale: displayScale)
                    )
                    let tw = sheet.tilePts
                    let th = sheet.tilePts

                    var sy = -fmod(offset.y, th)
                    if sy > 0 { sy -= th }
                    var y = sy
                    while y < size.height {
                        var sx = -fmod(offset.x, tw)
                        if sx > 0 { sx -= tw }
                        var x = sx
                        while x < size.width {
                            context.draw(resolved, in: CGRect(x: x, y: y, width: tw, height: th))
                            x += tw
                        }
                        y += th
                    }
                }
                .colorEffect(
                    ShaderLibrary.washiSimulated(
                        .boundingRect,
                        .float(sheet.weight.fiberVisibility(for: colorScheme)),
                        .float(sheet.weight.tiltBoost),
                        .float(motionManager.tiltIntensity),
                        .float(motionManager.tiltAngle),
                        .float(tiltShadowBias),
                        .float(sheet.weight.surface),
                        .float(sheet.weight.warmth),
                        .float(stableSeedFloat)
                    )
                )
                .allowsHitTesting(false)
            }
            .onAppear { motionManager.start() }
            .onDisappear { motionManager.stop() }
    }

    private var tiltShadowBias: Float {
        colorScheme == .dark ? 0.0 : 1.0
    }

    private var stableSeedFloat: Float {
        Float(WashiTextureCache.stableHash(sheet.identity) & 0xFFFF)
    }
}

// MARK: - View Extension

extension View {
    /// Applies a washi paper material from a pre-generated sheet.
    ///
    /// - Parameters:
    ///   - sheet: A `WashiSheet` created via `WashiSheet.create()` or `WashiTextureCache`.
    ///   - offset: Point offset into the infinite tiled sheet.
    ///     Adjacent offsets produce adjacent paper regions.
    public func washiMaterial(
        _ sheet: WashiSheet,
        offset: CGPoint = .zero
    ) -> some View {
        modifier(WashiSheetModifier(sheet: sheet, offset: offset))
    }
}
