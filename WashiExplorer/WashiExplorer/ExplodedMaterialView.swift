import SwiftUI
import WashiMaterial

// MARK: - Layer Model

enum ExplodedLayerKind {
    case systemBlur
    case densityMap
    case shaderOutput
    case composited
}

struct ExplodedLayer {
    let label: String
    let kind: ExplodedLayerKind
}

// MARK: - Exploded Material View

struct ExplodedMaterialView: View {

    let tier: WashiTier
    let colorScheme: ColorScheme
    let cardValues: CardValues
    let densityImage: CGImage?
    let scanDensityImage: CGImage?
    let seed: Float
    let startFocused: Bool
    var transitionNamespace: Namespace.ID? = nil
    var transitionID: String? = nil
    let onDismiss: () -> Void

    @State private var isExploded = false
    @State private var showLabels = false
    @State private var dragOrbitOffset: CGSize = .zero
    @State private var dragOrbitBase: CGSize = .zero
    @State private var zoom: CGFloat = 1.0
    @State private var zoomBase: CGFloat = 1.0
    @State private var isFocused = false
    @State private var focusAmount: Double = 0
    @State private var morphComplete = false

    private let motionManager = WashiMotionManager.shared

    // MARK: - Layout Constants

    private let cardWidth: CGFloat = 300
    private let cardHeight: CGFloat = 200

    // Multi-card zoom: 0.5 – 1.8. Single-card: fixed at 1.5.
    // Gate at raw ~2.0 to enter single-card. Pinch-out to exit.
    private let multiZoomMin: CGFloat = 0.5
    private let multiZoomMax: CGFloat = 1.8
    private let singleCardZoom: CGFloat = 1.5
    private let gateRawThreshold: CGFloat = 3.0
    private let exitRawThreshold: CGFloat = 0.5

    // MARK: - Layer Stack

    private var layers: [ExplodedLayer] {
        var result: [ExplodedLayer] = [
            ExplodedLayer(label: "System Blur", kind: .systemBlur),
        ]

        if tier == .simulated || tier == .scanned {
            result.append(ExplodedLayer(label: "Fiber Density", kind: .densityMap))
        }

        result.append(ExplodedLayer(label: "Modulation", kind: .shaderOutput))
        result.append(ExplodedLayer(label: "", kind: .composited))

        return result
    }

    private var labeledLayers: [(index: Int, label: String)] {
        layers.enumerated().compactMap { index, layer in
            layer.label.isEmpty ? nil : (index, layer.label)
        }
    }

    // MARK: - Orbit

    private let baseOrbitX: Double = 25.0
    private let baseOrbitY: Double = -30.0

    private var clampedDragWidth: CGFloat {
        max(-200, min(200, dragOrbitOffset.width))
    }

    private var clampedDragHeight: CGFloat {
        max(-200, min(200, dragOrbitOffset.height))
    }

    private var orbitX: Double {
        baseOrbitX + Double(clampedDragHeight / 200.0) * 15.0
    }

    private var orbitY: Double {
        baseOrbitY + Double(clampedDragWidth / 200.0) * 15.0
    }

    // MARK: - Orbit Fiber Response

    /// Tilt magnitude from orbit deviation — how far the viewing angle
    /// has shifted from the default isometric position.
    private var orbitTiltIntensity: Float {
        let devX = Float(orbitX - baseOrbitX)
        let devY = Float(orbitY - baseOrbitY)
        let magnitude = sqrt(devX * devX + devY * devY)
        let maxDev: Float = 15.0
        return min(magnitude / maxDev, 1.0)
    }

    /// Tilt direction from orbit deviation.
    private var orbitTiltAngle: Float {
        let devX = Float(orbitX - baseOrbitX)
        let devY = Float(orbitY - baseOrbitY)
        var angle = atan2(devX, devY)
        if angle < 0 { angle += 2.0 * .pi }
        return angle
    }

    /// Combined tilt magnitude: vector sum of gyro + orbit contributions.
    private var combinedTiltIntensity: Float {
        let gyroX = motionManager.tiltIntensity * cos(motionManager.tiltAngle)
        let gyroY = motionManager.tiltIntensity * sin(motionManager.tiltAngle)

        let oX = orbitTiltIntensity * cos(orbitTiltAngle)
        let oY = orbitTiltIntensity * sin(orbitTiltAngle)

        let cx = gyroX + oX
        let cy = gyroY + oY
        return min(sqrt(cx * cx + cy * cy), 1.0)
    }

