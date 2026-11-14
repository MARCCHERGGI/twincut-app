import AVFoundation
import CoreGraphics
import ImageIO

/// Turns a photo into a short silent video so photos and clips flow through one engine.
enum StillVideo {
    static let length: Double = 12

    enum Failure: Error { case writer, pixelBuffer }

    /// Decodes image data upright (EXIF orientation applied), at most `maxSide` pixels long,
    /// without ever holding the full-resolution bitmap.
    static func upright(_ data: Data, maxSide: Int = 1920) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxSide,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              image.width >= 2, image.height >= 2 else { return nil }
        return image
    }

    static func write(_ image: CGImage, to url: URL, length: Double = StillVideo.length) async throws {
        let width = image.width / 2 * 2
        let height = image.height / 2 * 2
        try? FileManager.default.removeItem(at: url)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
        ])
        guard writer.canAdd(input) else { throw Failure.writer }
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? Failure.writer }
        writer.startSession(atSourceTime: .zero)

        guard let pool = adaptor.pixelBufferPool else { throw Failure.pixelBuffer }
        var pb: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pb)
        guard let buffer = pb else { throw Failure.pixelBuffer }
        CVPixelBufferLockBaseAddress(buffer, [])
        if let ctx = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) {
            // Transparent pixels in a PNG land on black, not on whatever the buffer held.
            ctx.setFillColor(CGColor(gray: 0, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])

        // One frame a second keeps every second seekable for the composition.
        let frames = Int(length.rounded(.up))
        for second in 0...frames {
            while !input.isReadyForMoreMediaData {
                guard writer.status == .writing else { throw writer.error ?? Failure.writer }
                try await Task.sleep(nanoseconds: 2_000_000)
            }
            let time = CMTime(seconds: min(Double(second), length), preferredTimescale: 600)
            if !adaptor.append(buffer, withPresentationTime: time) { throw writer.error ?? Failure.writer }
            if Double(second) >= length { break }
        }
        input.markAsFinished()
        writer.endSession(atSourceTime: CMTime(seconds: length, preferredTimescale: 600))
        await writer.finishWriting()
        if writer.status != .completed { throw writer.error ?? Failure.writer }
    }
}
