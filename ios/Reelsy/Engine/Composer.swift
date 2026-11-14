import AVFoundation
import UIKit

enum SoundMode: String, CaseIterable, Identifiable {
    /// Twincut's own beat, generated on the template's beat times (BeatSynth).
    case beat
    /// Silent export: the user adds a song inside Instagram or TikTok.
    case off
    /// Keep each clip's own sound.
    case clips

    var id: String { rawValue }
}

struct RenderSpec {
    var plan: CutPlan
    var clips: [ClipAsset]
    var captions: [Caption]
    var sound: SoundMode
    /// Twincut's beat for the template; used when `sound` is `.beat`.
    var beat: URL?
    var renderSize = CGSize(width: 1080, height: 1920)
    var fps: Int32 = 30
}

struct BuiltComposition {
    let asset: AVMutableComposition
    let video: AVMutableVideoComposition
}

/// Builds the reel as an AVFoundation composition: two alternating video tracks, one hard
/// cut per segment, each clip reframed to 9:16 around its point of interest by
/// ReelCompositor. Nothing is rendered until export; the editor plays the composition live.
enum Composer {
    enum Failure: LocalizedError {
        case tracks, missingVideo
        var errorDescription: String? { "One of your clips couldn't be read. Try replacing it." }
    }

    /// Segment boundaries on the frame grid, strictly increasing so no segment is empty.
    static func frameBoundaries(_ plan: CutPlan, fps: Int32) -> [CMTime] {
        let step = CMTimeValue(600 / fps)
        var frames = [0] + plan.segments.map { Int(($0.end * Double(fps)).rounded()) }
        for k in 1..<frames.count where frames[k] <= frames[k - 1] { frames[k] = frames[k - 1] + 1 }
        return frames.map { CMTime(value: CMTimeValue($0) * step, timescale: 600) }
    }

    /// - Parameter burnCaptions: draw the captions into the frames (export). The editor
    ///   preview leaves them off and draws them in SwiftUI so edits show instantly.
    static func build(_ spec: RenderSpec, burnCaptions: Bool = false) async throws -> BuiltComposition {
        let overlays = burnCaptions ? await captionOverlays(spec.captions, renderSize: spec.renderSize) : []
        let composition = AVMutableComposition()
        guard let a = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let b = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { throw Failure.tracks }
        let videoTracks = [a, b]
        var audioTracks: [AVMutableCompositionTrack] = []
        if spec.sound == .clips {
            for _ in 0..<2 {
                if let t = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
                    audioTracks.append(t)
                }
            }
        }

        // A track holds its asset weakly, so the asset is kept here until the tracks are inserted.
        struct Source {
            let asset: AVURLAsset
            let video: AVAssetTrack
            let audio: AVAssetTrack?
            let natural: CGSize
            let transform: CGAffineTransform
            let duration: CMTime
        }
        var sources: [UUID: Source] = [:]
        for clip in spec.clips where sources[clip.id] == nil {
            let asset = AVURLAsset(url: clip.url)
            guard let video = try await asset.loadTracks(withMediaType: .video).first else { throw Failure.missingVideo }
            let (natural, transform, range) = try await video.load(.naturalSize, .preferredTransform, .timeRange)
            let duration = range.end
            let audio = try await asset.loadTracks(withMediaType: .audio).first
            sources[clip.id] = Source(asset: asset, video: video, audio: audio, natural: natural, transform: transform, duration: duration)
        }

