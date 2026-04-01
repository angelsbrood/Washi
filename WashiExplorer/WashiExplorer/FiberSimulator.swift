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
        var textureScale: Float

        init(
            fiberLength: Float,
            fiberFineness: Float,
            formationLayers: Float,
            formationAlignment: Float,
            kumo: Float,
            kumoScale: Float,
            seed: Float,
            textureScale: Float = 1.0
        ) {
            self.fiberLength = fiberLength
            self.fiberFineness = fiberFineness
            self.fiberCount = Int(1500 + (8000 - 1500) * formationLayers)
            self.formationAlignment = formationAlignment
            self.kumo = kumo
            self.kumoScale = kumoScale
            self.seed = UInt64(seed)
            self.textureScale = textureScale
        }
    }

    // MARK: - Formation Pass

    private struct FormationPass {
        let fraction: Float
        let baseAngle: Float
        let spreadMul: Float
        let flowAngle: Float
        let flowBias: Float
        let flowOscillations: Int
    }

    // MARK: - Generation

    nonisolated static func generate(params: FiberParams, size: Int = 1024) -> CGImage {
        var buffer = [Float](repeating: 0.0, count: size * size)
        var dirXBuffer = [Float](repeating: 0.0, count: size * size)
        var dirYBuffer = [Float](repeating: 0.0, count: size * size)
        var rng = SeededRNG(seed: params.seed)

        // Scale fiber dimensions and count by textureScale
        let ts = max(params.textureScale, 0.1)
        let fiberHalfLength = Float(size) * lerp(0.006, 0.025, params.fiberLength) / ts
        let fiberWidth = Float(size) * lerp(0.0005, 0.0015, 1.0 - params.fiberFineness) / ts
        let angularSpread = lerp(0.3, .pi, params.formationAlignment)
        let scaledFiberCount = Int(Float(params.fiberCount) * ts * ts)

        // Pre-compute meso-flocculation field
        let mesoField = generateMesoField(size: size, seed: params.seed)

        // Nagashizuki formation passes
        let passes: [FormationPass] = [
            // Kakemizu: quick initial pour, strong gradient toward pour edge
            FormationPass(fraction: 0.40, baseAngle: 0.15, spreadMul: 1.0,
                          flowAngle: 0.15, flowBias: 0.3, flowOscillations: 0),
            // Choshi: back-and-forth main formation, mild oscillation banding
            FormationPass(fraction: 0.40, baseAngle: 0.15 + 1.2, spreadMul: 1.0,
                          flowAngle: 0.15 + 1.2, flowBias: 0.15, flowOscillations: 3),
            // Sutemizu: quick final pour, tight alignment, mild gradient
            FormationPass(fraction: 0.20, baseAngle: 0.15, spreadMul: 0.3,
                          flowAngle: 0.15, flowBias: 0.2, flowOscillations: 0),
        ]

        // Compensation for meso rejection (~40%) and micro-floc expansion (~1.3×)
        let compensationFactor: Float = 1.28

        for pass in passes {
            let count = Int(Float(scaledFiberCount) * pass.fraction * compensationFactor)
            let flowCos = cos(pass.flowAngle)
            let flowSin = sin(pass.flowAngle)

            for _ in 0..<count {
                // Flow-biased placement
                let rawAlong = rng.nextFloat()
                let along = pass.flowBias < 0.001
                    ? rawAlong
                    : pow(rawAlong, 1.0 + pass.flowBias * 2.0)
                let across = rng.nextFloat()

                let rawX = (flowCos * along - flowSin * across) * Float(size)
                let rawY = (flowSin * along + flowCos * across) * Float(size)
                let ox = ((rawX.truncatingRemainder(dividingBy: Float(size))) + Float(size))
                    .truncatingRemainder(dividingBy: Float(size))
                let oy = ((rawY.truncatingRemainder(dividingBy: Float(size))) + Float(size))
                    .truncatingRemainder(dividingBy: Float(size))

                // Choshi oscillation: sinusoidal density variation from back-and-forth
                if pass.flowOscillations > 0 {
                    let oscillation = sin(along * Float(pass.flowOscillations) * .pi)
                    let threshold = 0.5 + oscillation * 0.15
                    if rng.nextFloat() > threshold { continue }
                }

                // Meso-flocculation: accept/reject based on noise field
                let mesoIdx = min(Int(oy) * size + Int(ox), mesoField.count - 1)
                let mesoValue = mesoField[max(mesoIdx, 0)]
                let mesoThreshold = 0.35 + mesoValue * 0.50
                if rng.nextFloat() > mesoThreshold { continue }

                let angle = pass.baseAngle
                    + (rng.nextFloat() - 0.5) * angularSpread * pass.spreadMul
                let curvature = (rng.nextFloat() - 0.5) * 0.3

                // Micro-flocculation: occasional fiber clusters
                let isCluster = rng.nextFloat() < 0.15
                let clusterCount = isCluster ? Int(2 + rng.nextFloat() * 2) : 1

                for c in 0..<clusterCount {
                    let cOx = c == 0 ? ox : ox + (rng.nextFloat() - 0.5) * fiberWidth * 4
                    let cOy = c == 0 ? oy : oy + (rng.nextFloat() - 0.5) * fiberWidth * 4
                    let cAngle = c == 0 ? angle : angle + (rng.nextFloat() - 0.5) * 0.1

                    drawFiber(
                        buffer: &buffer,
                        dirXBuffer: &dirXBuffer,
                        dirYBuffer: &dirYBuffer,
                        size: size,
                        ox: cOx, oy: cOy,
                        angle: cAngle,
                        halfLength: fiberHalfLength,
                        width: fiberWidth,
                        curvature: curvature
                    )
                }
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

    // MARK: - Meso-flocculation field

    /// Grid-based value noise with smoothstep interpolation.
    /// Produces tileable density variation at intermediate scale (~128px blobs at 1024px).
    nonisolated private static func generateMesoField(size: Int, seed: UInt64) -> [Float] {
        let gridSize = 8
        let cellSize = Float(size) / Float(gridSize)
        var gridRng = SeededRNG(seed: seed &+ 0xDEAD_BEEF)

        let stride = gridSize + 1
        var grid = [Float](repeating: 0, count: stride * stride)
        for i in 0..<grid.count {
            grid[i] = gridRng.nextFloat()
        }
        // Make tileable: wrap edges
        for i in 0...gridSize {
            grid[i * stride + gridSize] = grid[i * stride]
            grid[gridSize * stride + i] = grid[i]
        }

        var field = [Float](repeating: 0.5, count: size * size)
        for y in 0..<size {
            let fy = Float(y) / cellSize
            let gy = Int(fy)
            let ty = fy - Float(gy)
            let sy = ty * ty * (3 - 2 * ty)  // smoothstep
            for x in 0..<size {
                let fx = Float(x) / cellSize
                let gx = Int(fx)
                let tx = fx - Float(gx)
                let sx = tx * tx * (3 - 2 * tx)

                let v00 = grid[gy * stride + gx]
                let v10 = grid[gy * stride + gx + 1]
                let v01 = grid[(gy + 1) * stride + gx]
                let v11 = grid[(gy + 1) * stride + gx + 1]

                let top = v00 + (v10 - v00) * sx
                let bot = v01 + (v11 - v01) * sx
                field[y * size + x] = top + (bot - top) * sy
            }
        }
        return field
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
        return caches.appendingPathComponent("WashiDensity-v4", isDirectory: true)
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
