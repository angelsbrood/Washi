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
    }

    // MARK: - Generation

    /// Generates a sheet that tiles seamlessly: fibers wrap at the edges, every
    /// noise field is periodic over the sheet, and nothing depends on position
    /// across it — so a tile's edges meet like its interior.
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
        // Each pass reads in the sheet through the angle and alignment of the
        // fibers it lays. Placement is uniform: a pour gradient or scoop
        // banding across the sheet would have to jump where the tile wraps.
        let choshiScoopCount = max(params.choshiScoops, 1)
        let choshiFractionPerScoop = 0.20 / Float(choshiScoopCount)

        var passes: [FormationPass] = [
            // Kakemizu: quick initial pour
            FormationPass(fraction: 0.40, baseAngle: 0.15, spreadMul: 1.0),
        ]

        // Choshi: multiple back-and-forth scoops at jittered angles
        let choshiBaseAngle: Float = 0.15 + 1.2
        var scoopRng = SeededRNG(seed: params.seed &+ 0xC305_0000)
        for _ in 0..<choshiScoopCount {
            let jitter = (scoopRng.nextFloat() - 0.5) * 0.4
            passes.append(FormationPass(
                fraction: choshiFractionPerScoop, baseAngle: choshiBaseAngle + jitter,
                spreadMul: 1.0))
        }

        // Sutemizu: quick final pour, tight alignment
        passes.append(FormationPass(fraction: 0.20, baseAngle: 0.15, spreadMul: 0.3))

        // Compensation for meso rejection (~40%), micro-floc expansion (~1.3×),
        // and higher density needed for layered fiber texture
        let compensationFactor: Float = 10.0

        for pass in passes {
            let count = Int(Float(scaledFiberCount) * pass.fraction * compensationFactor)

            for _ in 0..<count {
                // Per-fiber size variation: biased toward shorter fibers
                // (beaten kozo has a wide distribution — many short, few long)
                let sizeSample = rng.nextFloat()
                let lengthScale = 0.15 + pow(sizeSample, 5.0) * 1.5  // 0.15× – 1.65×
                let widthScale = 0.5 + sqrt(lengthScale) * 0.5 + rng.nextFloat() * 0.15
                let thisHalfLength = fiberHalfLength * lengthScale
                let thisWidth = fiberWidth * widthScale

                let ox = rng.nextFloat() * Float(size)
                let oy = rng.nextFloat() * Float(size)

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

            // Floor, not truncate: a point just left of or above the sheet
            // belongs to the last column or row, not the first.
            let ix = Int(px.rounded(.down))
            let iy = Int(py.rounded(.down))

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
        let broad = PeriodicNoise(periodU: freq, periodV: freq, rng: &rng)
        let fine = PeriodicNoise(periodU: freq * 2, periodV: freq * 2, rng: &rng)

        let invSize = 1.0 / Float(size)
        for y in 0..<size {
            let v = Float(y) * invSize * freq
            for x in 0..<size {
                let u = Float(x) * invSize * freq

                let n = broad(u, v) * 0.7 + fine(u * 2.0, v * 2.0) * 0.3

                let modFactor = 1.0 + n * intensity
                buffer[y * size + x] *= modFactor
            }
        }

    }

    // MARK: - Periodic simplex noise (2D)

    nonisolated private static func mod289(_ x: Float) -> Float {
        x - floor(x * (1.0 / 289.0)) * 289.0
    }

    nonisolated private static func permute(_ x: Float) -> Float {
        mod289((x * 34.0 + 1.0) * x)
    }

    /// The 2D simplex noise of Washi.metal (Gustavson), made to tile exactly
    /// over a `periodU × periodV` window of noise space so that every field
    /// built from it wraps with the sheet.
    ///
    /// Simplex noise repeats wherever its lattice does, so the window's edges
    /// are mapped onto two lattice vectors and each corner's lattice index is
    /// reduced modulo them before hashing. The equilateral lattice holds no
    /// exact axis-aligned rectangle, so the map carries a small linear
    /// distortion: about 1% at meso frequencies, a few percent at the lowest
    /// kumo frequencies.
    ///
    /// The period holds finitely many lattice corners, so their hashes are
    /// computed once into a table covering every corner the window visits.
    nonisolated private struct PeriodicNoise {
        private typealias Lattice = (k11: Int, k12: Int, k21: Int, k22: Int, det: Int)

        private let a11, a12, a21, a22: Float       // window (u, v) → simplex input space
        private let phaseX, phaseY: Float           // per-seed sub-cell phase
        private let lattice: Lattice                // period lattice in index space
        private let hashOffset: (Float, Float)      // per-seed hash offset
        private let table: [Float]                  // corner hashes over the window's index range
        private let tableI, tableJ, tableWidth, tableHeight: Int

        init(periodU: Float, periodV: Float, rng: inout SeededRNG) {
            let pu = Double(periodU), pv = Double(periodV)
            // Rotate the window (free: the noise is isotropic), skew its edges
            // into lattice index space, and round them to integer vectors;
            // keep the fit whose map strays least from a pure rotation.
            var best: (score: Double, k: (Int, Int, Int, Int))?
            for step in 0..<1200 {
                let theta = Double(step) / 1200 * .pi / 3   // the lattice repeats every 60°
                let (c, s) = (cos(theta), sin(theta))
                let edgeU = (Self.f1 * c + Self.f * s, Self.f * c + Self.f1 * s)    // S · R · (1, 0)
                let edgeV = (Self.f * c - Self.f1 * s, Self.f1 * c - Self.f * s)    // S · R · (0, 1)
                for rounding in 0..<16 {
                    let k = (Self.round(edgeU.0 * pu, up: rounding & 1 != 0),
                             Self.round(edgeU.1 * pu, up: rounding & 2 != 0),
                             Self.round(edgeV.0 * pv, up: rounding & 4 != 0),
                             Self.round(edgeV.1 * pv, up: rounding & 8 != 0))
                    guard k.0 * k.3 - k.2 * k.1 != 0 else { continue }
                    let score = Self.distortion(Self.map(k, pu, pv))
                    if score < best?.score ?? .infinity { best = (score, k) }
                }
            }
            var (k11, k12, k21, k22) = best!.k
            let a = Self.map((k11, k12, k21, k22), pu, pv)
            (a11, a12, a21, a22) = (Float(a.0), Float(a.1), Float(a.2), Float(a.3))
            // (K1, −K2) spans the same lattice; take the orientation with det > 0.
            if k11 * k22 - k21 * k12 < 0 { (k21, k22) = (-k21, -k22) }
            let lattice = (k11: k11, k12: k12, k21: k21, k22: k22, det: k11 * k22 - k21 * k12)
            self.lattice = lattice

            let hashOffset = ((rng.nextFloat() * 289).rounded(.down), (rng.nextFloat() * 289).rounded(.down))
            self.hashOffset = hashOffset
            phaseX = rng.nextFloat()
            phaseY = rng.nextFloat()

            // The map is linear, so the window's four corners bound every lattice
            // index it reaches; pad for the simplex's far corner and rounding.
            var lo = (Int.max, Int.max), hi = (Int.min, Int.min)
            for (u, v) in [(0, 0), (periodU, 0), (0, periodV), (periodU, periodV)] {
                let vx = a11 * u + a12 * v + phaseX
                let vy = a21 * u + a22 * v + phaseY
                let s = (vx + vy) * Float(Self.f)
                let i = Int(floor(vx + s)), j = Int(floor(vy + s))
                lo = (min(lo.0, i), min(lo.1, j))
                hi = (max(hi.0, i), max(hi.1, j))
            }
            (tableI, tableJ) = (lo.0 - 2, lo.1 - 2)
            (tableWidth, tableHeight) = (hi.0 - lo.0 + 5, hi.1 - lo.1 + 5)
            var table = [Float](repeating: 0, count: tableWidth * tableHeight)
            for j in 0..<tableHeight {
                for i in 0..<tableWidth {
                    table[j * tableWidth + i] = Self.reducedHash(tableI + i, tableJ + j, lattice, hashOffset)
                }
            }
            self.table = table
        }

        // Skew S = [[f1, f], [f, f1]] maps simplex input space to lattice index space.
        private static let f = (3.0.squareRoot() - 1) / 2   // 0.5 * (sqrt(3) - 1)
        private static let f1 = 1 + f

        private static func round(_ x: Double, up: Bool) -> Int {
            Int(up ? x.rounded(.up) : x.rounded(.down))
        }

        /// A = S⁻¹ · [K1 / periodU | K2 / periodV]: the map whose window edges land on K1, K2.
        private static func map(_ k: (Int, Int, Int, Int), _ pu: Double, _ pv: Double)
            -> (Double, Double, Double, Double) {
            let d = f1 * f1 - f * f
            let (s11, s12, s21, s22) = (f1 / d, -f / d, -f / d, f1 / d)
            let (b11, b21) = (Double(k.0) / pu, Double(k.1) / pu)
            let (b12, b22) = (Double(k.2) / pv, Double(k.3) / pv)
            return (s11 * b11 + s12 * b21, s11 * b12 + s12 * b22,
                    s21 * b11 + s22 * b21, s21 * b12 + s22 * b22)
        }

        /// Worst-axis scale error of a 2×2 map: max |ln σ| over its singular values.
        private static func distortion(_ a: (Double, Double, Double, Double)) -> Double {
            let sumSq = a.0 * a.0 + a.1 * a.1 + a.2 * a.2 + a.3 * a.3
            let det = abs(a.0 * a.3 - a.1 * a.2)
            let root = max(sumSq * sumSq - 4 * det * det, 0).squareRoot()
            let s1 = ((sumSq + root) / 2).squareRoot(), s2 = ((sumSq - root) / 2).squareRoot()
            return max(abs(log(s1)), abs(log(s2)))
        }

        private static func floorDiv(_ a: Int, _ b: Int) -> Int {
            let q = a / b
            return (a % b != 0) && ((a < 0) != (b < 0)) ? q - 1 : q
        }

        /// Gradient hash of a lattice corner, reduced into the period so it
        /// repeats with the window.
        private static func reducedHash(_ i: Int, _ j: Int, _ l: Lattice, _ offset: (Float, Float)) -> Float {
            let c1 = floorDiv(l.k22 * i - l.k21 * j, l.det)
            let c2 = floorDiv(l.k11 * j - l.k12 * i, l.det)
            let x = mod289(Float(i - (l.k11 * c1 + l.k21 * c2)) + offset.0)
            let y = mod289(Float(j - (l.k12 * c1 + l.k22 * c2)) + offset.1)
            return permute(permute(y) + x)
        }

        private func hash(_ i: Int, _ j: Int) -> Float {
            let ti = i - tableI, tj = j - tableJ
            guard ti >= 0, tj >= 0, ti < tableWidth, tj < tableHeight else {
                return Self.reducedHash(i, j, lattice, hashOffset)
            }
            return table[tj * tableWidth + ti]
        }

        /// Noise at (u, v); repeats exactly every `periodU` in u and `periodV` in v.
        func callAsFunction(_ u: Float, _ v: Float) -> Float {
            let vx = a11 * u + a12 * v + phaseX
            let vy = a21 * u + a22 * v + phaseY

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

            let jx = Int(ix), jy = Int(iy)
            let p = (hash(jx, jy), hash(jx + Int(i1x), jy + Int(i1y)), hash(jx + 1, jy + 1))

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

        let noise = octaves.map { octave in
            var rng = SeededRNG(seed: seed &+ octave.seedOffset)
            return PeriodicNoise(periodU: octave.frequency, periodV: octave.frequency, rng: &rng)
        }

        let invSize = 1.0 / Float(size)
        var field = [Float](repeating: 0, count: size * size)
        for y in 0..<size {
            let v = Float(y) * invSize
            for x in 0..<size {
                let u = Float(x) * invSize
                var value: Float = 0
                for (i, octave) in octaves.enumerated() {
                    let n = noise[i](u * octave.frequency, v * octave.frequency)
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
        return caches.appendingPathComponent("WashiDensity-v23", isDirectory: true)
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
