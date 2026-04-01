import SwiftUI
import WashiMaterial
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
#if !os(macOS)
import PhotosUI
#endif
import UniformTypeIdentifiers

// MARK: - Explorer Weight

enum ExplorerWeight: String, CaseIterable, Identifiable {
    case thin = "Thin"
    case standard = "Standard"
    case thick = "Thick"

    var id: String { rawValue }

    var systemMaterial: AnyShapeStyle {
        switch self {
        case .thin:     AnyShapeStyle(.ultraThinMaterial)
        case .standard: AnyShapeStyle(.thinMaterial)
        case .thick:    AnyShapeStyle(.regularMaterial)
        }
    }

    // Production simulation param offsets relative to Standard
    // (from WashiWeight in WashiMaterial.swift)
    var fiberLengthOffset: Float {
        switch self { case .thin: -0.05; case .standard: 0; case .thick: 0.05 }
    }
    var fiberFinenessOffset: Float {
        switch self { case .thin: 0.10; case .standard: 0; case .thick: -0.10 }
    }
    var formationAlignmentOffset: Float {
        switch self { case .thin: -0.03; case .standard: 0; case .thick: 0.02 }
    }
    var kumoOffset: Float {
        switch self { case .thin: -0.10; case .standard: 0; case .thick: 0.10 }
    }
    var kumoScaleOffset: Float {
        switch self { case .thin: 0.05; case .standard: 0; case .thick: 0.0 }
    }

    /// Fiber count ratio relative to Standard (production: thin=600, standard=1000, thick=1500).
    var fiberCountRatio: Float {
        switch self { case .thin: 0.6; case .standard: 1.0; case .thick: 1.5 }
    }

    /// Fiber visibility ratio relative to standard base (0.50).
    func fiberVisibilityRatio(for colorScheme: ColorScheme) -> Float {
        switch self {
        case .thin:     0.06
        case .standard: 0.10
        case .thick:    0.16
        }
    }

    /// Surface texture ratio relative to Standard (production: 0.08, 0.12, 0.18).
    var surfaceRatio: Float {
        switch self { case .thin: 0.667; case .standard: 1.0; case .thick: 1.5 }
    }

    /// Cream tint opacity ratio (production light: 0.16, 0.30, 0.44).
    var creamRatio: Double {
        switch self { case .thin: 0.533; case .standard: 1.0; case .thick: 1.467 }
    }

    #if os(iOS)
    var uiBlurStyle: UIBlurEffect.Style {
        switch self {
        case .thin:     .systemUltraThinMaterial
        case .standard: .systemThinMaterial
        case .thick:    .systemMaterial
        }
    }
    #elseif os(macOS)
    var nsBlurMaterial: NSVisualEffectView.Material {
        switch self {
        case .thin:     .hudWindow
        case .standard: .popover
        case .thick:    .menu
        }
    }
    #endif
}

// MARK: - Presets

struct WashiPreset: Identifiable, Equatable, Codable {
    let id: String
    var name: String
    let fiberLength: Float
    let fiberFineness: Float
    let fiberVisibility: Float
    let formationLayers: Float
    let formationAlignment: Float
    let kumo: Float
    let kumoScale: Float
    let surface: Float
    let warmth: Float
    var isBuiltin: Bool = true
}

extension WashiPreset {
    // Kozo: production Standard values from WashiWeight in WashiMaterial.swift.
    // fiberVisibility is the standard-light base; per-weight/scheme scaling handles the rest.
    // formationLayers 0.4118 → fiberCount = Int(1500 + 6500 * 0.4118) = 4177.
    static let kozo = WashiPreset(
        id: "kozo", name: "Kozo",
        fiberLength: 0.60, fiberFineness: 0.55, fiberVisibility: 0.50,
        formationLayers: 0.4118, formationAlignment: 0.28,
        kumo: 0.25, kumoScale: 0.40, surface: 0.12, warmth: 0.0
    )
    static let gampi = WashiPreset(
        id: "gampi", name: "Gampi",
        fiberLength: 0.40, fiberFineness: 0.80, fiberVisibility: 0.25,
        formationLayers: 0.60, formationAlignment: 0.50,
        kumo: 0.15, kumoScale: 0.50, surface: 0.25, warmth: 0.20
    )
    static let mitsumata = WashiPreset(
        id: "mitsumata", name: "Mitsumata",
        fiberLength: 0.50, fiberFineness: 0.65, fiberVisibility: 0.30,
        formationLayers: 0.70, formationAlignment: 0.60,
        kumo: 0.10, kumoScale: 0.30, surface: 0.20, warmth: 0.35
    )
    static let unryu = WashiPreset(
        id: "unryu", name: "Unryu",
        fiberLength: 0.95, fiberFineness: 0.30, fiberVisibility: 0.70,
        formationLayers: 1.00, formationAlignment: 0.15,
        kumo: 0.35, kumoScale: 0.50, surface: 0.10, warmth: 0.40
    )
    static let lace = WashiPreset(
        id: "lace", name: "Lace",
        fiberLength: 0.85, fiberFineness: 0.45, fiberVisibility: 0.80,
        formationLayers: 0.50, formationAlignment: 0.20,
        kumo: 0.60, kumoScale: 0.60, surface: 0.05, warmth: 0.30
    )

    static let all: [WashiPreset] = [.kozo, .gampi, .mitsumata, .unryu, .lace]
}

// MARK: - Washi Tier

