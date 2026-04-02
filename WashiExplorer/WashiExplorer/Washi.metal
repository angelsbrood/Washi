#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// ============================================================
// Washi fiber overlay — v2
//
// colorEffect on a Color.white overlay above an untouched system
// material. System material (background) provides blur, this
// shader (overlay) provides texture as semi-transparent
// modulation pixels (premultiplied alpha).
//
// v2: ridged multifractal fibers, domain warping, sparse
// prominent fibers, bimodal contrast curve, kumo as threshold
// warp, fiber-scale variation.
// ============================================================

// ============================================================
// Simplex noise (2D) — Gustavson implementation
// ============================================================

float3 mod289(float3 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
float2 mod289(float2 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
float3 permute(float3 x) { return mod289(((x * 34.0) + 1.0) * x); }

float snoise(float2 v) {
    const float4 C = float4(
         0.211324865405187,   // (3.0 - sqrt(3.0)) / 6.0
         0.366025403784439,   // 0.5 * (sqrt(3.0) - 1.0)
        -0.577350269189626,   // -1.0 + 2.0 * C.x
         0.024390243902439    // 1.0 / 41.0
    );

    float2 i = floor(v + dot(v, C.yy));
    float2 x0 = v - i + dot(i, C.xx);

    float2 i1 = (x0.x > x0.y) ? float2(1.0, 0.0) : float2(0.0, 1.0);
    float4 x12 = x0.xyxy + C.xxzz;
    x12.xy -= i1;

    i = mod289(i);
    float3 p = permute(permute(i.y + float3(0.0, i1.y, 1.0))
                                    + i.x + float3(0.0, i1.x, 1.0));

    float3 m = max(0.5 - float3(dot(x0, x0), dot(x12.xy, x12.xy),
                                 dot(x12.zw, x12.zw)), 0.0);
    m = m * m;
    m = m * m;

    float3 x = 2.0 * fract(p * C.www) - 1.0;
    float3 h = abs(x) - 0.5;
    float3 ox = floor(x + 0.5);
    float3 a0 = x - ox;

    m *= 1.79284291400159 - 0.85373472095314 * (a0 * a0 + h * h);

    float3 g;
    g.x = a0.x * x0.x + h.x * x0.y;
    g.yz = a0.yz * x12.xz + h.yz * x12.yw;

    return 130.0 * dot(m, g);
}

// ============================================================
// Deterministic hashes for fiber scattering (Tier 2)
// ============================================================

float hash21(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

float2 hash22(float2 p) {
    float3 a = fract(float3(p.xyx) * float3(123.34, 234.34, 345.65));
    a += dot(a, a + 34.45);
    return fract(float2(a.x * a.y, a.y * a.z));
}

// ============================================================
// Technique 1: Ridged multifractal fiber layer
//
// 1.0 - abs(noise) creates sharp peaks at zero-crossings —
// thin bright ridges that read as individual fiber strands.
// pow(..., sharpness) controls fiber thickness. Musgrove's
// weight feedback creates heterogeneity: fine detail only
// appears near coarse ridges.
// ============================================================

float ridgedFiberLayer(
    float2 uv,
    float angle,        // fiber alignment direction (radians)
    float stretch,      // elongation ratio (higher = longer fibers)
    float scale,        // overall frequency
    float sharpness,    // ridge sharpness (higher = thinner fibers)
    float seed          // variation offset
) {
    // Rotate UV space
    float c = cos(angle);
    float s = sin(angle);
    float2 rotated = float2(
        uv.x * c - uv.y * s,
        uv.x * s + uv.y * c
    );

    // Stretch along fiber direction
    float2 stretched = float2(rotated.x / stretch, rotated.y) * scale;

    // Ridged multifractal — 3 octaves
    float value = 0.0;
    float amplitude = 1.0;
    float2 p = stretched + seed;
    float weight = 1.0;

    for (int i = 0; i < 3; i++) {
        float n = snoise(p);

        // Ridge transform: sharp peaks at zero-crossings
        n = 1.0 - abs(n);

        // Sharpen the ridges — thinner fibers
        n = pow(n, sharpness);

        // Weight by previous octave (Musgrove's ridged multifractal)
        n *= weight;
        weight = saturate(n);

        value += n * amplitude;
        p *= 2.0;           // lacunarity
        amplitude *= 0.5;   // gain
    }

    return value;
}

// ============================================================
// Technique 3: Sparse prominent fiber
//
// Very high stretch, aggressively thresholded ridge noise.
// Produces a few clearly visible individual fiber strands —
// the signature mark of handmade kozo.
// ============================================================

float sparseProminentFiber(
    float2 uv,
    float angle,
    float scale,
    float seed
) {
    float c = cos(angle);
    float s = sin(angle);
    float2 rotated = float2(
        uv.x * c - uv.y * s,
        uv.x * s + uv.y * c
    );

    // Very high stretch — long, continuous fibers
    float2 stretched = float2(rotated.x / 12.0, rotated.y) * scale;

    float n = snoise(stretched + seed);

    // Ridge transform
    n = 1.0 - abs(n);

    // Aggressive threshold: only the sharpest peaks survive
    n = pow(n, 6.0);

    // Clean up: only peaks above a cutoff
    n = smoothstep(0.15, 0.5, n);

    return n;
}

// ============================================================
// Main washi shader — v2
//
// colorEffect on a Color.white overlay. Outputs semi-transparent
// premultiplied-alpha modulation pixels.
// ============================================================

[[ stitchable ]] half4 washi(
    float2 position,
    half4 color,            // input pixel (white — overwritten)
    float4 bounds,          // .boundingRect: x, y, width, height
    float fiberLength,      // how long fibers are (stretch ratio) [0.3..1.0]
    float fiberFineness,    // coarse <-> fine (frequency) [0.2..1.0]
    float fiberVisibility,  // how prominent fiber structure is [0..1]
    float formationLayers,  // 1 = directional, 3 = complex interweave [0..1]
    float formationAlignment, // how parallel the layers are [0..1]
    float kumo,             // cloud formation intensity [0..1]
    float kumoScale,        // cloud formation size [0.1..1.0]
    float surface,          // fine surface roughness [0..1]
    float warmth,           // fiber material warmth bias [0..1]
    float seed              // variation seed
) {
    float2 size = bounds.zw;
    float2 uv = position / size;

    // ---- Derive internal parameters from user-facing values ----

    // Fiber stretch: fiberLength [0.3..1.0] -> stretch ratio [3..10]
    float stretch = mix(3.0, 10.0, fiberLength);

    // Fiber scale: fiberFineness [0.2..1.0] -> noise frequency
    float fScale = mix(15.0, 60.0, fiberFineness);

    // Ridge sharpness: higher fineness = thinner/sharper fibers
    float sharpness = mix(1.5, 3.0, fiberFineness);

    // Number of effective layers (1, 2, or 3)
    int numLayers = int(mix(1.0, 3.0, formationLayers) + 0.5);

    // Angular spread between layers
    // alignment [0..1] -> spread [0.15..1.5] radians
    float angularSpread = mix(0.15, 1.5, 1.0 - formationAlignment);

    // Base angle — slight off-horizontal for naturalism
    float baseAngle = 0.15;


    // ================================================================
    // Technique 2: Domain warp — organic fiber curvature
    //
    // Distort UV space with low-frequency noise before generating
    // fibers. Gives fibers gentle curves instead of ruler-straight
    // paths. Warp amount is small — fibers are generally straight
    // but with subtle organic bends from water flow.
    // ================================================================

    float warpAmount = 0.025; // 2.5% of UV space
    float2 warp = float2(
        snoise(uv * 3.5 + seed + 500.0),
        snoise(uv * 3.5 + seed + 600.0)
    );
    float2 warped_uv = uv + warp * warpAmount;


    // ================================================================
    // Technique 1: Ridged fiber layers
    //
    // Multiple layers at different angles, weighted by formationLayers.
    // Each layer uses ridged multifractal noise for sharp, strand-like
    // ridges.
    // ================================================================

    float fiber_density = 0.0;

    // Primary layer — always present, dominant
    float primary = ridgedFiberLayer(
        warped_uv,
        baseAngle,
        stretch,
        fScale,
        sharpness,
        seed
    );
    fiber_density += primary * 0.55;

    // Secondary layer — crossing fibers
    if (numLayers >= 2) {
        float secondary = ridgedFiberLayer(
            warped_uv,
            baseAngle + angularSpread,
            stretch * 0.75,    // slightly shorter fibers
            fScale * 0.9,
            sharpness * 0.9,   // slightly softer
            seed + 47.0
        );
        fiber_density += secondary * 0.30;
    }

    // Tertiary layer — subtle cross-fibers
    if (numLayers >= 3) {
        float tertiary = ridgedFiberLayer(
            warped_uv,
            baseAngle + angularSpread * 2.0,
            stretch * 0.6,
            fScale * 0.85,
            sharpness * 0.85,
            seed + 113.0
        );
        fiber_density += tertiary * 0.15;
    }


    // ================================================================
    // Technique 3: Sparse prominent fibers
    //
    // A few clearly visible individual strands scattered across the
    // surface — the signature of handmade washi.
    // ================================================================

    float prominent = sparseProminentFiber(
        warped_uv,
        baseAngle + 0.3,  // slightly off from primary direction
        fScale * 0.6,
        seed + 200.0
    );

    // Second sparse layer at a different angle
    prominent += sparseProminentFiber(
        warped_uv,
        baseAngle + angularSpread * 0.7,
        fScale * 0.5,
        seed + 250.0
    );

    // Add prominent fibers on top of base density
    fiber_density += prominent * 0.3;


    // ================================================================
    // Technique 6: Fiber-scale variation
    //
    // Modulate fiber prominence across the sheet with low-frequency
    // noise. Some areas have coarser, more visible fibers; others
    // are finer and more uniform. Prevents uniform character.
    // ================================================================

    float scaleVar = snoise(uv * 2.5 + seed + 700.0) * 0.5 + 0.5;
    scaleVar = mix(0.7, 1.3, scaleVar);
    fiber_density *= scaleVar;


    // ================================================================
    // Fine surface texture
    //
    // Very high frequency, very subtle noise — prevents digital
    // flatness in the gaps between fibers.
    // ================================================================

    float surfaceNoise = snoise(uv * fScale * 3.0 + seed + 300.0);
    fiber_density += surfaceNoise * surface * 0.08;


    // ================================================================
    // Technique 5: Kumo (cloud formation) as threshold warp
    //
    // Shift the contrast threshold with low-frequency noise. The
    // boundary between "dense" and "sparse" shifts organically —
    // exactly how real kumo works (uneven pulp distribution).
    // ================================================================

    float kumoNoise = snoise(uv * mix(2.0, 6.0, kumoScale) + seed + 400.0);
    float kumoShift = kumoNoise * kumo * 0.15;


    // ================================================================
    // Technique 4: Contrast curve — bimodal density
    //
    // smoothstep pushes the distribution toward dense-or-translucent
    // extremes. Kumo shift moves the thresholds, creating cloud-like
    // variation in where the dense/sparse boundary falls.
    // ================================================================

    float loThreshold = 0.15 + kumoShift;
    float hiThreshold = 0.55 + kumoShift;
    float density = smoothstep(loThreshold, hiThreshold, fiber_density);


    // ================================================================
    // Output: semi-transparent modulation (premultiplied alpha)
    //
    // High density (fiber-dense) -> semi-transparent darkening
    // Low density (translucent) -> semi-transparent brightening
    // ================================================================

    float modulation = (density - 0.5) * fiberVisibility * 2.0;

    float alpha = abs(modulation);

    // Premultiplied alpha output
    half3 modColor;
    if (modulation > 0.0) {
        // Dense fibers -> darken (black with alpha)
        modColor = half3(0.0);
    } else {
        // Sparse/translucent -> brighten (white with alpha, premultiplied)
        modColor = half3(half(alpha));
    }

    // ---- Optional warmth ----
    // Kozo fiber has a faint warm material cast. Applied as a subtle
    // shift in dense fiber areas only.
    if (warmth > 0.0 && modulation > 0.0) {
        float warmFactor = modulation * warmth;
        modColor.r += half(warmFactor * 0.015);
        modColor.g += half(warmFactor * 0.008);
    }

    return half4(modColor, half(alpha));
}

// ============================================================
// Debug visualization: opaque grayscale fiber density
// (for explorer app — shows the density map)
// ============================================================

[[ stitchable ]] half4 washiDebug(
    float2 position,
    half4 color,
    float4 bounds,
    float fiberLength,
    float fiberFineness,
    float fiberVisibility,
    float formationLayers,
    float formationAlignment,
    float kumo,
    float kumoScale,
    float surface,
    float warmth,
    float seed
) {
    // Call the main shader to get modulation
    half4 mod = washi(position, color, bounds,
        fiberLength, fiberFineness, fiberVisibility,
        formationLayers, formationAlignment,
        kumo, kumoScale, surface, warmth, seed);

    // Convert modulation to visible grayscale
    float brightness = 0.5;
    if (mod.a > 0.001h) {
        if (mod.r < 0.01h) {
            // Darkening pixel — reduce brightness
            brightness -= float(mod.a) * 0.5;
        } else {
            // Brightening pixel — increase brightness
            brightness += float(mod.a) * 0.5;
        }
    }

    return half4(half3(half(brightness)), 1.0h);
}

// ============================================================
// Tier 2: GPU Fiber Scattering
//
// Scatters individual fiber segments across a grid and computes
// density from their overlap. Each pixel evaluates its distance
// to nearby fibers. This directly models what washi IS — a
// collection of individual fibers — rather than trying to make
// noise look like fibers.
// ============================================================

[[ stitchable ]] half4 washiScattered(
    float2 position,
    half4 color,
    float4 bounds,
    float fiberLength,        // length of individual fibers [0.3..1.0]
    float fiberFineness,      // fiber width: fine ↔ coarse [0.2..1.0]
    float fiberVisibility,    // modulation depth [0..1]
    float formationLayers,    // fibers per cell [0..1] → maps to 1–3
    float formationAlignment, // angular spread [0..1]
    float kumo,               // density variation [0..1]
    float kumoScale,          // density variation size [0.1..1.0]
    float surface,            // fine surface noise [0..1]
    float warmth,             // warm bias [0..1]
    float seed
) {
    float2 size = bounds.zw;
    float2 uv = position / size;

    // ---- Derive internal parameters ----

    // Grid density: controls how many cells (and thus fibers) per unit area.
    // Higher = more fibers = denser paper.
    float gridScale = mix(20.0, 60.0, fiberFineness);

    // Fiber segment half-length in UV cell space
    float halfLength = mix(0.5, 1.2, fiberLength);

    // Fiber width (distance falloff radius)
    float fiberWidth = mix(0.12, 0.025, fiberFineness);

    // Fibers per cell
    int fibersPerCell = int(mix(2.0, 5.0, formationLayers) + 0.5);

    // Angular spread: formationAlignment 0 = random, 1 = aligned
    float angularRange = mix(3.14159, 0.15, formationAlignment);

    // Base angle (slight off-horizontal bias)
    float baseAngle = 0.15;

    // Scale UV to grid
    float2 gridUV = uv * gridScale;


    // ---- Slight domain warp for organic curvature ----
    float2 warp = float2(
        snoise(uv * 4.0 + seed + 500.0),
        snoise(uv * 4.0 + seed + 600.0)
    );
    gridUV += warp * 0.6;


    // ---- Scatter fibers and accumulate density ----

    float2 cellID = floor(gridUV);
    float density = 0.0;

    // Check 3×3 neighborhood (like Worley noise)
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            float2 neighbor = cellID + float2(x, y);

            for (int f = 0; f < fibersPerCell; f++) {
                // Deterministic fiber properties from cell hash
                float2 h = hash22(neighbor + float2(float(f) * 17.0, seed));
                float angleHash = hash21(neighbor + float2(float(f) * 31.0, seed + 7.0));

                // Per-fiber width: sqrt distribution skews toward thicker
                float widthVar = hash21(neighbor + float2(float(f) * 53.0, seed + 13.0));
                widthVar = pow(widthVar, 0.5);
                float thisFiberWidth = fiberWidth * mix(0.4, 2.5, widthVar);

                // Per-fiber length variation
                float lengthVar = hash21(neighbor + float2(float(f) * 71.0, seed + 19.0));
                float thisHalfLength = halfLength * mix(0.4, 1.5, lengthVar);

                // Fiber origin: random point within the cell
                float2 origin = neighbor + h;

                // Fiber angle: biased toward baseAngle, spread by alignment
                float angle = baseAngle + (angleHash - 0.5) * angularRange;

                // Per-fiber curvature: perpendicular offset at midpoint
                float curvature = (hash21(neighbor + float2(float(f) * 89.0, seed + 23.0)) - 0.5) * 0.8;

                // Fiber endpoints
                float2 dir = float2(cos(angle), sin(angle)) * thisHalfLength;
                float2 a = origin - dir;
                float2 b = origin + dir;

                // Curved midpoint: offset perpendicular to fiber direction
                float2 perp = float2(-sin(angle), cos(angle));
                float2 mid = (a + b) * 0.5 + perp * curvature * thisHalfLength;

                // Distance to curved fiber: min of two sub-segments A→M, M→B
                float2 p = gridUV;

                float2 pa1 = p - a;
                float2 ba1 = mid - a;
                float t1 = saturate(dot(pa1, ba1) / dot(ba1, ba1));
                float dist1 = length(pa1 - ba1 * t1);

                float2 pa2 = p - mid;
                float2 ba2 = b - mid;
                float t2 = saturate(dot(pa2, ba2) / dot(ba2, ba2));
                float dist2 = length(pa2 - ba2 * t2);

                float dist = min(dist1, dist2);

                // Soft falloff with per-fiber width
                float contrib = smoothstep(thisFiberWidth, thisFiberWidth * 0.4, dist);

                density += contrib;
            }
        }
    }

    // Soft saturation: density accumulates naturally, plateaus gently.
    // Exponential mapping is physically correct for fiber overlap —
    // each additional fiber contributes less when already near-opaque.
    density = 1.0 - exp(-density * mix(0.5, 1.5, formationLayers));


    // ---- Kumo: large-scale density variation ----
    // Shift the density threshold organically
    float kumoNoise = snoise(uv * mix(2.0, 6.0, kumoScale) + seed + 400.0);
    float kumoShift = kumoNoise * kumo * 0.2;
    density = smoothstep(0.2 + kumoShift, 0.7 + kumoShift, density);


    // ---- Fine surface texture ----
    float surfaceNoise = snoise(uv * gridScale * 3.0 + seed + 300.0);
    density += surfaceNoise * surface * 0.05;
    density = saturate(density);


    // ---- Output: same semi-transparent modulation as Tier 1 ----
    float modulation = (density - 0.5) * fiberVisibility * 2.0;
    float alpha = abs(modulation);

    half3 modColor;
    if (modulation > 0.0) {
        modColor = half3(0.0);  // darken
    } else {
        modColor = half3(half(alpha));  // brighten (premultiplied)
    }

    // Warmth
    if (warmth > 0.0 && modulation > 0.0) {
        float warmFactor = modulation * warmth;
        modColor.r += half(warmFactor * 0.015);
        modColor.g += half(warmFactor * 0.008);
    }

    return half4(modColor, half(alpha));
}

// ============================================================
// Debug visualization: opaque grayscale scattered fiber density
// ============================================================

[[ stitchable ]] half4 washiScatteredDebug(
    float2 position,
    half4 color,
    float4 bounds,
    float fiberLength,
    float fiberFineness,
    float fiberVisibility,
    float formationLayers,
    float formationAlignment,
    float kumo,
    float kumoScale,
    float surface,
    float warmth,
    float seed
) {
    half4 mod = washiScattered(position, color, bounds,
        fiberLength, fiberFineness, fiberVisibility,
        formationLayers, formationAlignment,
        kumo, kumoScale, surface, warmth, seed);

    float brightness = 0.5;
    if (mod.a > 0.001h) {
        if (mod.r < 0.01h) {
            brightness -= float(mod.a) * 0.5;
        } else {
            brightness += float(mod.a) * 0.5;
        }
    }

    return half4(half3(half(brightness)), 1.0h);
}

// ============================================================
// Debug visualization: amber density ramp
//
// Maps the R channel (fiber density 0..1) through a warm amber
// color ramp. Five sRGB stops along a ~30°–40° hue arc:
//   0.00  dark roasted umber    0.25  warm copper
//   0.50  rich amber            0.75  golden cream
//   1.00  pale parchment
// ============================================================

[[ stitchable ]] half4 amberDensity(
    float2 position,
    half4 color
) {
    half d = half(saturate(float(color.r)));

    half3 c0 = half3(0.11h, 0.07h, 0.035h);   // substrate
    half3 c1 = half3(0.63h, 0.40h, 0.23h);     // copper
    half3 c2 = half3(0.78h, 0.58h, 0.29h);     // amber
    half3 c3 = half3(0.94h, 0.85h, 0.66h);     // golden
    half3 c4 = half3(0.98h, 0.94h, 0.86h);     // parchment

    half3 rgb = mix(c0, c1, saturate(d * 5.0h));
    rgb = mix(rgb, c2, saturate((d - 0.20h) * 4.0h));
    rgb = mix(rgb, c3, saturate((d - 0.45h) * 4.0h));
    rgb = mix(rgb, c4, saturate((d - 0.70h) * 3.333h));

    return half4(rgb, 1.0h);
}

// ============================================================
// Tier 3: Simulated Fiber Deposition
//
// The density map is precomputed on CPU (FiberSimulator) and
// rendered as a SwiftUI Image. This shader receives each pixel's
// grayscale density as its input color and converts it to the
// same semi-transparent modulation output as Tiers 1 and 2.
// ============================================================

[[ stitchable ]] half4 washiSimulated(
    float2 position,
    half4 color,           // RGBA: R=density, G=orientation from rendered Image
    float4 bounds,
    float fiberVisibility,
    float tiltBoost,       // max additional visibility from tilt
    float tiltIntensity,   // current tilt magnitude [0..1]
    float tiltAngle,       // current tilt direction [0..2pi]
    float tiltShadowBias,  // 0.0 = highlights only, 1.0 = shadows only
    float surface,
    float warmth,
    float seed
) {
    float2 size = bounds.zw;
    float2 uv = position / size;

    float density = float(color.r);
    float fiberAngle = float(color.g) * 3.14159;  // [0..1] -> [0..pi]

    // Directional tilt response: fibers most visible when light
    // rakes across them perpendicularly.
    float angleDiff = tiltAngle - fiberAngle;
    float perpendicularity = (1.0 - cos(2.0 * angleDiff)) / 2.0;
    float directionalBoost = tiltBoost * tiltIntensity * perpendicularity;

    // Asymmetric boost: shadow bias routes tilt energy to the visible channel
    float shadowBoost = directionalBoost * tiltShadowBias;
    float highlightBoost = directionalBoost * (1.0 - tiltShadowBias);
    float darkVisibility = fiberVisibility + shadowBoost;
    float brightVisibility = fiberVisibility + highlightBoost;

    // Fine surface texture (micro-roughness in fiber gaps)
    float surfaceNoise = snoise(uv * 150.0 + seed + 300.0);
    density += surfaceNoise * surface * 0.08;
    density = saturate(density);

    // Output: semi-transparent modulation (premultiplied alpha)
    float modulation;
    if (density > 0.5) {
        modulation = (density - 0.5) * darkVisibility * 2.0;
    } else {
        modulation = -((0.5 - density) * brightVisibility * 2.0);
    }
    float alpha = abs(modulation);

    half3 modColor;
    if (modulation > 0.0) {
        modColor = half3(0.0);  // darken
    } else {
        modColor = half3(half(alpha));  // brighten (premultiplied)
    }

    if (warmth > 0.0 && modulation > 0.0) {
        float warmFactor = modulation * warmth;
        modColor.r += half(warmFactor * 0.015);
        modColor.g += half(warmFactor * 0.008);
    }

    return half4(modColor, half(alpha));
}
