import SwiftUI

// MARK: - iOS

#if os(iOS)

import UIKit

private let creamTintColor = UIColor(red: 0.94, green: 0.92, blue: 0.89, alpha: 1.0)

/// Container that applies CATransform3D in layoutSubviews, ensuring
/// correct bounds are available for perspective scaling.
final class BlurCard3DContainer: UIView {

    var rotX: Double = 0
    var rotY: Double = 0
    var perspective: Double = 0

    override func layoutSubviews() {
        super.layoutSubviews()
        applyTransform()
    }

    func applyTransform() {
        var t = CATransform3DIdentity
        let maxDim = max(bounds.width, bounds.height)
        if perspective > 0.001 && maxDim > 0 {
            t.m34 = -CGFloat(perspective) / maxDim
        }
        t = CATransform3DRotate(t, CGFloat(rotY) * .pi / 180.0, 0, 1, 0)
        t = CATransform3DRotate(t, CGFloat(rotX) * .pi / 180.0, 1, 0, 0)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.transform = t
        CATransaction.commit()
    }
}

/// UIKit-bridged blur card with CALayer.transform for correct
/// blur + 3D perspective compositing.
///
/// UIVisualEffectView renders blur flat into its layer. The compositor
/// then applies the 3D transform to the already-composited result.
/// This avoids SwiftUI's rotation3DEffect breaking blur sampling.
struct BlurCard3DView: UIViewRepresentable {

    let blurStyle: UIBlurEffect.Style
    let creamOpacity: CGFloat
    let fiberOverlay: AnyView
    let rotX: Double
    let rotY: Double
    let perspective: Double
    let cornerRadius: CGFloat

    func makeUIView(context: Context) -> BlurCard3DContainer {
        let container = BlurCard3DContainer()
        container.backgroundColor = .clear
        container.layer.cornerRadius = cornerRadius
        container.layer.masksToBounds = true
        container.layer.borderColor = UIColor.white.withAlphaComponent(0.1).cgColor
        container.layer.borderWidth = 0.5

        // System blur
        let effectView = UIVisualEffectView(
            effect: UIBlurEffect(style: blurStyle)
        )
        effectView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(effectView)
        NSLayoutConstraint.activate([
            effectView.topAnchor.constraint(equalTo: container.topAnchor),
            effectView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            effectView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            effectView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])

        // Cream tint inside blur's contentView
        let creamView = UIView()
        creamView.backgroundColor = creamTintColor.withAlphaComponent(creamOpacity)
        creamView.translatesAutoresizingMaskIntoConstraints = false
        effectView.contentView.addSubview(creamView)
        NSLayoutConstraint.activate([
            creamView.topAnchor.constraint(equalTo: effectView.contentView.topAnchor),
            creamView.bottomAnchor.constraint(equalTo: effectView.contentView.bottomAnchor),
            creamView.leadingAnchor.constraint(equalTo: effectView.contentView.leadingAnchor),
            creamView.trailingAnchor.constraint(equalTo: effectView.contentView.trailingAnchor),
        ])

        // Fiber overlay — SwiftUI hosted inside UIKit
        let hostingController = UIHostingController(rootView: fiberOverlay)
        hostingController.view.backgroundColor = .clear
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        effectView.contentView.addSubview(hostingController.view)
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: effectView.contentView.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: effectView.contentView.bottomAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: effectView.contentView.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: effectView.contentView.trailingAnchor),
        ])

        context.coordinator.effectView = effectView
        context.coordinator.creamView = creamView
        context.coordinator.hostingController = hostingController

        return container
    }

    func updateUIView(_ container: BlurCard3DContainer, context: Context) {
        // Update 3D transform
        container.rotX = rotX
        container.rotY = rotY
        container.perspective = perspective
        container.applyTransform()

        // Update cream opacity
        context.coordinator.creamView?.backgroundColor =
            creamTintColor.withAlphaComponent(creamOpacity)

        // Update fiber content
        context.coordinator.hostingController?.rootView = fiberOverlay
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator {
        var effectView: UIVisualEffectView?
        var creamView: UIView?
        var hostingController: UIHostingController<AnyView>?
    }
}