enum WashiTier: String, CaseIterable {
    case simulated = "Simulated"
    case scanned = "Scanned"
    case scattered = "Scattered"
    case noise = "Noise"
}

// MARK: - Background Mode

enum BackgroundMode: String, CaseIterable, Identifiable {
    case gradient = "Tanizaki"
    case muji = "Muji"
    case light = "Light"
    case dark = "Dark"
    case custom = "Custom"

    var id: String { rawValue }
}

// MARK: - Card Values

struct CardValues {
    let fiberLength: Float
    let fiberFineness: Float
    let fiberVisibility: Float
    let formationLayers: Float
    let formationAlignment: Float
    let kumo: Float
    let kumoScale: Float
    let surface: Float
    let warmth: Float
    let creamTintOpacity: Double
    let systemMaterial: AnyShapeStyle
    #if os(iOS)
    let blurStyle: UIBlurEffect.Style
    #elseif os(macOS)
    let blurStyle: NSVisualEffectView.Material
    #endif
}

// MARK: - Content View

struct ContentView: View {

    @Environment(\.colorScheme) private var colorScheme

    // MARK: Washi parameters (initialized to Kozo production values)

    @State private var fiberLength: Float = WashiPreset.kozo.fiberLength
    @State private var fiberFineness: Float = WashiPreset.kozo.fiberFineness
    @State private var fiberVisibility: Float = WashiPreset.kozo.fiberVisibility
    @State private var formationLayers: Float = WashiPreset.kozo.formationLayers
    @State private var formationAlignment: Float = WashiPreset.kozo.formationAlignment
    @State private var kumo: Float = WashiPreset.kozo.kumo
    @State private var kumoScale: Float = WashiPreset.kozo.kumoScale
    @State private var surface: Float = WashiPreset.kozo.surface
    @State private var warmth: Float = WashiPreset.kozo.warmth

    // Cream tint (default = production standard-light warmTintOpacity)
    @State private var creamOpacity: Float = 0.10

    @State private var activePreset: WashiPreset = .kozo
    @State private var customPresets: [WashiPreset] = {
        guard let data = UserDefaults.standard.data(forKey: "customPresets"),
              let presets = try? JSONDecoder().decode([WashiPreset].self, from: data)
        else { return [] }
        return presets
    }()
    @State private var editingPresetID: String?
    @FocusState private var editingFieldFocused: Bool
    @State private var backgroundMode: BackgroundMode = .gradient
    @State private var showDebug = false
    @State private var previewScheme: ColorScheme = .dark
    @State private var didApplySystemScheme = false

    // Three density maps for Simulated row (one per weight)
    @State private var densityImageThin: CGImage?
    @State private var densityImageStandard: CGImage?
    @State private var densityImageThick: CGImage?
    @State private var isGenerating = false
    @State private var presetDensityCache: [String: CGImage] = [:]

    // Custom background
    @State private var backgroundImage: CGImage?
    #if os(macOS)
    enum FileImportTarget { case scan, background }
    @State private var fileImportTarget: FileImportTarget = .scan
    @State private var showingFileImporter = false
    #else
    @State private var showingBackgroundPicker = false
    @State private var backgroundPickerItem: PhotosPickerItem?
    #endif

    // Tier 4: Scanned Washi
    #if !os(macOS)
    @State private var showingScanPicker = false
    @State private var scanPickerItem: PhotosPickerItem?
    #endif
    @State private var scanSourceImage: CGImage?
    @State private var scanDensityImage: CGImage?
    @State private var scanBlurRadius: Float = 50.0
    @State private var scanContrast: Float = 2.0
    @State private var isScanProcessing = false
    @State private var scanLoadGeneration: Int = 0
    @State private var pendingScanImage: CGImage?
    @State private var showingScanCrop = false

    private let seed: Float = 42.0
    private let motionManager = WashiMotionManager.shared

    // Custom preset reordering
    @State private var reorderingPresetID: String?
    @State private var reorderDragOffset: CGFloat = 0

    // 3D exploded view
    @State private var expandedCard: (tier: WashiTier, weight: ExplorerWeight)?
    @State private var expandedGeneration = 0
    @State private var isCardFocused = false
    @Namespace private var cardTransition

    // MARK: Density generation trigger

    private struct DensityParams: Equatable, Sendable {
        var fiberLength: Float
        var fiberFineness: Float
        var formationLayers: Float
        var formationAlignment: Float
        var kumo: Float
        var kumoScale: Float
    }

    private var densityParams: DensityParams {
        DensityParams(
            fiberLength: fiberLength,
            fiberFineness: fiberFineness,
            formationLayers: formationLayers,
            formationAlignment: formationAlignment,
            kumo: kumo,
            kumoScale: kumoScale
        )
    }

    private struct ScanProcessingParams: Equatable, Sendable {
        var generation: Int
        var blurRadius: Float
        var contrast: Float
    }

    private var scanProcessingParams: ScanProcessingParams? {
        guard scanSourceImage != nil else { return nil }
        return ScanProcessingParams(
            generation: scanLoadGeneration,
            blurRadius: scanBlurRadius,
            contrast: scanContrast
        )
    }

    // MARK: Per-weight derivation

