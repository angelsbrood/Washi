# washiexplorer

Procedural washi paper for SwiftUI.

`WashiMaterial` renders sheets of Japanese paper — fibers deposited by a
three-pass nagashizuki simulation (kakemizu, chōshi, sutemizu), cached as
density/orientation textures, and lit directionally by device tilt through a
Metal shader. Three weights (`.thin`, `.standard`, `.thick`) map onto the
system blur materials, and an `identity` parameter makes every surface its
own deterministic sheet.

```swift
import WashiMaterial

CardView()
    .washiMaterial(.standard, identity: "photoMetadataCard")
```

Built at Moon for [Untitled](https://github.com/angelsbrood/untitled-ig),
whose metadata cards sit on it.

## The explorer

`WashiExplorer/` is the tuning environment (iOS 26+ / macOS 26+): four
rendering tiers — noise, scattered, simulated, scanned — against three
weights in a live grid, parameter sliders, presets (Kozo, Gampi, Mitsumata,
Unryu, Lace), a scan processor that extracts fiber structure from
photographs of real paper, and a 3D exploded view of the material's
compositing layers. Parameters tuned here are baked into the package's
`WashiWeight` cases.

Open `WashiExplorer/WashiExplorer.xcodeproj` and run.

## The package

Swift Package at the repo root; product `WashiMaterial`; iOS 26+ /
macOS 26+; no dependencies.

```swift
.package(url: "https://github.com/angelsbrood/washiexplorer", branch: "main")
```

**The shader lives in your app target, not in the package.** SwiftUI's
`ShaderLibrary` resolves `[[ stitchable ]]` functions from the main bundle,
and Swift packages can't contribute to it — so `WashiMaterial` calls
`ShaderLibrary.washiSimulated(...)` and expects your app to supply it. Copy
`WashiExplorer/WashiExplorer/Washi.metal` into your own target; only
`washiSimulated` is required, the rest are for the explorer's other tiers.
Without it the material fails to resolve the shader at runtime.

## License

MIT — see [LICENSE](LICENSE).
