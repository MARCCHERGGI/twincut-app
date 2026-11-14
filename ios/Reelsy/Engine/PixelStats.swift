import CoreGraphics

/// Small-image statistics shared by the clip probe and the reference analyzer.
enum PixelStats {
    /// Greyscale pixels of `image` scaled to width x height.
    static func luma(_ image: CGImage, width: Int, height: Int) -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: width * height)
        pixels.withUnsafeMutableBytes { buffer in
            guard let ctx = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return }
            ctx.interpolationQuality = .medium
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return pixels
    }

    /// RGB pixels (3 bytes each) of `image` scaled to width x height.
    static func rgb(_ image: CGImage, width: Int, height: Int) -> [UInt8] {
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        rgba.withUnsafeMutableBytes { buffer in
            guard let ctx = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            ) else { return }
            ctx.interpolationQuality = .medium
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        var out = [UInt8]()
        out.reserveCapacity(width * height * 3)
        for i in stride(from: 0, to: rgba.count, by: 4) {
            out.append(rgba[i])
            out.append(rgba[i + 1])
            out.append(rgba[i + 2])
        }
        return out
    }

    static func meanBrightness(_ luma: [UInt8]) -> Double {
        guard !luma.isEmpty else { return 0 }
        return Double(luma.reduce(0) { $0 + Int($1) }) / Double(luma.count) / 255
    }

    static func meanAbsDiff(_ a: [UInt8], _ b: [UInt8]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var sum = 0
        for i in 0..<a.count { sum += abs(Int(a[i]) - Int(b[i])) }
        return Double(sum) / Double(a.count)
    }

    /// A shot's colour for the edit-DNA strip: saturation-weighted mean hue of a tiny
    /// thumbnail, with lightness and saturation pulled into a range that reads on black.
    /// Same formula as the server analyzer.
    static func swatch(rgb: [UInt8]) -> (hex: String, brightness: Double) {
        var x = 0.0, y = 0.0, wsum = 0.0, light = 0.0, satSum = 0.0, luma = 0.0
        let px = Double(rgb.count / 3)
        guard px > 0 else { return ("#5a5a66", 0.3) }
        for i in stride(from: 0, to: rgb.count, by: 3) {
            let r = Double(rgb[i]) / 255, g = Double(rgb[i + 1]) / 255, b = Double(rgb[i + 2]) / 255
            let mx = max(r, g, b), mn = min(r, g, b)
            let l = (mx + mn) / 2
            let d = mx - mn
            let s = d == 0 ? 0 : d / (1 - abs(2 * l - 1))
            var h = 0.0
            if d > 0 {
                if mx == r { h = 60 * ((g - b) / d).truncatingRemainder(dividingBy: 6) }
                else if mx == g { h = 60 * ((b - r) / d + 2) }
                else { h = 60 * ((r - g) / d + 4) }
            }
            let w = s * (0.25 + l)
            x += cos(h * .pi / 180) * w
            y += sin(h * .pi / 180) * w
            wsum += w
            light += l
            satSum += s
            luma += 0.2126 * r + 0.7152 * g + 0.0722 * b
        }
        let hue = wsum > 0 ? (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360) : 220
        let sat = wsum > 0 ? min(0.85, max(0.35, satSum / px * 1.4)) : 0.08
        let l = min(0.62, max(0.34, light / px + 0.12))
        return (hsl(hue, sat, l), luma / px)
    }

    static func hsl(_ h: Double, _ s: Double, _ l: Double) -> String {
        func f(_ n: Double) -> Double {
            let k = (n + h / 30).truncatingRemainder(dividingBy: 12)
            let a = s * min(l, 1 - l)
            return l - a * max(-1, min(k - 3, min(9 - k, 1)))
        }
        let c = [f(0), f(8), f(4)].map { String(format: "%02x", Int((max(0, min(1, $0)) * 255).rounded())) }
        return "#" + c.joined()
    }
}
