import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// MARK: - Seeded PRNG (xorshift64)

nonisolated struct SeededRNG: Sendable {
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
        var choshiScoops: Int

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
            self.choshiScoops = 3 + Int(formationLayers * 5)
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
        let fiberHalfLength = Float(size) * lerp(0.004, 0.018, params.fiberLength) / ts
        let fiberWidth = Float(size) * lerp(0.0004, 0.0012, 1.0 - params.fiberFineness) / ts
        let angularSpread = lerp(0.3, .pi, params.formationAlignment)
        let scaledFiberCount = Int(Float(params.fiberCount) * ts * ts)

        // Pre-compute meso-flocculation field
        let mesoField = generateMesoField(size: size, seed: params.seed)

        // --- Stage 1: Base mat (continuous paper body) ---
        // Direct density floor with meso variation — no individual fibrils.
        // Calibrated so mat normalizes to ~0.5 (shader neutral) after
        // prominent fiber peaks set the max.
        let matBaseDensity = lerp(3.0, 10.0, params.fiberFineness)
            * Float(scaledFiberCount) / 4200.0
        let matOrientField = generateMesoField(size: size, seed: params.seed &+ 42)

        for y in 0..<size {
            for x in 0..<size {
                let idx = y * size + x
                let mesoValue = mesoField[idx]
                let density = matBaseDensity * (0.3 + mesoValue * 1.4)
                buffer[idx] = density
                // Smooth random orientation, weighted lightly so prominent
                // fibers dominate where they exist
                let matAngle = matOrientField[idx] * .pi
                let weight = density * 0.2
                dirXBuffer[idx] = cos(matAngle) * weight
                dirYBuffer[idx] = sin(matAngle) * weight
            }
        }

        // --- Stage 1b: Mat fibrils (granular texture) ---
        // Tiny deposited fibers create the fine-grained variation visible in real
        // washi. Without these, the smooth mat floor looks blobby and synthetic.
        let matFibrilHalfLength = fiberHalfLength * 0.20
        let matFibrilWidth = max(fiberWidth * 0.5, 0.3)
        let matFibrilCount = Int(Float(scaledFiberCount) * 50.0)
        var matRng = SeededRNG(seed: params.seed &+ 0xF1B0_0000)

        for _ in 0..<matFibrilCount {
            let fx = matRng.nextFloat() * Float(size)
            let fy = matRng.nextFloat() * Float(size)

            let mesoIdx = min(Int(fy) * size + Int(fx), mesoField.count - 1)
            let mesoValue = mesoField[max(mesoIdx, 0)]
            let mesoThreshold = 0.35 + mesoValue * 0.50
            if matRng.nextFloat() > mesoThreshold { continue }

            let angle = matRng.nextFloat() * .pi
            let curv = (matRng.nextFloat() - 0.5) * 0.15

            drawFiber(
                buffer: &buffer, dirXBuffer: &dirXBuffer, dirYBuffer: &dirYBuffer,
                size: size, ox: fx, oy: fy, angle: angle,
                halfLength: matFibrilHalfLength, width: matFibrilWidth,
                curvature: curv, wobbleFreq: 0, wobbleAmp: 0, taperAmount: 0.15)
        }

        // --- Stage 2: Prominent fibers (nagashizuki) ---
        let choshiScoopCount = max(params.choshiScoops, 1)
        let choshiFractionPerScoop = 0.40 / Float(choshiScoopCount)

        var passes: [FormationPass] = [
            // Kakemizu: quick initial pour, strong gradient toward pour edge
            FormationPass(fraction: 0.40, baseAngle: 0.15, spreadMul: 1.0,
                          flowAngle: 0.15, flowBias: 0.3, flowOscillations: 0),
        ]

        // Choshi: multiple back-and-forth scoops at jittered angles
        let choshiBaseAngle: Float = 0.15 + 1.2
        var scoopRng = SeededRNG(seed: params.seed &+ 0xC305_0000)
        for _ in 0..<choshiScoopCount {
            let jitter = (scoopRng.nextFloat() - 0.5) * 0.4
            let angle = choshiBaseAngle + jitter
            let osc = 2 + Int(scoopRng.nextFloat() * 3)
            passes.append(FormationPass(
                fraction: choshiFractionPerScoop, baseAngle: angle,
                spreadMul: 1.0, flowAngle: angle,
                flowBias: 0.15, flowOscillations: osc))
        }

        // Sutemizu: quick final pour, tight alignment, mild gradient
        passes.append(FormationPass(
            fraction: 0.20, baseAngle: 0.15, spreadMul: 0.3,
            flowAngle: 0.15, flowBias: 0.2, flowOscillations: 0))

        // Compensation for meso rejection (~40%), micro-floc expansion (~1.3×),
        // and higher density needed for layered fiber texture
        let compensationFactor: Float = 10.0

        for pass in passes {
            let count = Int(Float(scaledFiberCount) * pass.fraction * compensationFactor)
            let flowCos = cos(pass.flowAngle)
            let flowSin = sin(pass.flowAngle)

            for _ in 0..<count {
                // Per-fiber size variation: biased toward shorter fibers
                // (beaten kozo has a wide distribution — many short, few long)
                let sizeSample = rng.nextFloat()
                let lengthScale = 0.15 + pow(sizeSample, 5.0) * 1.5  // 0.15× – 1.65×
                let widthScale = 0.5 + sqrt(lengthScale) * 0.5 + rng.nextFloat() * 0.15
                let thisHalfLength = fiberHalfLength * lengthScale
                let thisWidth = fiberWidth * widthScale

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
                let wobbleFreq = lerp(5.0, 2.0, min(lengthScale, 1.0))
                let wobbleAmp = pow(lengthScale, 2.0) * fiberWidth * 4.0
                let taperAmount = lerp(0.2, 0.7, min(lengthScale, 1.0))

                // Micro-flocculation: fiber clusters create visible knots
                let isCluster = rng.nextFloat() < 0.35
                let clusterCount = isCluster ? Int(4 + rng.nextFloat() * 5) : 1

                for c in 0..<clusterCount {
                    let cOx = c == 0 ? ox : ox + (rng.nextFloat() - 0.5) * thisWidth * 8
                    let cOy = c == 0 ? oy : oy + (rng.nextFloat() - 0.5) * thisWidth * 8
                    let cAngle = c == 0 ? angle : angle + (rng.nextFloat() - 0.5) * 0.2

                    drawFiber(
                        buffer: &buffer,
                        dirXBuffer: &dirXBuffer,
                        dirYBuffer: &dirYBuffer,
                        size: size,
                        ox: cOx, oy: cOy,
                        angle: cAngle,
                        halfLength: thisHalfLength,
                        width: thisWidth,
                        curvature: curvature,
                        wobbleFreq: wobbleFreq,
                        wobbleAmp: wobbleAmp,
                        taperAmount: taperAmount
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

        // Percentile normalization: p5→0.0, p95→1.0 for full density range
        let sorted = buffer.sorted()
        let count = sorted.count
        let p5 = sorted[Int(Float(count) * 0.05)]
        let p95 = sorted[Int(Float(count) * 0.95)]
        let range = max(p95 - p5, 0.001)
        for i in 0..<buffer.count {
            buffer[i] = min(max((buffer[i] - p5) / range, 0.0), 1.0)
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
        curvature: Float,
        wobbleFreq: Float,
        wobbleAmp: Float,
        taperAmount: Float
    ) {
        let steps = max(Int(halfLength * 2.0), 1)
        let sigma = max(width, 0.1)

        let ca = cos(angle)
        let sa = sin(angle)

        for step in 0...steps {
            let t = Float(step) / Float(steps) - 0.5 // -0.5..0.5
            let along = t * halfLength * 2.0

            // Parabolic bend + sinusoidal wobble damped at ends
            let perpBend = curvature * along * along
            let envelope = 1.0 - 4.0 * t * t
            let wobble = wobbleAmp * sin(t * wobbleFreq * 2.0 * .pi) * envelope
            let perpOffset = perpBend + wobble

            let px = ox + ca * along - sa * perpOffset
            let py = oy + sa * along + ca * perpOffset

            let ix = Int(px)
            let iy = Int(py)

            // Width taper: thicker middle, thinner ends
            let taperScale = 1.0 - taperAmount * 4.0 * t * t
            let localSigma = sigma * max(taperScale, 0.15)
            let localRadius = Int(ceil(localSigma * 3.0))

            for dy in -localRadius...localRadius {
                for dx in -localRadius...localRadius {
                    // Wrap edges for tileability
                    let wx = ((ix + dx) % size + size) % size
                    let wy = ((iy + dy) % size + size) % size

                    let dist = sqrt(Float(dx * dx + dy * dy))
                    let falloff = exp(-dist * dist / (2.0 * localSigma * localSigma))

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
        guard intensity > 0.001 else { return }
        let freq = lerp(2.0, 8.0, scale)
        var rng = SeededRNG(seed: seed &+ 0xBADA_CAFE)
        let ox = rng.nextFloat() * 1000.0
        let oy = rng.nextFloat() * 1000.0

        let invSize = 1.0 / Float(size)
        for y in 0..<size {
            let v = Float(y) * invSize
            for x in 0..<size {
                let u = Float(x) * invSize

                var n = snoise(u * freq + ox, v * freq + oy) * 0.7
                n += snoise(u * freq * 2.0 + ox + 50, v * freq * 2.0 + oy + 50) * 0.3

                let modFactor = 1.0 + n * intensity
                buffer[y * size + x] *= modFactor
            }
        }

    }

    // MARK: - Simplex noise (2D) — Gustavson, ported from Washi.metal

    nonisolated private static func mod289(_ x: Float) -> Float {
        x - floor(x * (1.0 / 289.0)) * 289.0
    }

    nonisolated private static func permute(_ x: Float) -> Float {
        mod289((x * 34.0 + 1.0) * x)
    }

    nonisolated private static func permute(_ x: (Float, Float, Float)) -> (Float, Float, Float) {
        (permute(x.0), permute(x.1), permute(x.2))
    }

    nonisolated private static func snoise(_ vx: Float, _ vy: Float) -> Float {
        let Cx: Float = 0.211324865405187   // (3.0 - sqrt(3.0)) / 6.0
        let Cy: Float = 0.366025403784439   // 0.5 * (sqrt(3.0) - 1.0)
        let Cz: Float = -0.577350269189626  // -1.0 + 2.0 * Cx
        let Cw: Float = 0.024390243902439   // 1.0 / 41.0

        let s = (vx + vy) * Cy
        let ix = floor(vx + s)
        let iy = floor(vy + s)

        let t = (ix + iy) * Cx
        let x0x = vx - ix + t
        let x0y = vy - iy + t

        let i1x: Float = x0x > x0y ? 1.0 : 0.0
        let i1y: Float = x0x > x0y ? 0.0 : 1.0

        let x1x = x0x - i1x + Cx
        let x1y = x0y - i1y + Cx
        let x2x = x0x + Cz
        let x2y = x0y + Cz

        let jx = mod289(ix)
        let jy = mod289(iy)
        let pInner = permute((jy, jy + i1y, jy + 1.0))
        let p = permute((pInner.0 + jx, pInner.1 + jx + i1x, pInner.2 + jx + 1.0))

        var m0 = max(0.5 - (x0x * x0x + x0y * x0y), 0.0)
        var m1 = max(0.5 - (x1x * x1x + x1y * x1y), 0.0)
        var m2 = max(0.5 - (x2x * x2x + x2y * x2y), 0.0)
        m0 *= m0; m0 *= m0
        m1 *= m1; m1 *= m1
        m2 *= m2; m2 *= m2

        let gx0 = 2.0 * (p.0 * Cw - floor(p.0 * Cw)) - 1.0
        let gx1 = 2.0 * (p.1 * Cw - floor(p.1 * Cw)) - 1.0
        let gx2 = 2.0 * (p.2 * Cw - floor(p.2 * Cw)) - 1.0
        let h0 = abs(gx0) - 0.5
        let h1 = abs(gx1) - 0.5
        let h2 = abs(gx2) - 0.5
        let a0 = gx0 - floor(gx0 + 0.5)
        let a1 = gx1 - floor(gx1 + 0.5)
        let a2 = gx2 - floor(gx2 + 0.5)

        m0 *= 1.79284291400159 - 0.85373472095314 * (a0 * a0 + h0 * h0)
        m1 *= 1.79284291400159 - 0.85373472095314 * (a1 * a1 + h1 * h1)
        m2 *= 1.79284291400159 - 0.85373472095314 * (a2 * a2 + h2 * h2)

        let g0 = a0 * x0x + h0 * x0y
        let g1 = a1 * x1x + h1 * x1y
        let g2 = a2 * x2x + h2 * x2y

        return 130.0 * (m0 * g0 + m1 * g1 + m2 * g2)
    }

    // MARK: - Meso-flocculation field

    /// Multi-octave simplex noise for meso-scale density variation.
    /// Three octaves at frequencies 8, 16, 32 produce organic, isotropic
    /// variation without the axis-aligned grid artifacts of value noise.
    nonisolated private static func generateMesoField(size: Int, seed: UInt64) -> [Float] {
        let octaves: [(frequency: Float, amplitude: Float, seedOffset: UInt64)] = [
            (8,  1.0,  0xDEAD_BEEF),
            (16, 0.5,  0xCAFE_BABE),
            (32, 0.25, 0xFACE_FEED),
        ]
        let totalAmplitude = octaves.reduce(Float(0)) { $0 + $1.amplitude }

        var offsets: [(Float, Float)] = []
        for octave in octaves {
            var rng = SeededRNG(seed: seed &+ octave.seedOffset)
            offsets.append((rng.nextFloat() * 1000.0, rng.nextFloat() * 1000.0))
        }

        let invSize = 1.0 / Float(size)
        var field = [Float](repeating: 0, count: size * size)
        for y in 0..<size {
            let v = Float(y) * invSize
            for x in 0..<size {
                let u = Float(x) * invSize
                var value: Float = 0
                for (i, octave) in octaves.enumerated() {
                    let (ox, oy) = offsets[i]
                    let n = snoise(u * octave.frequency + ox, v * octave.frequency + oy)
                    value += (n + 1.0) * 0.5 * octave.amplitude
                }
                field[y * size + x] = value / totalAmplitude
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
        return caches.appendingPathComponent("WashiDensity-v22", isDirectory: true)
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
