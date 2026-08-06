# Washi

Procedural washi paper for SwiftUI.

Washi is a material, not a texture. `WashiMaterial` grows each sheet from a
three-pass nagashizuki simulation — kakemizu, chōshi, sutemizu — depositing
individual fibers with curvature, taper, and flow alignment, then caching the
result as a density/orientation map that a Metal shader lights directionally
from device tilt. Turn the phone and the light rakes across the grain.

Three weights (`.thin`, `.standard`, `.thick`) sit on the system blur
materials, and an `identity` parameter gives every surface its own
deterministic sheet — the same string yields the same paper across launches,
a different string yields paper that never repeats it.

```swift
import WashiMaterial

CardView()
    .washiMaterial(.standard, identity: "photoMetadataCard")
```

Built at Moon for [Untitled](https://github.com/angelsbrood/untitled-ig),
whose photograph metadata cards sit on it.

## The package

Swift Package at the repo root; product `WashiMaterial`; iOS 26+ /
macOS 26+; no dependencies.

```swift
.package(url: "https://github.com/angelsbrood/Washi", branch: "main")
```

**The shader lives in your app target, not in the package.** SwiftUI's
`ShaderLibrary` resolves `[[ stitchable ]]` functions from the main bundle,
and Swift packages can't contribute to it — so `WashiMaterial` calls
`ShaderLibrary.washiSimulated(...)` and expects your app to supply it. Copy
`WashiExplorer/WashiExplorer/Washi.metal` into your own target; only
`washiSimulated` is required, the rest drive the explorer's other tiers.
Without it the material fails to resolve the shader at runtime.

Sheets are tileable and need not be square. `WashiSheet.create(weight:
identity:tileSize:displayScale:)` takes an explicit tile size for surfaces
long enough that a 1024² tile would visibly recur, and
`washiMaterial(_:offset:scale:)` grows the fibers on screen alongside the
content in front of them.

## The explorer

`WashiExplorer/` is where the material is tuned — an app in its own right
(iOS 26+ / macOS 26+), and the reason the parameters are what they are.

Four rendering tiers — noise, scattered, simulated, scanned — run against
three weights in a live grid, with parameter sliders for fiber length and
fineness, formation layers and alignment, kumo intensity and scale, surface,
and warmth. Five presets (Kozo, Gampi, Mitsumata, Unryu, Lace) anchor the
space. A scan processor extracts fiber structure from photographs of real
paper so a scanned sheet can be compared against a simulated one, and a 3D
exploded view pulls the material apart into its compositing layers — blur,
density, shader modulation, result.

Parameters tuned here are baked into the package's `WashiWeight` cases; the
Kozo preset is the production Standard weight.

Open `WashiExplorer/WashiExplorer.xcodeproj` and run.

## License

MIT — see [LICENSE](LICENSE).