    private func cardValues(for weight: ExplorerWeight) -> CardValues {
        let stdCount = 1500.0 + 6500.0 * formationLayers
        let weightCount = max(stdCount * weight.fiberCountRatio, 1500)
        let weightFL = clamp01((weightCount - 1500) / 6500)

        #if os(iOS)
        let platformBlurStyle = weight.uiBlurStyle
        #else
        let platformBlurStyle = weight.nsBlurMaterial
        #endif

        return CardValues(
            fiberLength: clamp01(fiberLength + weight.fiberLengthOffset),
            fiberFineness: clamp01(fiberFineness + weight.fiberFinenessOffset),
            fiberVisibility: clamp01(fiberVisibility * weight.fiberVisibilityRatio(for: previewScheme)),
            formationLayers: weightFL,
            formationAlignment: clamp01(formationAlignment + weight.formationAlignmentOffset),
            kumo: clamp01(kumo + weight.kumoOffset),
            kumoScale: clamp01(kumoScale + weight.kumoScaleOffset),
            surface: clamp01(surface * weight.surfaceRatio),
            warmth: warmth,
            creamTintOpacity: Double(creamOpacity) * weight.creamRatio
                * (previewScheme == .dark ? 0.5 : 1.0),
            systemMaterial: weight.systemMaterial,
            blurStyle: platformBlurStyle
        )
    }

    /// Shader args for Noise / Scattered tiers (10 float params + bounds).
    private func noiseShaderArgs(for cv: CardValues) -> [Shader.Argument] {
        [.boundingRect,
         .float(cv.fiberLength), .float(cv.fiberFineness), .float(cv.fiberVisibility),
         .float(cv.formationLayers), .float(cv.formationAlignment),
         .float(cv.kumo), .float(cv.kumoScale),
         .float(cv.surface), .float(cv.warmth), .float(seed)]
    }

    /// Debug shader args: max visibility, no surface/warmth — shows raw density.
    private func debugNoiseShaderArgs(for cv: CardValues) -> [Shader.Argument] {
        [.boundingRect,
         .float(cv.fiberLength), .float(cv.fiberFineness), .float(1.0),
         .float(cv.formationLayers), .float(cv.formationAlignment),
         .float(cv.kumo), .float(cv.kumoScale),
         .float(0), .float(0), .float(seed)]
    }

    /// Shader args for Simulated / Scanned tiers (8 float params + bounds).
    private func simulatedShaderArgs(for cv: CardValues) -> [Shader.Argument] {
        [.boundingRect, .float(cv.fiberVisibility),
         .float(0.06),
         .float(motionManager.tiltIntensity), .float(motionManager.tiltAngle),
         .float(previewScheme == .dark ? 0.0 : 1.0),
         .float(cv.surface), .float(cv.warmth), .float(seed)]
    }

    private func densityImage(for weight: ExplorerWeight) -> CGImage? {
        switch weight {
        case .thin: densityImageThin
        case .standard: densityImageStandard
        case .thick: densityImageThick
        }
    }

    // MARK: - Body