        let bounds = frameBoundaries(spec.plan, fps: spec.fps)
        var instructions: [ReelInstruction] = []
        for (i, seg) in spec.plan.segments.enumerated() {
            let range = CMTimeRange(start: bounds[i], end: bounds[i + 1])
            let clip = spec.clips[seg.clipIndex]
            guard let src = sources[clip.id] else { throw Failure.missingVideo }

            var read = CMTimeRange(
                start: CMTime(seconds: max(0, seg.sourceStart), preferredTimescale: 600),
                duration: CMTime(seconds: max(seg.sourceDuration, 1.0 / Double(spec.fps)), preferredTimescale: 600)
            )
            if read.duration > src.duration { read = CMTimeRange(start: .zero, duration: src.duration) }
            if read.end > src.duration { read.start = src.duration - read.duration }

            let track = videoTracks[i % 2]
            try place(read, of: src.video, on: track, at: range)
            if !audioTracks.isEmpty, let audio = src.audio {
                try place(read, of: audio, on: audioTracks[i % 2], at: range)
            }

            let base = Reframe.transform(naturalSize: src.natural, preferredTransform: src.transform,
                                         renderSize: spec.renderSize, mode: clip.fill, focus: clip.focus)
            let end = clip.isPhoto
                ? Reframe.transform(naturalSize: src.natural, preferredTransform: src.transform,
                                    renderSize: spec.renderSize, mode: clip.fill, focus: clip.focus, zoom: 1.1)
                : base
            let captions = overlays.filter { $0.end > range.start.seconds && $0.start < range.end.seconds }
            instructions.append(ReelInstruction(timeRange: range, trackID: track.trackID, start: base, end: end, captions: captions))
        }

        if spec.sound == .beat, let beat = spec.beat {
            try await addSong(beat, to: composition, length: bounds.last ?? .zero)
        }

        // Silent clips or a single segment leave tracks with nothing on them; drop those.
        for track in composition.tracks where track.segments.isEmpty {
            composition.removeTrack(track)
        }

        let video = AVMutableVideoComposition()
        video.renderSize = spec.renderSize
        video.frameDuration = CMTime(value: 1, timescale: spec.fps)
        video.instructions = instructions
        video.customVideoCompositorClass = ReelCompositor.self
        video.colorPrimaries = AVVideoColorPrimaries_ITU_R_709_2
        video.colorTransferFunction = AVVideoTransferFunction_ITU_R_709_2
        video.colorYCbCrMatrix = AVVideoYCbCrMatrix_ITU_R_709_2
        return BuiltComposition(asset: composition, video: video)
    }

    /// Puts `read` of a source track at `range` on the composition track, padding the gap
    /// left by the other track's segments and stretching the footage when it is shorter.
    private static func place(_ read: CMTimeRange, of source: AVAssetTrack, on track: AVMutableCompositionTrack, at range: CMTimeRange) throws {
        let end = track.timeRange.end
        if end < range.start {
            track.insertEmptyTimeRange(CMTimeRange(start: end, end: range.start))
        }
        try track.insertTimeRange(read, of: source, at: range.start)
        if read.duration != range.duration {
            track.scaleTimeRange(CMTimeRange(start: range.start, duration: read.duration), toDuration: range.duration)
        }
    }

    /// Lays the song under the whole reel from time zero, cut off where the reel ends.
    static func addSong(_ url: URL, to composition: AVMutableComposition, length: CMTime) async throws {
        let asset = AVURLAsset(url: url)
        guard let audio = try await asset.loadTracks(withMediaType: .audio).first,
              let track = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { return }
        let available = try await asset.load(.duration)
        try track.insertTimeRange(CMTimeRange(start: .zero, duration: min(length, available)), of: audio, at: .zero)
    }

    /// The visible captions as images placed in the frame, rendered with the same SwiftUI view
    /// the editor shows.
    static func captionOverlays(_ captions: [Caption], renderSize size: CGSize) async -> [BurnedCaption] {
        let visible = captions.filter(\.isVisible)
        let images = await MainActor.run { visible.map { CaptionRenderer.image(for: $0, frameWidth: size.width) } }
        return zip(visible, images).compactMap { caption, image in
            guard let image else { return nil }
            let w = CGFloat(image.width), h = CGFloat(image.height)
            let centreFromTop = CGFloat(caption.position.y) * size.height
            // Core Image puts the origin at the bottom left.
            let origin = CGPoint(x: ((size.width - w) / 2).rounded(), y: (size.height - centreFromTop - h / 2).rounded())
            return BurnedCaption(image: CIImage(cgImage: image), origin: origin, start: caption.start, end: caption.end)
        }
    }
}
