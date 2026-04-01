import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// MARK: - Seeded PRNG (xorshift64)

struct SeededRNG {
    var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 1 : seed
    }

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }

    mutating func nextFloat() -> Float {
        Float(next() & 0xFFFFFF) / Float(0xFFFFFF)
    }
}

// MARK: - Fiber Simulator

enum FiberSimulator {

    struct FiberParams: Sendable {
        var fiberLength: Float
        var fiberFineness: Float
        var fiberCount: Int
        var formationAlignment: Float
        var kumo: Float
        var kumoScale: Float
        var seed: UInt64

        init(
            fiberLength: Float,
            fiberFineness: Float,
            formationLayers: Float,
            formationAlignment: Float,
            kumo: Float,
            kumoScale: Float,
            seed: Float
        ) {
            self.fiberLength = fiberLength
            self.fiberFineness = fiberFineness
            self.fiberCount = Int(1500 + (8000 - 1500) * formationLayers)
            self.formationAlignment = formationAlignment
            self.kumo = kumo
            self.kumoScale = kumoScale
            self.seed = UInt64(seed)
        }
    }

    // MARK: - Generation

    nonisolated static func generate(params: FiberParams, size: Int = 1024) -> CGImage {
        var buffer = [Float](repeating: 0.0, count: size * size)
        var dirXBuffer = [Float](repeating: 0.0, count: size * size)
        var dirYBuffer = [Float](repeating: 0.0, count: size * size)
        var rng = SeededRNG(seed: params.seed)

        let fiberHalfLength = Float(size) * lerp(0.006, 0.025, params.fiberLength)
        let fiberWidth = Float(size) * lerp(0.0005, 0.0015, 1.0 - params.fiberFineness)
        let angularSpread = lerp(0.3, .pi, params.formationAlignment)

        // Nagashizuki formation passes
        let passes: [(fraction: Float, baseAngle: Float, spreadMul: Float)] = [
            (0.40, 0.15, 1.0),          // kakemizu
            (0.40, 0.15 + 1.2, 1.0),    // choshi
            (0.20, 0.15, 0.3),           // sutemizu (tight alignment)
        ]

        for pass in passes {
            let count = Int(Float(params.fiberCount) * pass.fraction)

            for _ in 0..<count {
                let ox = rng.nextFloat() * Float(size)
                let oy = rng.nextFloat() * Float(size)

                let angle = pass.baseAngle
                    + (rng.nextFloat() - 0.5) * angularSpread * pass.spreadMul

                let curvature = (rng.nextFloat() - 0.5) * 0.3

                drawFiber(
                    buffer: &buffer,
                    dirXBuffer: &dirXBuffer,
                    dirYBuffer: &dirYBuffer,
                    size: size,
                    ox: ox, oy: oy,
                    angle: angle,
                    halfLength: fiberHalfLength,
                    width: fiberWidth,
                    curvature: curvature
                )
            }
        }

        if params.kumo > 0 {
            applyKumo(
                buffer: &buffer, size: size,
                intensity: params.kumo,
                scale: params.kumoScale,
                seed: params.seed
            )
        }

        // Normalize to 0..1
        let maxVal = buffer.max() ?? 1.0
        if maxVal > 0 {
            for i in 0..<buffer.count {
                buffer[i] /= maxVal
            }
        }

        // Compute orientation map from accumulated direction vectors
        var orientationBuffer = [Float](repeating: 0.0, count: size * size)
        for i in 0..<size * size {
            if buffer[i] > 0.001 {
                let angle = atan2(dirYBuffer[i], dirXBuffer[i])
                let normalized = angle < 0 ? angle + .pi : angle  // [0, π)
                orientationBuffer[i] = normalized / .pi            // [0, 1)
            } else {
                orientationBuffer[i] = 0.5  // neutral where no fibers
            }
        }

        return bufferToCGImage(densityBuffer: buffer, orientationBuffer: orientationBuffer, size: size)
    }

    // MARK: - Fiber drawing

    /// Draw a single curved fiber as an additive gaussian soft-edge line.
    nonisolated private static func drawFiber(
        buffer: inout [Float],
        dirXBuffer: inout [Float],
        dirYBuffer: inout [Float],
        size: Int,
        ox: Float, oy: Float,
        angle: Float,
        halfLength: Float,
        width: Float,
        curvature: Float
    ) {
        let steps = Int(halfLength * 2.0)
        let sigma = width

        let ca = cos(angle)
        let sa = sin(angle)
        let radius = Int(ceil(sigma * 3.0))

        for step in 0...steps {
            let t = Float(step) / Float(steps) - 0.5 // -0.5..0.5
            let along = t * halfLength * 2.0
            let perpOffset = curvature * along * along // quadratic bend

            let px = ox + ca * along - sa * perpOffset
            let py = oy + sa * along + ca * perpOffset

            let ix = Int(px)
            let iy = Int(py)

            for dy in -radius...radius {
                for dx in -radius...radius {
                    // Wrap edges for tileability
                    let wx = ((ix + dx) % size + size) % size
                    let wy = ((iy + dy) % size + size) % size

                    let dist = sqrt(Float(dx * dx + dy * dy))
                    let falloff = exp(-dist * dist / (2.0 * sigma * sigma))

                    let idx = wy * size + wx
                    buffer[idx] += falloff
                    dirXBuffer[idx] += ca * falloff
                    dirYBuffer[idx] += sa * falloff
                }
            }
        }
    }

    // MARK: - Kumo (cloud formation)

    /// Multiplicative low-frequency density modulation.
    nonisolated private static func applyKumo(
        buffer: inout [Float],
        size: Int,
        intensity: Float,
        scale: Float,
        seed: UInt64
    ) {
        let freq = lerp(2.0, 8.0, scale)
        let seedF = Float(seed)

        for y in 0..<size {
            let v = Float(y) / Float(size)
            for x in 0..<size {
                let u = Float(x) / Float(size)

                let n = sin(u * freq + seedF * 0.1)
                    * cos(v * (freq * 0.875) + seedF * 0.07)
                    * sin((u + v) * (freq * 0.625) + seedF * 0.13)

                let modFactor = 1.0 + n * intensity * 0.3
                buffer[y * size + x] *= modFactor
            }
        }
    }

    // MARK: - Buffer to CGImage

    nonisolated private static func bufferToCGImage(
        densityBuffer: [Float],
        orientationBuffer: [Float],
        size: Int
    ) -> CGImage {
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        for i in 0..<size * size {
            let density = UInt8(min(max(densityBuffer[i] * 255.0, 0.0), 255.0))
            let orientation = UInt8(min(max(orientationBuffer[i] * 255.0, 0.0), 255.0))
            pixels[i * 4 + 0] = density       // R
            pixels[i * 4 + 1] = orientation    // G
            pixels[i * 4 + 2] = 0             // B
            pixels[i * 4 + 3] = 255           // A
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: &pixels,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: size * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )!

        return context.makeImage()!
    }

    // MARK: - Disk Cache

    nonisolated private static var cacheDirectory: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return caches.appendingPathComponent("WashiDensity-v3", isDirectory: true)
    }

    nonisolated static func loadCached(presetID: String) -> CGImage? {
        let url = cacheDirectory.appendingPathComponent("\(presetID).png")
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    nonisolated static func saveToCache(_ image: CGImage, presetID: String) {
        let dir = cacheDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("\(presetID).png")
        guard let dest = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil
        ) else { return }
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
    }

    // MARK: - Helpers

    nonisolated private static func lerp(_ a: Float, _ b: Float, _ t: Float) -> Float {
        a + (b - a) * t
    }
}
