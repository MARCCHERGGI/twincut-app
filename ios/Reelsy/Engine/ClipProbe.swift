import AVFoundation
import Vision

/// Reads what the planner and reframer need from a clip, entirely on the device: length,
/// upright size, how tight the framing is, how much it moves, how bright it is, and the
/// point of interest to keep centred when the clip is cropped to 9:16.
enum ClipProbe {
    enum Failure: LocalizedError {
        case noVideo
        var errorDescription: String? { "This file has no video Twincut can read." }
    }

    static func probe(url: URL, isPhoto: Bool) async throws -> ClipAsset {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw Failure.noVideo }
        // The video track's end, not the asset's: audio often runs a few frames longer.
        let (natural, transform, range) = try await track.load(.naturalSize, .preferredTransform, .timeRange)
        let duration = range.end.seconds
        guard duration.isFinite, duration > 0 else { throw Failure.noVideo }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 480, height: 480)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.1, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.1, preferredTimescale: 600)
        let t1 = min(1.0, duration * 0.3)
        let t2 = min(duration * 0.9, t1 + 0.5)
        let first = try? await generator.image(at: CMTime(seconds: t1, preferredTimescale: 600)).image
        let second = isPhoto ? nil : try? await generator.image(at: CMTime(seconds: t2, preferredTimescale: 600)).image

        var clip = ClipAsset(
            id: UUID(), url: url, isPhoto: isPhoto, duration: duration,
            displaySize: Reframe.displaySize(naturalSize: natural, preferredTransform: transform),
            focus: CGPoint(x: 0.5, y: 0.5), framing: nil, motion: 0, brightness: 0.4, thumbnail: first
        )
        guard let first else { return clip }

        let a = PixelStats.luma(first, width: 32, height: 32)
        clip.brightness = PixelStats.meanBrightness(a)
        if let second {
            clip.motion = min(1, PixelStats.meanAbsDiff(a, PixelStats.luma(second, width: 32, height: 32)) / 25)
        }
        let look = look(at: first)
        clip.framing = look.framing
        clip.focus = look.focus
        return clip
    }

    /// Framing from the largest face (or, with no face, the size of the salient object) and
    /// the point to keep centred. Vision failures fall back to a centred, unknown framing.
    static func look(at image: CGImage) -> (framing: Template.Framing?, focus: CGPoint) {
        let faces = VNDetectFaceRectanglesRequest()
        let saliency = VNGenerateAttentionBasedSaliencyImageRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try? handler.perform([faces])
        try? handler.perform([saliency])

        var focus = CGPoint(x: 0.5, y: 0.5)
        var framing: Template.Framing?
        if let face = faces.results?.max(by: { $0.boundingBox.area < $1.boundingBox.area }) {
            let area = face.boundingBox.area
            framing = area > 0.06 ? .close : area > 0.008 ? .medium : .wide
            focus = CGPoint(x: face.boundingBox.midX, y: 1 - face.boundingBox.midY)
        } else if let object = saliency.results?.first?.salientObjects?.max(by: { $0.boundingBox.area < $1.boundingBox.area }) {
            let area = object.boundingBox.area
            framing = area > 0.35 ? .close : area < 0.1 ? .wide : .medium
            focus = CGPoint(x: object.boundingBox.midX, y: 1 - object.boundingBox.midY)
        }
        return (framing, focus)
    }
}

extension CGRect {
    var area: CGFloat { width * height }
}
