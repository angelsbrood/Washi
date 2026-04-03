import SwiftUI
import AppKit
import AVFoundation
import ScreenCaptureKit
import WashiMaterial

struct CaptureView: View {

    @State private var densityImage: CGImage?
    @State private var rotX: Double = 0.0
    @State private var statusMessage: String?

    private let totalFrames = 360
    private let fps: Double = 60.0
    private let cardWidth: CGFloat = 800
    private let cardHeight: CGFloat = 530

    // Card turned to face left, with perspective
    private let rotY: Double = -20.0
    private let cardPerspective: Double = 0.3
    // Orbit amplitude: tilt up/down ±15°
    private let orbitAmplitude: Double = 15.0

    // Shader tilt derived from orbit angles
    private var orbitTiltIntensity: Float {
        let devX = Float(rotX)
        let devY = Float(rotY)
        let magnitude = sqrt(devX * devX + devY * devY)
        let maxDev: Float = 25.0
        return min(magnitude / maxDev, 1.0)
    }

    private var orbitTiltAngle: Float {
        var angle = atan2(Float(rotX), Float(rotY))
        if angle < 0 { angle += 2.0 * .pi }
        return angle
    }

    @ViewBuilder
    private var fiberOverlay: some View {
        if let densityImage {
            Image(decorative: densityImage, scale: 1.0)
                .resizable()
                .interpolation(.high)
                .colorEffect(
                    ShaderLibrary.washiSimulated(
                        .boundingRect,
                        .float(0.03),                // fiberVisibility (thin)
                        .float(0.04),                // tiltBoost (thin)
                        .float(orbitTiltIntensity),
                        .float(orbitTiltAngle),
                        .float(1.0),                 // tiltShadowBias (light mode)
                        .float(0.08),                // surface (thin)
                        .float(0.0),                 // warmth (thin)
                        .float(42.0)                 // seed
                    )
                )
        }
    }

    var body: some View {
        ZStack {
            // Shiro background
            LinearGradient(
                colors: [
                    Color(red: 0.98, green: 0.98, blue: 0.97),
                    Color(red: 0.94, green: 0.93, blue: 0.91),
                    Color(red: 0.97, green: 0.96, blue: 0.95),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Washi card via BlurCard3DView (CALayer transform preserves blur + perspective)
            BlurCard3DView(
                blurStyle: .hudWindow,          // thin weight
                creamOpacity: 0.05,             // thin light mode tint
                fiberOverlay: AnyView(fiberOverlay),
                rotX: rotX,
                rotY: rotY,
                perspective: cardPerspective,
                cornerRadius: 24
            )
            .frame(width: cardWidth, height: cardHeight)

            if let statusMessage {
                Text(statusMessage)
                    .font(.title)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 1920, height: 1080)
        .task { await runCapturePipeline() }
    }

    // MARK: - Pipeline

    private func runCapturePipeline() async {
        // 1. Generate density texture
        print("Generating density texture…")
        let params = FiberSimulator.FiberParams(
            fiberLength: 0.55,
            fiberFineness: 0.65,
            fiberCount: 2500,
            formationAlignment: 0.25,
            kumo: 0.15,
            kumoScale: 0.45,
            seed: 42,
            textureScale: 2.2,
            choshiScoops: 4
        )
        let image = await Task.detached(priority: .userInitiated) {
            FiberSimulator.generate(params: params)
        }.value
        densityImage = image
        print("Density texture ready.")

        // 2. Wait for blur to settle
        try? await Task.sleep(for: .seconds(1.0))

        // 3. Capture frames
        print("Starting capture: \(totalFrames) frames at \(Int(fps))fps…")
        let success = await captureFrames()

        // 4. Done
        statusMessage = success ? "Saved to Desktop" : "Capture failed"
        print(success ? "SUCCESS: Saved to ~/Desktop/WashiCapture-light-shiro.mov" : "ERROR: Capture failed")

        try? await Task.sleep(for: .seconds(2.0))
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Frame Capture

    private func captureFrames() async -> Bool {
        // Find our window via ScreenCaptureKit
        let filter: SCContentFilter
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let window = content.windows.first(where: { $0.owningApplication?.bundleIdentifier == Bundle.main.bundleIdentifier }) else {
                print("ERROR: Could not find WashiCapture window")
                return false
            }
            filter = SCContentFilter(desktopIndependentWindow: window)
        } catch {
            print("ERROR: ScreenCaptureKit content query failed: \(error)")
            return false
        }

        let config = SCStreamConfiguration()
        config.width = 1920
        config.height = 1080
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = false
        config.capturesAudio = false
        config.colorSpaceName = CGColorSpace.sRGB

        // Set up AVAssetWriter
        let outputURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop/WashiCapture-light-shiro.mov")
        try? FileManager.default.removeItem(at: outputURL)

        let writer: AVAssetWriter
        do {
            writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
        } catch {
            print("ERROR: AVAssetWriter init failed: \(error)")
            return false
        }

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.proRes4444,
            AVVideoWidthKey: 1920,
            AVVideoHeightKey: 1080,
        ]

        let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        input.expectsMediaDataInRealTime = false

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: 1920,
                kCVPixelBufferHeightKey as String: 1080,
            ]
        )

        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        for frame in 0..<totalFrames {
            // Smooth sinusoidal orbit: up/down ±15°, 1.5 cycles over 6 seconds
            let p = Double(frame) / Double(totalFrames - 1)
            rotX = orbitAmplitude * sin(2.0 * .pi * p * 2.0)

            // Let SwiftUI render
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(50))

            // Capture window via ScreenCaptureKit
            let screenshot: CGImage
            do {
                screenshot = try await SCScreenshotManager.captureImage(
                    contentFilter: filter,
                    configuration: config
                )
            } catch {
                print("WARNING: Frame \(frame) capture failed: \(error)")
                continue
            }

            // Convert and append
            guard let pb = pixelBuffer(from: screenshot, pool: adaptor.pixelBufferPool) else {
                print("WARNING: Frame \(frame) pixel buffer failed, skipping")
                continue
            }

            let presentationTime = CMTime(value: CMTimeValue(frame), timescale: CMTimeScale(fps))

            while !input.isReadyForMoreMediaData {
                try? await Task.sleep(for: .milliseconds(10))
            }

            adaptor.append(pb, withPresentationTime: presentationTime)

            if frame % 60 == 0 {
                print("  Frame \(frame)/\(totalFrames)")
            }
        }

        input.markAsFinished()
        await writer.finishWriting()

        return writer.status == .completed
    }

    // MARK: - Pixel Buffer

    private func pixelBuffer(from image: CGImage, pool: CVPixelBufferPool?) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?

        if let pool {
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer)
        } else {
            CVPixelBufferCreate(
                nil, image.width, image.height,
                kCVPixelFormatType_32BGRA, nil, &pixelBuffer
            )
        }

        guard let buffer = pixelBuffer else { return nil }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))

        return buffer
    }
}
