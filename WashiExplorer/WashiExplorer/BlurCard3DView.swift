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

/// Inner view that holds all content and owns the 3D transform.
/// Layer-hosting mode: we set the root layer before wantsLayer, so
/// AppKit cannot override anchorPoint or position. The outer container
/// sets our frame manually in layout(); we apply the 3D transform here.
final class TransformView: NSView {

    var rotX: Double = 0
    var rotY: Double = 0
    var perspective: Double = 0

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        // Layer-hosting: own the root layer so anchorPoint survives.
        let rootLayer = CALayer()
        rootLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        self.layer = rootLayer
        self.wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        guard let layer = self.layer else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // Re-assert after every layout pass in case frame changes
        layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        layer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        applyTransform()
        CATransaction.commit()
    }

    func applyTransform() {
        guard let layer = self.layer else { return }
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

/// Outer container managed by NSViewRepresentable. Does not apply
/// transforms to its own layer — delegates that to the inner TransformView.
final class BlurCard3DContainer: NSView {

    let transformView = TransformView()

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.wantsLayer = true
        addSubview(transformView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        transformView.frame = bounds
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
        let inner = container.transformView
        inner.layer?.cornerRadius = cornerRadius
        inner.layer?.masksToBounds = true
        inner.layer?.borderColor = NSColor.white.withAlphaComponent(0.1).cgColor
        inner.layer?.borderWidth = 0.5

        // System blur — added to transformView, not container
        let effectView = NSVisualEffectView()
        effectView.material = blurStyle
        effectView.blendingMode = .withinWindow
        effectView.state = .active
        effectView.isEmphasized = false
        effectView.translatesAutoresizingMaskIntoConstraints = false
        inner.addSubview(effectView)
        NSLayoutConstraint.activate([
            effectView.topAnchor.constraint(equalTo: inner.topAnchor),
            effectView.bottomAnchor.constraint(equalTo: inner.bottomAnchor),
            effectView.leadingAnchor.constraint(equalTo: inner.leadingAnchor),
            effectView.trailingAnchor.constraint(equalTo: inner.trailingAnchor),
        ])

        // Cream tint
        let creamView = NSView()
        creamView.wantsLayer = true
        creamView.layer?.backgroundColor = creamTintColor.withAlphaComponent(creamOpacity).cgColor
        creamView.translatesAutoresizingMaskIntoConstraints = false
        inner.addSubview(creamView, positioned: .above, relativeTo: effectView)
        NSLayoutConstraint.activate([
            creamView.topAnchor.constraint(equalTo: inner.topAnchor),
            creamView.bottomAnchor.constraint(equalTo: inner.bottomAnchor),
            creamView.leadingAnchor.constraint(equalTo: inner.leadingAnchor),
            creamView.trailingAnchor.constraint(equalTo: inner.trailingAnchor),
        ])

        // Fiber overlay
        let hostingView = NSHostingView(rootView: fiberOverlay)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        inner.addSubview(hostingView, positioned: .above, relativeTo: creamView)
        NSLayoutConstraint.activate([
            hostingView.topAnchor.constraint(equalTo: inner.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: inner.bottomAnchor),
            hostingView.leadingAnchor.constraint(equalTo: inner.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: inner.trailingAnchor),
        ])

        context.coordinator.effectView = effectView
        context.coordinator.creamView = creamView
        context.coordinator.hostingView = hostingView

        return container
    }

    func updateNSView(_ container: BlurCard3DContainer, context: Context) {
        let inner = container.transformView
        inner.rotX = rotX
        inner.rotY = rotY
        inner.perspective = perspective
        inner.applyTransform()

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
