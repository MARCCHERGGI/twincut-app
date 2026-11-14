import AVFoundation
import UIKit
import XCTest
@testable import Reelsy

/// Test media made on the fly, so the repo carries no footage.
enum Synth {
    struct RGB: Equatable {
        var r: UInt8, g: UInt8, b: UInt8
        static let red = RGB(r: 230, g: 30, b: 30)
        static let green = RGB(r: 30, g: 210, b: 60)
        static let blue = RGB(r: 30, g: 50, b: 230)
        static let white = RGB(r: 250, g: 250, b: 250)
        static let black = RGB(r: 8, g: 8, b: 8)
    }

    static func tempURL(_ ext: String = "mp4") -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).\(ext)")
    }

    /// An H.264 video of solid-colour shots that cut at exact frame boundaries.
    static func video(_ shots: [(RGB, Double)], size: CGSize, fps: Int32 = 30) async throws -> URL {
        let url = tempURL()
        let width = Int(size.width), height = Int(size.height)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
        ])
        writer.add(input)
        XCTAssertTrue(writer.startWriting(), "writer: \(String(describing: writer.error))")
        writer.startSession(atSourceTime: .zero)

        var frame: Int64 = 0
        for (color, length) in shots {
            let buffer = try solid(color, width: width, height: height, pool: adaptor.pixelBufferPool)
            let count = Int64((length * Double(fps)).rounded())
            for _ in 0..<count {
                while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 1_000_000) }
                adaptor.append(buffer, withPresentationTime: CMTime(value: frame, timescale: fps))
                frame += 1
            }
        }
        input.markAsFinished()
        writer.endSession(atSourceTime: CMTime(value: frame, timescale: fps))
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
        return url
    }

    private static func solid(_ c: RGB, width: Int, height: Int, pool: CVPixelBufferPool?) throws -> CVPixelBuffer {
        var pb: CVPixelBuffer?
        if let pool { CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pb) }
        guard let buffer = pb else { throw CocoaError(.fileWriteUnknown) }
        CVPixelBufferLockBaseAddress(buffer, [])
        let base = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        for y in 0..<height {
            let row = base + y * stride
            for x in 0..<width {
                row[x * 4] = c.b
                row[x * 4 + 1] = c.g
                row[x * 4 + 2] = c.r
                row[x * 4 + 3] = 255
            }
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        return buffer
    }

    /// Upright frame of a video at `time`, scaled down to `width` px wide, as RGB bytes.
    static func frame(_ url: URL, at time: Double, width: Int, height: Int) async throws -> [UInt8] {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let image = try await generator.image(at: CMTime(seconds: time, preferredTimescale: 600)).image
        return PixelStats.rgb(image, width: width, height: height)
    }

    static func pixel(_ rgb: [UInt8], x: Int, y: Int, width: Int) -> RGB {
        let i = (y * width + x) * 3
        return RGB(r: rgb[i], g: rgb[i + 1], b: rgb[i + 2])
    }

    static func dominant(_ p: RGB) -> String {
        let m = max(p.r, p.g, p.b)
        if p.r == m { return "red" }
        if p.g == m { return "green" }
        return "blue"
    }

    /// Mono clicks on every beat, for the tempo tracker.
    static func clicks(bpm: Double, seconds: Double, sampleRate: Double = Rhythm.sampleRate, offset: Double = 0.1) -> [Float] {
        var s = [Float](repeating: 0, count: Int(seconds * sampleRate))
        let period = 60 / bpm
        var t = offset
        while t < seconds {
            let start = Int(t * sampleRate)
            for k in 0..<Int(0.03 * sampleRate) where start + k < s.count {
                let env = Float(exp(-Double(k) / (0.006 * sampleRate)))
                s[start + k] += env * Float(sin(2 * .pi * 1800 * Double(k) / sampleRate))
            }
            t += period
        }
        return s
    }

    static func template(shots lengths: [Double], beats: [Double] = [], texts: [Template.TextBeat] = []) -> Template {
        var t = 0.0
        let shots = lengths.enumerated().map { i, len -> Template.Shot in
            defer { t += len }
            return Template.Shot(index: i, start: t, end: t + len, color: "#808080", brightness: 0.5, motion: 0.5,
                                 framing: nil, subject: nil, camera: nil, hint: "Shot \(i + 1)")
        }
        let duration = lengths.reduce(0, +)
        return Template(id: UUID().uuidString, title: "Test", source: .init(kind: "test", platform: nil), duration: duration,
                        aspect: .init(width: 1080, height: 1920), pace: .fast, tempo: nil, beats: beats, onBeat: 0,
                        shots: shots, texts: texts, tags: [], labeledBy: nil, createdAt: nil)
    }
}