// MARK: - macOS

#elseif os(macOS)

import AppKit

private let creamTintColor = NSColor(red: 0.94, green: 0.92, blue: 0.89, alpha: 1.0)

/// Layer-hosting NSView: we own the root layer, so `layer.transform`
/// is allowed (unlike layer-backed views where AppKit manages the layer).
final class BlurCard3DContainer: NSView {

    var rotX: Double = 0
    var rotY: Double = 0
    var perspective: Double = 0

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        // Layer-hosting mode: set layer BEFORE wantsLayer.
        // This gives us full control over the root layer's transform.
        let rootLayer = CALayer()
        rootLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        self.layer = rootLayer
        self.wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        applyTransform()
    }

    func applyTransform() {
        guard let layer = layer else { return }
        var t = CATransform3DIdentity
        let maxDim = max(bounds.width, bounds.height)
        if perspective > 0.001 && maxDim > 0 {
            t.m34 = -CGFloat(perspective) / maxDim
        }
        t = CATransform3DRotate(t, CGFloat(rotY) * .pi / 180.0, 0, 1, 0)
        t = CATransform3DRotate(t, CGFloat(rotX) * .pi / 180.0, 1, 0, 0)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.transform = t
        CATransaction.commit()
    }
}

struct BlurCard3DView: NSViewRepresentable {

    let blurStyle: NSVisualEffectView.Material
    let creamOpacity: CGFloat
    let fiberOverlay: AnyView
    let rotX: Double
    let rotY: Double
    let perspective: Double
    let cornerRadius: CGFloat

    func makeNSView(context: Context) -> BlurCard3DContainer {
        let container = BlurCard3DContainer()
        container.layer?.cornerRadius = cornerRadius
        container.layer?.masksToBounds = true
        container.layer?.borderColor = NSColor.white.withAlphaComponent(0.1).cgColor
        container.layer?.borderWidth = 0.5

        // System blur
        let effectView = NSVisualEffectView()
        effectView.material = blurStyle
        effectView.blendingMode = .withinWindow
        effectView.state = .active
        effectView.isEmphasized = false
        effectView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(effectView)
        NSLayoutConstraint.activate([
            effectView.topAnchor.constraint(equalTo: container.topAnchor),
            effectView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            effectView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            effectView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])

        // Cream tint
        let creamView = NSView()
        creamView.wantsLayer = true
        creamView.layer?.backgroundColor = creamTintColor.withAlphaComponent(creamOpacity).cgColor
        creamView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(creamView, positioned: .above, relativeTo: effectView)
        NSLayoutConstraint.activate([
            creamView.topAnchor.constraint(equalTo: container.topAnchor),
            creamView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            creamView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            creamView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])

        // Fiber overlay
        let hostingView = NSHostingView(rootView: fiberOverlay)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(hostingView, positioned: .above, relativeTo: creamView)
        NSLayoutConstraint.activate([
            hostingView.topAnchor.constraint(equalTo: container.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            hostingView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])

        context.coordinator.effectView = effectView
        context.coordinator.creamView = creamView
        context.coordinator.hostingView = hostingView

        return container
    }

    func updateNSView(_ container: BlurCard3DContainer, context: Context) {
        container.rotX = rotX
        container.rotY = rotY
        container.perspective = perspective
        container.applyTransform()

        context.coordinator.creamView?.layer?.backgroundColor =
            creamTintColor.withAlphaComponent(creamOpacity).cgColor

        context.coordinator.hostingView?.rootView = fiberOverlay
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator {
        var effectView: NSVisualEffectView?
        var creamView: NSView?
        var hostingView: NSHostingView<AnyView>?
    }
}

#endif