    /// Combined tilt direction: direction of the gyro + orbit vector sum.
    private var combinedTiltAngle: Float {
        let gyroX = motionManager.tiltIntensity * cos(motionManager.tiltAngle)
        let gyroY = motionManager.tiltIntensity * sin(motionManager.tiltAngle)

        let oX = orbitTiltIntensity * cos(orbitTiltAngle)
        let oY = orbitTiltIntensity * sin(orbitTiltAngle)

        let cx = gyroX + oX
        let cy = gyroY + oY
        var angle = atan2(cy, cx)
        if angle < 0 { angle += 2.0 * .pi }
        return angle
    }

    /// 0 = normal exploded view, 1 = focused on Result card
    /// Driven by focusAmount (animated state), not zoom level
    private var focusProgress: Double { focusAmount }

    // MARK: - Depth Layout

    private var hasDensityLayer: Bool {
        tier == .simulated || tier == .scanned
    }

    private func layerDepth(_ index: Int) -> CGFloat {
        guard isExploded else { return 0 }

        switch layers[index].kind {
        case .systemBlur:   return hasDensityLayer ? 280 : 180
        case .densityMap:   return 180
        case .shaderOutput: return 80
        case .composited:   return -180
        }
    }

    private func projectedOffset(forDepth depth: CGFloat) -> CGSize {
        let angleX = orbitX * .pi / 180.0
        let angleY = orbitY * .pi / 180.0
        let dx = -depth * CGFloat(sin(angleY))
        let dy = -depth * CGFloat(sin(angleX) * cos(angleY))
        return CGSize(width: dx, height: dy)
    }

    private var zoomPanOffset: CGSize {
        let p = projectedOffset(forDepth: isExploded ? -180 : 0)
        let factor = max(0, zoom - 1) * 1.5
        // Fade out pan as Result card moves to center in focus mode
        let fp = focusProgress
        return CGSize(width: -p.width * factor * (1 - fp), height: -p.height * factor * (1 - fp))
    }

    private func layerOpacity(_ index: Int) -> Double {
        if isExploded { return 1.0 }
        return layers[index].kind == .composited ? 1.0 : 0.0
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            // Full-screen dismiss target behind everything
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    morphComplete = false
                    onDismiss()
                }

