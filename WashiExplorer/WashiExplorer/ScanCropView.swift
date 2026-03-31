import SwiftUI

struct ScanCropView: View {
    let image: CGImage
    let onCrop: (CGImage) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var offset: CGSize = .zero
    @State private var dragBase: CGSize = .zero
    @State private var zoom: CGFloat = 1.0
    @State private var zoomBase: CGFloat = 1.0

    // Cached from GeometryReader for toolbar action
    @State private var cropSide: CGFloat = 200
    @State private var fillScale: CGFloat = 1.0

    private var imageWidth: CGFloat { CGFloat(image.width) }
    private var imageHeight: CGFloat { CGFloat(image.height) }

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let side = min(geo.size.width, geo.size.height) * 0.8
                let fill = max(side / imageWidth, side / imageHeight)

                ZStack {
                    Color.black.ignoresSafeArea()

                    Image(decorative: image, scale: 1.0)
                        .resizable()
                        .interpolation(.high)
                        .frame(
                            width: imageWidth * fill * zoom,
                            height: imageHeight * fill * zoom
                        )
                        .offset(offset)

                    CropMaskShape(cropSide: side)
                        .fill(.black.opacity(0.55), style: FillStyle(eoFill: true))
                        .allowsHitTesting(false)

                    RoundedRectangle(cornerRadius: 2)
                        .strokeBorder(.white.opacity(0.5), lineWidth: 1)
                        .frame(width: side, height: side)
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            offset = CGSize(
                                width: dragBase.width + value.translation.width,
                                height: dragBase.height + value.translation.height
                            )
                        }
                        .onEnded { _ in
                            let clamped = clampedOffset()
                            withAnimation(.spring(duration: 0.3, bounce: 0.1)) {
                                offset = clamped
                            }
                            dragBase = clamped
                        }
                )
                .simultaneousGesture(
                    MagnifyGesture()
                        .onChanged { value in
                            zoom = max(1.0, zoomBase * value.magnification)
                        }
                        .onEnded { value in
                            zoom = max(1.0, zoomBase * value.magnification)
                            zoomBase = zoom
                            let clamped = clampedOffset()
                            withAnimation(.spring(duration: 0.3, bounce: 0.1)) {
                                offset = clamped
                            }
                            dragBase = clamped
                        }
                )
                .onAppear {
                    cropSide = side
                    fillScale = fill
                }
                .onChange(of: geo.size) { _, newSize in
                    cropSide = min(newSize.width, newSize.height) * 0.8
                    fillScale = max(cropSide / imageWidth, cropSide / imageHeight)
                }
            }
            .navigationTitle("Sample Region")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        if let cropped = performCrop() {
                            onCrop(cropped)
                        }
                        dismiss()
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        #if os(macOS)
        .frame(minWidth: 600, minHeight: 500)
        #endif
    }

    private func clampedOffset() -> CGSize {
        let displayW = imageWidth * fillScale * zoom
        let displayH = imageHeight * fillScale * zoom
        let maxX = max(0, (displayW - cropSide) / 2)
        let maxY = max(0, (displayH - cropSide) / 2)
        return CGSize(
            width: min(maxX, max(-maxX, offset.width)),
            height: min(maxY, max(-maxY, offset.height))
        )
    }

    private func performCrop() -> CGImage? {
        let totalScale = fillScale * zoom
        let cropCenterX = imageWidth / 2 - offset.width / totalScale
        let cropCenterY = imageHeight / 2 - offset.height / totalScale
        let sideInPixels = cropSide / totalScale

        let rect = CGRect(
            x: cropCenterX - sideInPixels / 2,
            y: cropCenterY - sideInPixels / 2,
            width: sideInPixels,
            height: sideInPixels
        )

        return image.cropping(to: rect)
    }
}

private struct CropMaskShape: Shape {
    let cropSide: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(rect)
        path.addRect(CGRect(
            x: rect.midX - cropSide / 2,
            y: rect.midY - cropSide / 2,
            width: cropSide,
            height: cropSide
        ))
        return path
    }
}