    var body: some View {
        Group {
            #if os(macOS)
            NavigationSplitView {
                controlsPanel
                    .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 340)
            } detail: {
                previewPanel
                    .environment(\.colorScheme, previewScheme)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            #else
            NavigationStack {
                VStack(spacing: 0) {
                    previewPanel
                        .environment(\.colorScheme, previewScheme)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    controlsPanel
                }
                .ignoresSafeArea(edges: .top)
            }
            #endif
        }
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Menu {
                    Button {
                        backgroundMode = .gradient
                    } label: {
                        Label("Tanizaki", systemImage: "paintpalette")
                    }
                    Button {
                        backgroundMode = .muji
                    } label: {
                        Label("Muji", systemImage: "leaf")
                    }
                    Button {
                        backgroundMode = .light
                    } label: {
                        Label("White", systemImage: "square.filled.on.square")
                    }
                    Button {
                        backgroundMode = .dark
                    } label: {
                        Label("Black", systemImage: "square.fill")
                    }
                    Button {
                        backgroundMode = .custom
                        triggerBackgroundPicker()
                    } label: {
                        Label("Photo", systemImage: "photo")
                    }
                } label: {
                    Image(systemName: backgroundIcon)
                }
                .help("Background")

                Button {
                    previewScheme = previewScheme == .dark ? .light : .dark
                } label: {
                    Image(systemName: previewScheme == .dark
                          ? "moon.fill" : "sun.max.fill")
                }
                .help("Toggle light/dark preview")

                Button {
                    showDebug.toggle()
                } label: {
                    Image(systemName: showDebug ? "eye.fill" : "eye")
                }
                .help("Toggle debug view")
                .disabled(expandedCard != nil && !isCardFocused)
            }
        }
        .onChange(of: customPresets) {
            if let data = try? JSONEncoder().encode(customPresets) {
                UserDefaults.standard.set(data, forKey: "customPresets")
            }
        }
        // Triple density map generation (all 3 weights on every param change)
        .task(id: densityParams) {
            if let cached = cachedPresetImages() {
                densityImageThin = cached.thin
                densityImageStandard = cached.standard
                densityImageThick = cached.thick
                return
            }

            if densityImageStandard != nil {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
            }
            withAnimation(.easeIn(duration: 0.25)) { isGenerating = true }

            let thinP = simulationParams(for: .thin)
            let stdP = simulationParams(for: .standard)
            let thickP = simulationParams(for: .thick)

            async let thinImg = Task.detached { FiberSimulator.generate(params: thinP) }.value
            async let stdImg = Task.detached { FiberSimulator.generate(params: stdP) }.value
            async let thickImg = Task.detached { FiberSimulator.generate(params: thickP) }.value

            let (t, s, k) = await (thinImg, stdImg, thickImg)
            guard !Task.isCancelled else { return }

            densityImageThin = t
            densityImageStandard = s
            densityImageThick = k
            withAnimation(.easeOut(duration: 0.3)) { isGenerating = false }
        }
        // Preset cache (generate all weights for built-in presets on launch)
        .task {
            await generatePresetCache()
        }
        // Platform-specific pickers
        #if os(macOS)
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [.image]
        ) { result in
            if case .success(let url) = result {
                switch fileImportTarget {
                case .scan: loadScanFromURL(url)
                case .background: loadBackgroundFromURL(url)
                }
            }
        }
        #else
        .photosPicker(isPresented: $showingScanPicker, selection: $scanPickerItem, matching: .images)
        .onChange(of: scanPickerItem) { _, newItem in
            guard let newItem else { return }
            Task { await loadImageFromPickerItem(newItem, target: .scan) }
        }
        .photosPicker(isPresented: $showingBackgroundPicker, selection: $backgroundPickerItem, matching: .images)
        .onChange(of: backgroundPickerItem) { _, newItem in
            guard let newItem else { return }
            Task { await loadImageFromPickerItem(newItem, target: .background) }
        }
        #endif
        .sheet(isPresented: $showingScanCrop) {
            if let image = pendingScanImage {
                ScanCropView(image: image) { cropped in
                    scanSourceImage = cropped
                    scanLoadGeneration += 1
                }
            }
        }
        // Scan processing
        .task(id: scanProcessingParams) {
            guard let params = scanProcessingParams, let sourceImage = scanSourceImage else { return }
            if scanDensityImage != nil {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
            }
            withAnimation(.easeIn(duration: 0.25)) { isScanProcessing = true }
            let radius = params.blurRadius
            let contrast = params.contrast
            let image = await Task.detached {
                WashiScanProcessor.extractStructure(
                    from: sourceImage,
                    blurRadius: radius,
                    contrast: contrast
                )
            }.value
            guard !Task.isCancelled else { return }
            scanDensityImage = image
            withAnimation(.easeOut(duration: 0.3)) { isScanProcessing = false }
        }
    }

    // MARK: - Preview Panel

    @ViewBuilder
    private var previewPanel: some View {
        ZStack {
            backgroundView

            VStack(spacing: 8) {
                gridHeaderRow
                ForEach(WashiTier.allCases, id: \.self) { tier in
                    gridRow(tier)
                }
            }
            .padding()
            .opacity(expandedCard == nil ? 1.0 : 0.0)
            .animation(.easeOut(duration: 0.3), value: expandedCard == nil)

            if let expanded = expandedCard {
                explodedOverlay(tier: expanded.tier, weight: expanded.weight)
                    .id(expandedGeneration)
            }
        }
        .onAppear {
            motionManager.start()
            if !didApplySystemScheme {
                didApplySystemScheme = true
                previewScheme = colorScheme
                backgroundMode = colorScheme == .dark ? .gradient : .muji
            }
        }
        .onDisappear { motionManager.stop() }
    }

    @ViewBuilder
    private func explodedOverlay(tier: WashiTier, weight: ExplorerWeight) -> some View {
        let cv = cardValues(for: weight)

        ExplodedMaterialView(
            tier: tier,
            colorScheme: previewScheme,
            cardValues: cv,
            densityImage: tier == .simulated ? densityImage(for: weight) : nil,
            scanDensityImage: tier == .scanned ? scanDensityImage : nil,
            seed: seed,
            showDebug: showDebug,
            isGenerating: isGenerating,
            startFocused: true,
            transitionNamespace: cardTransition,
            transitionID: "\(tier.rawValue)-\(weight.rawValue)",
            onFocusChange: { focused in
                isCardFocused = focused
            },
            onDismiss: {
                isCardFocused = false
                withAnimation(.spring(duration: 0.5, bounce: 0.12)) {
                    expandedCard = nil
                }
            }
        )
    }

    private var gridHeaderRow: some View {
        HStack(spacing: 8) {
            Text("")
                .frame(width: 56)
            ForEach(ExplorerWeight.allCases) { weight in
                Text(weight.rawValue)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private func gridRow(_ tier: WashiTier) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Text(tier.rawValue)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 56, alignment: .center)

            if tier == .scanned && scanDensityImage == nil {
                scannedPlaceholderCard
            } else {
                ForEach(ExplorerWeight.allCases) { weight in
                    weightedTierCard(tier: tier, weight: weight)
                }
            }
        }
    }

    private var scannedPlaceholderCard: some View {
        let cv = cardValues(for: .standard)
        return Color.clear
            .background { Rectangle().fill(cv.systemMaterial) }
            .overlay {
                if isScanProcessing {
                    ProgressView()
                } else {
                    VStack(spacing: 4) {
                        Image(systemName: "camera")
                            .font(.title3)
                        Text("Load Scan")
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary.opacity(0.5))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .onTapGesture { triggerScanPicker() }
            .contextMenu {
                Button {
                    triggerScanPicker()
                } label: {
                    Label("Load Scan...", systemImage: "photo.on.rectangle")
                }
            }
    }

    // MARK: Background

    @ViewBuilder
    private var backgroundView: some View {
        switch backgroundMode {
        case .gradient:
            LinearGradient(
                colors: [
                    Color(red: 0.12, green: 0.13, blue: 0.18),
                    Color(red: 0.35, green: 0.30, blue: 0.28),
                    Color(red: 0.85, green: 0.75, blue: 0.65)
                ],
                startPoint: .bottomLeading,
                endPoint: .topTrailing
            )
        case .muji:
            LinearGradient(
                colors: [
                    Color(red: 0.55, green: 0.68, blue: 0.80),
                    Color(red: 0.82, green: 0.82, blue: 0.80),
                    Color(red: 0.78, green: 0.73, blue: 0.66)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        case .light:
            Color.white
        case .dark:
            Color.black
        case .custom:
            if let backgroundImage {
                Image(decorative: backgroundImage, scale: 1.0)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Color.gray.opacity(0.3)
            }
        }
    }

    // MARK: - Tier Cards

    @ViewBuilder
    private func weightedTierCard(tier: WashiTier, weight: ExplorerWeight) -> some View {
        let cv = cardValues(for: weight)

        Group {
            switch tier {
            case .noise:
                noiseCard(cv: cv)
            case .scattered:
                scatteredCard(cv: cv)
            case .simulated:
                simulatedCard(weight: weight, cv: cv)
            case .scanned:
                scannedCard(cv: cv)
            }
        }
        .matchedGeometryEffect(id: "\(tier.rawValue)-\(weight.rawValue)", in: cardTransition)
        .onTapGesture {
            expandedGeneration += 1
            withAnimation(.spring(duration: 0.5, bounce: 0.12)) {
                expandedCard = (tier: tier, weight: weight)
            }
        }
    }

    @ViewBuilder
    private func noiseCard(cv: CardValues) -> some View {
        let args = showDebug ? debugNoiseShaderArgs(for: cv) : noiseShaderArgs(for: cv)

        Color.clear
            .background { Rectangle().fill(cv.systemMaterial) }
            .overlay {
                Color(red: 0.94, green: 0.92, blue: 0.89)
                    .opacity(showDebug ? 0 : cv.creamTintOpacity)
                    .allowsHitTesting(false)
            }
            .overlay {
                Color.white
                    .colorEffect(Shader(function: ShaderLibrary.default.washi, arguments: args))
                    .allowsHitTesting(false)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func scatteredCard(cv: CardValues) -> some View {
        let args = showDebug ? debugNoiseShaderArgs(for: cv) : noiseShaderArgs(for: cv)

        Color.clear
            .background { Rectangle().fill(cv.systemMaterial) }
            .overlay {
                Color(red: 0.94, green: 0.92, blue: 0.89)
                    .opacity(showDebug ? 0 : cv.creamTintOpacity)
                    .allowsHitTesting(false)
            }
            .overlay {
                Color.white
                    .colorEffect(Shader(function: ShaderLibrary.default.washiScattered, arguments: args))
                    .allowsHitTesting(false)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func simulatedCard(weight: ExplorerWeight, cv: CardValues) -> some View {
        let image = densityImage(for: weight)
        let args = simulatedShaderArgs(for: cv)

        if let cgImage = image {
            ZStack {
                // Normal material stack
                Color.clear
                    .background { Rectangle().fill(cv.systemMaterial) }
                    .overlay {
                        Color(red: 0.94, green: 0.92, blue: 0.89)
                            .opacity(cv.creamTintOpacity)
                            .allowsHitTesting(false)
                    }
                    .overlay {
                        Image(decorative: cgImage, scale: 1.0)
                            .resizable()
                            .interpolation(.high)
                            .colorEffect(Shader(
                                function: ShaderLibrary.default.washiSimulated,
                                arguments: args
                            ))
                            .allowsHitTesting(false)
                    }
                    .opacity(showDebug ? 0 : 1)

                // Debug amber density
                Image(decorative: cgImage, scale: 1.0)
                    .resizable()
                    .interpolation(.high)
                    .colorEffect(ShaderLibrary.default.amberDensity())
                    .opacity(showDebug ? 1 : 0)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay { generatingOverlay }
        } else {
            Color.clear
                .background { Rectangle().fill(cv.systemMaterial) }
                .overlay {
                    if isGenerating {
                        ProgressView()
                    } else {
                        VStack(spacing: 4) {
                            Image(systemName: "sparkles")
                                .font(.title3)
                            Text("Simulated")
                                .font(.caption)
                        }
                        .foregroundStyle(.secondary.opacity(0.5))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    @ViewBuilder
    private func scannedCard(cv: CardValues) -> some View {
        let args = simulatedShaderArgs(for: cv)

        Group {
            if let cgImage = scanDensityImage {
                ZStack {
                    // Normal material stack
                    Color.clear
                        .background { Rectangle().fill(cv.systemMaterial) }
                        .overlay {
                            Color(red: 0.94, green: 0.92, blue: 0.89)
                                .opacity(cv.creamTintOpacity)
                                .allowsHitTesting(false)
                        }
                        .overlay {
                            Image(decorative: cgImage, scale: 1.0)
                                .resizable()
                                .interpolation(.high)
                                .aspectRatio(contentMode: .fill)
                                .colorEffect(Shader(
                                    function: ShaderLibrary.default.washiSimulated,
                                    arguments: args
                                ))
                                .allowsHitTesting(false)
                        }
                        .opacity(showDebug ? 0 : 1)

                    // Debug amber density
                    Image(decorative: cgImage, scale: 1.0)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fill)
                        .colorEffect(ShaderLibrary.default.amberDensity())
                        .opacity(showDebug ? 1 : 0)
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay { scanProcessingOverlay }
            } else {
                Color.clear
                    .background { Rectangle().fill(cv.systemMaterial) }
                    .overlay {
                        if isScanProcessing {
                            ProgressView()
                        } else {
                            VStack(spacing: 4) {
                                Image(systemName: "camera")
                                    .font(.title3)
                                Text("Scanned")
                                    .font(.caption)
                            }
                            .foregroundStyle(.secondary.opacity(0.5))
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .contextMenu {
            Button {
                triggerScanPicker()
            } label: {
                Label("Load Scan...", systemImage: "photo.on.rectangle")
            }
            if scanSourceImage != nil {
                Button(role: .destructive) {
                    scanSourceImage = nil
                    scanDensityImage = nil
                } label: {
                    Label("Clear Scan", systemImage: "trash")
                }
            }
        }
    }

    // MARK: Overlays

    @ViewBuilder
    private var generatingOverlay: some View {
        if isGenerating {
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .overlay { ProgressView() }
                .transition(.opacity)
        }
    }

    @ViewBuilder
    private var scanProcessingOverlay: some View {
        if isScanProcessing {
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .overlay { ProgressView() }
                .transition(.opacity)
        }
    }

    // MARK: - Controls

    @ViewBuilder
    private var controlsPanel: some View {
        #if os(macOS)
        VStack(spacing: 0) {
            toolbar
                .padding(.horizontal)
                .padding(.top, 12)
                .padding(.bottom, 8)
            Divider()
            parameterSliders
        }
        .onTapGesture {
            if editingPresetID != nil {
                editingPresetID = nil
                editingFieldFocused = false
            }
        }
        #else
        VStack(spacing: 0) {
            toolbar
                .padding(.horizontal)
                .padding(.top, 12)
                .padding(.bottom, 8)
            Divider()
            parameterSliders
                .frame(maxHeight: 320)
        }
        .background(.regularMaterial)
        .onTapGesture {
            if editingPresetID != nil {
                editingPresetID = nil
                editingFieldFocused = false
            }
        }
        #endif
    }

    private var parameterSliders: some View {
        ScrollView {
            VStack(spacing: 16) {
                sliderSection("Fiber") {
                    paramSlider("Length", value: $fiberLength)
                    paramSlider("Fineness", value: $fiberFineness)
                    paramSlider("Visibility", value: $fiberVisibility)
                }
                sliderSection("Formation") {
                    paramSlider("Layers", value: $formationLayers)
                    paramSlider("Alignment", value: $formationAlignment)
                }
                sliderSection("Kumo") {
                    paramSlider("Intensity", value: $kumo)
                    paramSlider("Scale", value: $kumoScale)
                }
                sliderSection("Surface") {
                    paramSlider("Texture", value: $surface)
                }
                sliderSection("Material") {
                    HStack(spacing: 8) {
                        Text("Cream")
                            .font(.caption)
                            .frame(width: 70, alignment: .leading)
                        Slider(value: $creamOpacity, in: 0...0.50)
                        Text(String(format: "%.2f", creamOpacity))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 36, alignment: .trailing)
                    }
                    paramSlider("Warmth", value: $warmth)
                }
                if scanSourceImage != nil {
                    sliderSection("Scan Processing") {
                        HStack(spacing: 8) {
                            Text("Blur Radius")
                                .font(.caption)
                                .frame(width: 70, alignment: .leading)
                            Slider(value: $scanBlurRadius, in: 10...80)
                            Text(String(format: "%.0f", scanBlurRadius))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 36, alignment: .trailing)
                        }
                        HStack(spacing: 8) {
                            Text("Contrast")
                                .font(.caption)
                                .frame(width: 70, alignment: .leading)
                            Slider(value: $scanContrast, in: 1.0...4.0)
                            Text(String(format: "%.1f", scanContrast))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 36, alignment: .trailing)
                        }
                    }
                }
            }
            .padding()
        }
    }

    // MARK: Toolbar (presets + toggles)

    private var toolbar: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(WashiPreset.all) { preset in
                        presetChip(preset)
                    }

                    if !customPresets.isEmpty {
                        Divider()
                            .frame(height: 20)
                            .padding(.horizontal, 2)
                    }

                    ForEach(customPresets) { preset in
                        let isDragging = reorderingPresetID == preset.id
                        presetChip(preset)
                            .offset(x: isDragging ? reorderDragOffset : 0)
                            .scaleEffect(isDragging ? 1.08 : 1.0)
                            .zIndex(isDragging ? 1 : 0)
                            // Non-dragged items spring into new positions on swap;
                            // dragged item has no position animation (tracks finger)
                            .animation(isDragging ? nil : .interactiveSpring, value: customPresets.map(\.id))
                            // Scale animates on drag start/end
                            .animation(.spring(duration: 0.2), value: reorderingPresetID)
                            .simultaneousGesture(
                                LongPressGesture(minimumDuration: 0.3)
                                    .sequenced(before: DragGesture())
                                    .onChanged { value in
                                        switch value {
                                        case .second(true, let drag):
                                            if reorderingPresetID != preset.id {
                                                reorderingPresetID = preset.id
                                            }
                                            if let drag {
                                                reorderDragOffset = drag.translation.width
                                                checkReorderSwap()
                                            }
                                        default:
                                            break
                                        }
                                    }
                                    .onEnded { _ in
                                        withAnimation(.spring(duration: 0.3)) {
                                            reorderingPresetID = nil
                                            reorderDragOffset = 0
                                        }
                                    }
                            )
                    }

                    Button {
                        addCustomPreset()
                    } label: {
                        Image(systemName: "plus")
                            .font(.caption.weight(.semibold))
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(.quaternary))
                            .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var backgroundIcon: String {
        switch backgroundMode {
        case .gradient: "paintpalette"
        case .muji: "leaf"
        case .light: "square.filled.on.square"
        case .dark: "square.fill"
        case .custom: "photo"
        }
    }

    private func presetChip(_ preset: WashiPreset) -> some View {
        let isActive = activePreset.id == preset.id
        let isModified = isActive && !matchesPreset(preset)
        let isEditing = editingPresetID == preset.id

        return Button {
            applyPreset(preset)
        } label: {
            HStack(spacing: 4) {
                Text(preset.name)
                    .font(.caption)
                    .fontWeight(isActive ? .semibold : .regular)
                    .opacity(isEditing ? 0 : 1)
                    .overlay {
                        if isEditing, let idx = customPresets.firstIndex(where: { $0.id == preset.id }) {
                            TextField("Name", text: $customPresets[idx].name)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .textFieldStyle(.plain)
                                .fixedSize()
                                .focused($editingFieldFocused)
                                .onSubmit {
                                    editingPresetID = nil
                                }
                        }
                    }
                if isModified && !isEditing {
                    Circle()
                        .fill(.primary)
                        .frame(width: 4, height: 4)
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 6)
            .foregroundStyle(isActive ? .primary : .secondary)
            .contextMenu(preset.isBuiltin ? nil : ContextMenu {
                Button("Rename") {
                    editingPresetID = preset.id
                    editingFieldFocused = true
                }
                Button("Delete", role: .destructive) {
                    deleteCustomPreset(preset)
                }
            })
        }
    }

    private func checkReorderSwap() {
        guard let dragID = reorderingPresetID,
              let index = customPresets.firstIndex(where: { $0.id == dragID })
        else { return }

        let threshold: CGFloat = 60

        if reorderDragOffset > threshold && index < customPresets.count - 1 {
            reorderDragOffset -= threshold
            customPresets.swapAt(index, index + 1)
        } else if reorderDragOffset < -threshold && index > 0 {
            reorderDragOffset += threshold
            customPresets.swapAt(index, index - 1)
        }
    }

    private func deleteCustomPreset(_ preset: WashiPreset) {
        customPresets.removeAll { $0.id == preset.id }
        if activePreset.id == preset.id {
            applyPreset(.kozo)
        }
    }

    // MARK: Slider helpers

    private func sliderSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            content()
        }
    }

    private func paramSlider(_ label: String, value: Binding<Float>) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .frame(width: 70, alignment: .leading)
            Slider(value: value, in: 0...1)
            Text(String(format: "%.2f", value.wrappedValue))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .trailing)
        }
    }

    // MARK: - Preset Logic

    private func applyPreset(_ preset: WashiPreset) {
        activePreset = preset
        fiberLength = preset.fiberLength
        fiberFineness = preset.fiberFineness
        fiberVisibility = preset.fiberVisibility
        formationLayers = preset.formationLayers
        formationAlignment = preset.formationAlignment
        kumo = preset.kumo
        kumoScale = preset.kumoScale
        surface = preset.surface
        warmth = preset.warmth

        for weight in ExplorerWeight.allCases {
            let key = "\(preset.id)-\(weight.rawValue)"
            if let cached = presetDensityCache[key] {
                setDensityImage(cached, for: weight)
            }
        }
    }

    private func setDensityImage(_ image: CGImage, for weight: ExplorerWeight) {
        switch weight {
        case .thin: densityImageThin = image
        case .standard: densityImageStandard = image
        case .thick: densityImageThick = image
        }
    }

    private func cachedPresetImages() -> (thin: CGImage, standard: CGImage, thick: CGImage)? {
        for preset in WashiPreset.all {
            if preset.fiberLength == fiberLength
                && preset.fiberFineness == fiberFineness
                && preset.formationLayers == formationLayers
                && preset.formationAlignment == formationAlignment
                && preset.kumo == kumo
                && preset.kumoScale == kumoScale
            {
                let thinKey = "\(preset.id)-\(ExplorerWeight.thin.rawValue)"
                let stdKey = "\(preset.id)-\(ExplorerWeight.standard.rawValue)"
                let thickKey = "\(preset.id)-\(ExplorerWeight.thick.rawValue)"

                // Check in-memory cache first
                if let t = presetDensityCache[thinKey],
                   let s = presetDensityCache[stdKey],
                   let k = presetDensityCache[thickKey] {
                    return (t, s, k)
                }

                // Fall back to disk cache (survives rebuilds)
                if let t = FiberSimulator.loadCached(presetID: thinKey),
                   let s = FiberSimulator.loadCached(presetID: stdKey),
                   let k = FiberSimulator.loadCached(presetID: thickKey) {
                    presetDensityCache[thinKey] = t
                    presetDensityCache[stdKey] = s
                    presetDensityCache[thickKey] = k
                    return (t, s, k)
                }
            }
        }
        return nil
    }

    private func addCustomPreset() {
        let preset = WashiPreset(
            id: UUID().uuidString,
            name: "Custom",
            fiberLength: fiberLength,
            fiberFineness: fiberFineness,
            fiberVisibility: fiberVisibility,
            formationLayers: formationLayers,
            formationAlignment: formationAlignment,
            kumo: kumo,
            kumoScale: kumoScale,
            surface: surface,
            warmth: warmth,
            isBuiltin: false
        )
        customPresets.append(preset)
        activePreset = preset
        editingPresetID = preset.id
        editingFieldFocused = true
    }

    private func matchesPreset(_ preset: WashiPreset) -> Bool {
        fiberLength == preset.fiberLength
        && fiberFineness == preset.fiberFineness
        && fiberVisibility == preset.fiberVisibility
        && formationLayers == preset.formationLayers
        && formationAlignment == preset.formationAlignment
        && kumo == preset.kumo
        && kumoScale == preset.kumoScale
        && surface == preset.surface
        && warmth == preset.warmth
    }

    // MARK: - Simulation Params

    /// Compute simulation parameters for a given weight from current slider state.
    private func simulationParams(for weight: ExplorerWeight) -> FiberSimulator.FiberParams {
        let stdCount = 1500.0 + 6500.0 * formationLayers
        let weightCount = max(stdCount * weight.fiberCountRatio, 1500)
        let weightFL = clamp01((weightCount - 1500) / 6500)

        return FiberSimulator.FiberParams(
            fiberLength: clamp01(fiberLength + weight.fiberLengthOffset),
            fiberFineness: clamp01(fiberFineness + weight.fiberFinenessOffset),
            formationLayers: weightFL,
            formationAlignment: clamp01(formationAlignment + weight.formationAlignmentOffset),
            kumo: clamp01(kumo + weight.kumoOffset),
            kumoScale: clamp01(kumoScale + weight.kumoScaleOffset),
            seed: seed
        )
    }

    /// Compute simulation parameters for a preset + weight (for cache generation).
    private static func simulationParams(
        preset: WashiPreset,
        weight: ExplorerWeight,
        seed: Float
    ) -> FiberSimulator.FiberParams {
        let stdCount = 1500.0 + 6500.0 * preset.formationLayers
        let weightCount = max(stdCount * weight.fiberCountRatio, 1500)
        let weightFL = clamp01((weightCount - 1500) / 6500)

        return FiberSimulator.FiberParams(
            fiberLength: clamp01(preset.fiberLength + weight.fiberLengthOffset),
            fiberFineness: clamp01(preset.fiberFineness + weight.fiberFinenessOffset),
            formationLayers: weightFL,
            formationAlignment: clamp01(preset.formationAlignment + weight.formationAlignmentOffset),
            kumo: clamp01(preset.kumo + weight.kumoOffset),
            kumoScale: clamp01(preset.kumoScale + weight.kumoScaleOffset),
            seed: seed
        )
    }

    // MARK: - Preset Cache

    private func generatePresetCache() async {
        for preset in WashiPreset.all {
            guard !Task.isCancelled else { return }
            let id = preset.id

            for weight in ExplorerWeight.allCases {
                guard !Task.isCancelled else { return }
                let key = "\(id)-\(weight.rawValue)"

                let cached: CGImage? = await Task.detached {
                    FiberSimulator.loadCached(presetID: key)
                }.value
                if let cached {
                    presetDensityCache[key] = cached
                    continue
                }

                let params = Self.simulationParams(preset: preset, weight: weight, seed: seed)
                let image = await Task.detached {
                    let img = FiberSimulator.generate(params: params)
                    FiberSimulator.saveToCache(img, presetID: key)
                    return img
                }.value
                presetDensityCache[key] = image
            }
        }
    }

    // MARK: - File / Photo Loaders

    private func triggerScanPicker() {
        #if os(macOS)
        fileImportTarget = .scan
        showingFileImporter = true
        #else
        showingScanPicker = true
        #endif
    }

    private func triggerBackgroundPicker() {
        #if os(macOS)
        fileImportTarget = .background
        showingFileImporter = true
        #else
        showingBackgroundPicker = true
        #endif
    }

    #if !os(macOS)
    private enum PickerTarget { case scan, background }

    private func loadImageFromPickerItem(_ item: PhotosPickerItem, target: PickerTarget) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let provider = CGDataProvider(data: data as CFData),
              let source = CGImageSourceCreateWithDataProvider(provider, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return }

        switch target {
        case .scan:
            pendingScanImage = cgImage
            showingScanCrop = true
        case .background:
            backgroundImage = cgImage
        }
    }
    #endif

    #if os(macOS)
    private func loadScanFromURL(_ url: URL) {
        guard let decoded = loadImageFromURL(url) else { return }
        pendingScanImage = decoded
        showingScanCrop = true
    }

    private func loadBackgroundFromURL(_ url: URL) {
        guard let decoded = loadImageFromURL(url) else { return }
        backgroundImage = decoded
    }

    private func loadImageFromURL(_ url: URL) -> CGImage? {
        guard url.startAccessingSecurityScopedResource() else { return nil }
        defer { url.stopAccessingSecurityScopedResource() }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }

        let w = cgImage.width, h = cgImage.height
        guard let ctx = CGContext(
            data: nil, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
    }
    #endif
}

// MARK: - Utility

private func clamp01(_ value: Float) -> Float {
    min(max(value, 0), 1)
}

#Preview {
    ContentView()
}
