import CoreGraphics
import Foundation

enum WashiScanProcessor {

    /// Extracts the fiber structure from a washi scan by removing the base
    /// paper color via high-pass filtering.
    ///
    /// - Parameters:
    ///   - image: The raw washi scan (any color space)
    ///   - blurRadius: Controls what's considered "structure" vs "base."
    ///     Large (40–80): keeps kumo + fibers, removes only paper color.
    ///     Medium (15–30): removes paper color AND kumo, keeps only fibers.
    ///   - contrast: Amplifies the extracted structure. Higher = more visible
    ///     fiber detail. Range: 1.0 (subtle) to 4.0 (dramatic).
    ///
    /// - Returns: A grayscale CGImage where 0.5 = neutral, >0.5 = fiber-dense,
    ///   <0.5 = translucent gap.
    nonisolated static func extractStructure(
        from image: CGImage,
        blurRadius: Float = 50.0,
        contrast: Float = 2.0
    ) -> CGImage {
        let downscaled = downscale(image, maxDimension: 2048)
        let width = downscaled.width
        let height = downscaled.height
        let count = width * height

        let luminance = toLuminanceBuffer(downscaled)
        let blurred = gaussianBlur(luminance, width: width, height: height, radius: blurRadius)

        // Compute high-pass differences
        var diffs = [Float](repeating: 0.0, count: count)
        for i in 0..<count {
            diffs[i] = (luminance[i] - blurred[i]) * contrast
        }

        // Percentile-based normalization — robust against edge artifacts
        // from blur clamping that would otherwise dominate max-based scaling
        var absSorted = diffs.map { abs($0) }
        absSorted.sort()
        let p98 = absSorted[min(Int(Float(count) * 0.98), count - 1)]
        let ceiling = max(p98, 1e-6)
        let scale: Float = 0.5 / ceiling

        var structure = [Float](repeating: 0.0, count: count)
        for i in 0..<count {
            structure[i] = min(max(diffs[i] * scale + 0.5, 0.0), 1.0)
        }

        return bufferToCGImage(structure, width: width, height: height)
    }

    // MARK: - Helpers

    nonisolated private static func downscale(_ image: CGImage, maxDimension: Int) -> CGImage {
        let w = image.width
        let h = image.height
        guard max(w, h) > maxDimension else { return image }

        let scale = Float(maxDimension) / Float(max(w, h))
        let newW = Int(Float(w) * scale)
        let newH = Int(Float(h) * scale)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: newW,
            height: newH,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return image }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: newW, height: newH))
        return context.makeImage() ?? image
    }

    nonisolated private static func toLuminanceBuffer(_ image: CGImage) -> [Float] {
        let width = image.width
        let height = image.height

        let colorSpace = CGColorSpaceCreateDeviceGray()
        var pixels = [UInt8](repeating: 0, count: width * height)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return pixels.map { Float($0) / 255.0 } }

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return pixels.map { Float($0) / 255.0 }
    }

    /// Approximate Gaussian blur via three-pass separable box blur.
    /// Each pass is O(width*height) using a running sum.
    nonisolated private static func gaussianBlur(
        _ buffer: [Float],
        width: Int,
        height: Int,
        radius: Float
    ) -> [Float] {
        let r = max(1, Int(radius))
        var current = buffer
        for _ in 0..<3 {
            current = boxBlur(current, width: width, height: height, radius: r)
        }
        return current
    }

    nonisolated private static func boxBlur(
        _ buffer: [Float],
        width: Int,
        height: Int,
        radius: Int
    ) -> [Float] {
        let count = width * height
        var temp = [Float](repeating: 0, count: count)
        var output = [Float](repeating: 0, count: count)
        let diameter = 2 * radius + 1
        let invDiameter = 1.0 / Float(diameter)

        // Horizontal pass
        for y in 0..<height {
            let row = y * width
            var sum: Float = 0
            for x in -radius...radius {
                sum += buffer[row + max(0, min(x, width - 1))]
            }
            temp[row] = sum * invDiameter
            for x in 1..<width {
                sum += buffer[row + min(x + radius, width - 1)]
                    - buffer[row + max(x - radius - 1, 0)]
                temp[row + x] = sum * invDiameter
            }
        }

        // Vertical pass
        for x in 0..<width {
            var sum: Float = 0
            for y in -radius...radius {
                sum += temp[max(0, min(y, height - 1)) * width + x]
            }
            output[x] = sum * invDiameter
            for y in 1..<height {
                sum += temp[min(y + radius, height - 1) * width + x]
                    - temp[max(y - radius - 1, 0) * width + x]
                output[y * width + x] = sum * invDiameter
            }
        }

        return output
    }

    nonisolated private static func bufferToCGImage(
        _ buffer: [Float],
        width: Int,
        height: Int
    ) -> CGImage {
        let pixels = Data(buffer.map { UInt8(min(max($0 * 255.0, 0.0), 255.0)) })
        let provider = CGDataProvider(data: pixels as CFData)!
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )!
    }
}