            ZStack {
                ForEach(Array(layers.enumerated()), id: \.offset) { index, layer in
                let depth = layerDepth(index)
                let projected = projectedOffset(forDepth: depth)
                let fp = focusProgress
                let isResult = layer.kind == .composited

                // Gyro/drag deviation from base angles (±15°)
                let devX = orbitX - baseOrbitX
                let devY = orbitY - baseOrbitY

                // Rotation: Result blends from isometric tilt to face-on with tilt
                let rotX = isResult ? (orbitX * 0.4 * (1 - fp) + devX * fp) : (orbitX * 0.4)
                let rotY = isResult ? (orbitY * 0.4 * (1 - fp) + devY * fp) : (orbitY * 0.4)

                // Position: Result blends to center in focus mode
                let posX = isResult ? projected.width * (1 - fp) : projected.width
                let posY = isResult ? projected.height * (1 - fp) : projected.height

                // Opacity: non-Result layers fade out in focus mode
                let opacity = isResult ? layerOpacity(index) : layerOpacity(index) * (1 - fp)

                cardContent(
                    layer: layer, isResult: isResult,
                    rotX: rotX, rotY: rotY, fp: fp
                )
                    .frame(
                        width: isResult ? cardWidth * 1.1 : cardWidth,
                        height: isResult ? cardHeight * 1.1 : cardHeight
                    )
                    .shadow(color: .black.opacity(isExploded ? 0.2 : 0), radius: 12, x: 4, y: 4)
                    .contentShape(RoundedRectangle(cornerRadius: 12))
                    .onTapGesture { }
                    .modifier(CardTransitionModifier(
                        apply: isResult,
                        id: transitionID,
                        namespace: transitionNamespace
                    ))
                    .offset(x: posX, y: posY)
                    .zIndex(Double(-depth))
                    .opacity(opacity)
            }

            if showLabels {
                ForEach(labeledLayers, id: \.index) { item in
                    let depth = layerDepth(item.index)
                    let projected = projectedOffset(forDepth: depth)

                    Text(item.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.ultraThinMaterial, in: Capsule())
                        .offset(
                            x: projected.width,
                            y: projected.height + cardHeight / 2 + 20
                        )
                        .zIndex(Double(-depth))
                        .opacity(1 - focusProgress)
                        .transition(.opacity)
                }
            }
        }
            .scaleEffect(zoom)
            .offset(x: zoomPanOffset.width, y: zoomPanOffset.height)
            .padding()
        }
        .gesture(
            DragGesture()
                .onChanged { value in
                    dragOrbitOffset = CGSize(
                        width: dragOrbitBase.width + value.translation.width,
                        height: dragOrbitBase.height + value.translation.height
                    )
                }
                .onEnded { value in
                    dragOrbitBase = CGSize(
                        width: max(-200, min(200, dragOrbitBase.width + value.translation.width)),
                        height: max(-200, min(200, dragOrbitBase.height + value.translation.height))
                    )
                }
        )
        .simultaneousGesture(
            MagnifyGesture()
                .onChanged { value in
                    let raw = zoomBase * value.magnification
                    if !isFocused {
                        if raw < multiZoomMin {
                            // Rubberband below min
                            zoom = multiZoomMin - (multiZoomMin - raw) * 0.3
                        } else if raw > multiZoomMax {
                            // Resistance approaching gate
                            zoom = multiZoomMax + (raw - multiZoomMax) * 0.3
                        } else {
                            zoom = raw
                        }
                    } else {
                        // Single-card: resistance in both directions, no real zoom
                        if raw < singleCardZoom {
                            zoom = singleCardZoom - (singleCardZoom - raw) * 0.3
                        } else {
                            zoom = singleCardZoom + (raw - singleCardZoom) * 0.1
                        }
                    }
                }
                .onEnded { value in
                    let raw = zoomBase * value.magnification
                    if !isFocused {
                        if raw > gateRawThreshold {
                            // Cleared gate → enter single-card
                            isFocused = true
                            zoomBase = singleCardZoom
                            withAnimation(.spring(duration: 0.4, bounce: 0.15)) {
                                zoom = singleCardZoom
                                focusAmount = 1.0
                            }
                        } else {
                            // Stay in multi-card, clamp to range
                            let clamped = max(multiZoomMin, min(multiZoomMax, raw))
                            zoomBase = clamped
                            withAnimation(.spring(duration: 0.35, bounce: 0.3)) {
                                zoom = clamped
                            }
                        }
                    } else {
                        if raw < exitRawThreshold {
                            // Exit single-card → land at multi-card max zoom
                            isFocused = false
                            zoomBase = multiZoomMax
                            withAnimation(.spring(duration: 0.4, bounce: 0.15)) {
                                zoom = multiZoomMax
                                focusAmount = 0
                                showLabels = true
                            }
                        } else {
                            // Snap back to single-card zoom
                            zoomBase = singleCardZoom
                            withAnimation(.spring(duration: 0.35, bounce: 0.3)) {
                                zoom = singleCardZoom
                            }
                        }
                    }
                }
        )
        .onAppear {
            motionManager.start()
            if startFocused {
                // Start in focus state at zoom 1.0 so matchedGeometry has clean coords
                isExploded = true
                isFocused = true
                focusAmount = 1.0
                zoom = 1.0
                zoomBase = singleCardZoom
                // Animate zoom up after geometry morph settles
                withAnimation(.spring(duration: 0.5, bounce: 0.12).delay(0.05)) {
                    zoom = singleCardZoom
                }
                // Detach from matchedGeometry after morph completes
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    morphComplete = true
                }
            } else {
                withAnimation(.spring(duration: 0.6, bounce: 0.2).delay(0.2)) {
                    isExploded = true
                }
                withAnimation(.easeIn(duration: 0.3).delay(0.7)) {
                    showLabels = true
                }
            }
        }
        .onDisappear {
            motionManager.stop()
        }
    }

    // MARK: - Layer Content (composited vs non-composited split)

    @ViewBuilder
    private func cardContent(
        layer: ExplodedLayer, isResult: Bool,
        rotX: Double, rotY: Double, fp: Double
    ) -> some View {
        if isResult {
            // Both views always in tree. SwiftUI compositedView provides
            // stable identity. BlurCard3DView handles 3D perspective
            // (blur-safe CATransform3D). They swap at morphComplete.
            ZStack {
                compositedView
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(.white.opacity(0.1), lineWidth: 0.5)
                    }
                    .rotation3DEffect(
                        .degrees(rotX),
                        axis: (x: 1, y: 0, z: 0),
                        perspective: 0
                    )
                    .rotation3DEffect(
                        .degrees(rotY),
                        axis: (x: 0, y: 1, z: 0),
                        perspective: 0
                    )
                    .opacity(morphComplete ? 0 : 1)

                BlurCard3DView(
                    blurStyle: cardValues.blurStyle,
                    creamOpacity: CGFloat(cardValues.creamTintOpacity),
                    fiberOverlay: AnyView(fiberOverlayForTier()),
                    rotX: rotX,
                    rotY: rotY,
                    perspective: morphComplete ? 0.3 * fp : 0,
                    cornerRadius: 12
                )
                .opacity(morphComplete ? 1 : 0)
            }
        } else {
            // Non-composited layers: SwiftUI rotation (no blur concern)
            layerView(for: layer)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(.white.opacity(0.1), lineWidth: 0.5)
                }
                .rotation3DEffect(
                    .degrees(rotX),
                    axis: (x: 1, y: 0, z: 0),
                    perspective: 0.15
                )
                .rotation3DEffect(
                    .degrees(rotY),
                    axis: (x: 0, y: 1, z: 0),
                    perspective: 0.15
                )
        }
    }

    // MARK: - Layer Rendering

    @ViewBuilder
    private func layerView(for layer: ExplodedLayer) -> some View {
        switch layer.kind {
        case .systemBlur:
            Rectangle().fill(cardValues.systemMaterial)

        case .densityMap:
            if let img = activeDensityImage {
                let imageView = Image(decorative: img, scale: 1.0)
                    .resizable()
                    .interpolation(.high)
                if tier == .scanned {
                    imageView
                        .aspectRatio(contentMode: .fill)
                        .colorEffect(ShaderLibrary.default.amberDensity())
                } else {
                    imageView
                        .colorEffect(ShaderLibrary.default.amberDensity())
                }
            } else {
                Color.clear
            }

        case .shaderOutput:
            shaderOutputView

        case .composited:
            compositedView
        }
    }

    // MARK: Active Density Image

    private var activeDensityImage: CGImage? {
        tier == .scanned ? scanDensityImage : densityImage
    }

    // MARK: Shader Args

    private var noiseArgs: [Shader.Argument] {
        [.boundingRect,
         .float(cardValues.fiberLength), .float(cardValues.fiberFineness),
         .float(cardValues.fiberVisibility),
         .float(cardValues.formationLayers), .float(cardValues.formationAlignment),
         .float(cardValues.kumo), .float(cardValues.kumoScale),
         .float(cardValues.surface), .float(cardValues.warmth), .float(seed)]
    }

    private var simulatedArgs: [Shader.Argument] {
        return [.boundingRect, .float(cardValues.fiberVisibility),
                .float(0.06),
                .float(combinedTiltIntensity), .float(combinedTiltAngle),
                .float(colorScheme == .dark ? 0.0 : 1.0),
                .float(cardValues.surface), .float(cardValues.warmth), .float(seed)]
    }

    // MARK: Shader Output (isolated modulation layer)

    @ViewBuilder
    private var shaderOutputView: some View {
        switch tier {
        case .noise:
            Color.white
                .colorEffect(Shader(function: ShaderLibrary.default.washi, arguments: noiseArgs))

        case .scattered:
            Color.white
                .colorEffect(Shader(function: ShaderLibrary.default.washiScattered, arguments: noiseArgs))

        case .simulated:
            if let img = densityImage {
                Image(decorative: img, scale: 1.0)
                    .resizable()
                    .interpolation(.high)
                    .colorEffect(Shader(
                        function: ShaderLibrary.default.washiSimulated,
                        arguments: simulatedArgs
                    ))
            } else {
                Color.clear
            }

        case .scanned:
            if let img = scanDensityImage {
                Image(decorative: img, scale: 1.0)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
                    .colorEffect(Shader(
                        function: ShaderLibrary.default.washiSimulated,
                        arguments: simulatedArgs
                    ))
            } else {
                Color.clear
            }
        }
    }

    // MARK: Composited (full material stack)

    @ViewBuilder
    private var compositedView: some View {
        switch tier {
        case .noise:
            Color.clear
                .background { Rectangle().fill(cardValues.systemMaterial) }
                .overlay {
                    Color(red: 0.94, green: 0.92, blue: 0.89)
                        .opacity(cardValues.creamTintOpacity)
                        .allowsHitTesting(false)
                }
                .overlay {
                    Color.white
                        .colorEffect(Shader(function: ShaderLibrary.default.washi, arguments: noiseArgs))
                        .allowsHitTesting(false)
                }

        case .scattered:
            Color.clear
                .background { Rectangle().fill(cardValues.systemMaterial) }
                .overlay {
                    Color(red: 0.94, green: 0.92, blue: 0.89)
                        .opacity(cardValues.creamTintOpacity)
                        .allowsHitTesting(false)
                }
                .overlay {
                    Color.white
                        .colorEffect(Shader(function: ShaderLibrary.default.washiScattered, arguments: noiseArgs))
                        .allowsHitTesting(false)
                }

        case .simulated:
            if let img = densityImage {
                Color.clear
                    .background { Rectangle().fill(cardValues.systemMaterial) }
                    .overlay {
                        Color(red: 0.94, green: 0.92, blue: 0.89)
                            .opacity(cardValues.creamTintOpacity)
                            .allowsHitTesting(false)
                    }
                    .overlay {
                        Image(decorative: img, scale: 1.0)
                            .resizable()
                            .interpolation(.high)
                            .colorEffect(Shader(
                                function: ShaderLibrary.default.washiSimulated,
                                arguments: simulatedArgs
                            ))
                            .allowsHitTesting(false)
                    }
            } else {
                Rectangle().fill(cardValues.systemMaterial)
            }

        case .scanned:
            if let img = scanDensityImage {
                Color.clear
                    .background { Rectangle().fill(cardValues.systemMaterial) }
                    .overlay {
                        Color(red: 0.94, green: 0.92, blue: 0.89)
                            .opacity(cardValues.creamTintOpacity)
                            .allowsHitTesting(false)
                    }
                    .overlay {
                        Image(decorative: img, scale: 1.0)
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fill)
                            .colorEffect(Shader(
                                function: ShaderLibrary.default.washiSimulated,
                                arguments: simulatedArgs
                            ))
                            .allowsHitTesting(false)
                    }
            } else {
                Rectangle().fill(cardValues.systemMaterial)
            }
        }
    }

    // MARK: Fiber Overlay (for BlurCard3DView hosting)

    /// Returns the fiber shader content only — no blur base, no cream tint.
    /// Cream tint and blur are handled by the UIKit/AppKit views in BlurCard3DView.
    @ViewBuilder
    private func fiberOverlayForTier() -> some View {
        switch tier {
        case .noise:
            Color.white
                .colorEffect(Shader(
                    function: ShaderLibrary.default.washi,
                    arguments: noiseArgs
                ))
                .allowsHitTesting(false)

        case .scattered:
            Color.white
                .colorEffect(Shader(
                    function: ShaderLibrary.default.washiScattered,
                    arguments: noiseArgs
                ))
                .allowsHitTesting(false)

        case .simulated:
            if let img = densityImage {
                Image(decorative: img, scale: 1.0)
                    .resizable()
                    .interpolation(.high)
                    .colorEffect(Shader(
                        function: ShaderLibrary.default.washiSimulated,
                        arguments: simulatedArgs
                    ))
                    .allowsHitTesting(false)
            }

        case .scanned:
            if let img = scanDensityImage {
                Image(decorative: img, scale: 1.0)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
                    .colorEffect(Shader(
                        function: ShaderLibrary.default.washiSimulated,
                        arguments: simulatedArgs
                    ))
                    .allowsHitTesting(false)
            }
        }
    }
}

// MARK: - Conditional Matched Geometry

private struct CardTransitionModifier: ViewModifier {
    let apply: Bool
    let id: String?
    let namespace: Namespace.ID?

    func body(content: Content) -> some View {
        if apply, let id, let namespace {
            content.matchedGeometryEffect(id: id, in: namespace)
        } else {
            content
        }
    }
}
