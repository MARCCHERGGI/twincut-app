import AVFoundation
import XCTest
@testable import Reelsy

/// The soundtrack: laid under the new reel from its first frame and cut where the reel ends.
final class SongTests: XCTestCase {
    /// A click track written as an audio file, standing in for a reel's song.
    private func song(seconds: Double) throws -> URL {
        let samples = Synth.clicks(bpm: 120, seconds: seconds)
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: Rhythm.sampleRate, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)))
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
        let url = Synth.tempURL("caf")
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
        return url
    }

    func testExportCarriesTheSongForTheReelsLength() async throws {
        let clip = try await ClipProbe.probe(url: try await Synth.video([(.red, 2.5)], size: CGSize(width: 360, height: 640)), isPhoto: false)
        let plan = CutPlanner.plan(template: Synth.template(shots: [1, 1]), clips: [clip.traits], arrangement: .order)
        let spec = RenderSpec(plan: plan, clips: [clip], captions: [], sound: .beat, beat: try song(seconds: 5))

        let built = try await Composer.build(spec)
        let audio = try await built.asset.loadTracks(withMediaType: .audio)
        XCTAssertEqual(audio.count, 1, "one song track")
        let range = try await XCTUnwrap(audio.first).load(.timeRange)
        XCTAssertEqual(range.start.seconds, 0, accuracy: 0.01, "song starts with the reel")
        XCTAssertEqual(range.duration.seconds, 2, accuracy: 0.05, "song cut where the reel ends")

        let out = Synth.tempURL()
        try await Exporter.export(spec, to: out) { _ in }
        let exported = try await AVURLAsset(url: out).loadTracks(withMediaType: .audio)
        XCTAssertFalse(exported.isEmpty, "exported reel has the song")
    }

    func testNoSongMeansSilent() async throws {
        let clip = try await ClipProbe.probe(url: try await Synth.video([(.red, 1.5)], size: CGSize(width: 360, height: 640)), isPhoto: false)
        let plan = CutPlanner.plan(template: Synth.template(shots: [1]), clips: [clip.traits], arrangement: .order)
        let built = try await Composer.build(RenderSpec(plan: plan, clips: [clip], captions: [], sound: .beat, beat: nil))
        let audio = try await built.asset.loadTracks(withMediaType: .audio)
        XCTAssertTrue(audio.isEmpty)
    }

    // MARK: Twincut's own beat

    func testBeatGridReachesTheEnd() {
        let beats = BeatSynth.extend([0.5, 1.0, 1.5, 2.0], to: 4.0)
        XCTAssertEqual(beats.first ?? -1, 0, accuracy: 0.001, "grid continues back to the start")
        XCTAssertEqual(beats.last ?? -1, 3.5, accuracy: 0.001, "and forward to the end")
        XCTAssertEqual(beats.count, 8)
    }

    func testOneTakeWithoutTempoStillGetsASteadyBeat() {
        let template = Synth.template(shots: [15], beats: [])
        let beats = BeatSynth.beatTimes(template)
        XCTAssertGreaterThanOrEqual(beats.count, 10)
        XCTAssertGreaterThan(beats.last ?? 0, 14)
    }

    func testKicksLandOnTheBeats() {
        let beats = [0.5, 1.0, 1.5, 2.0]
        let samples = BeatSynth.render(beats: beats, duration: 2.5)
        let rate = BeatSynth.sampleRate
        func energy(_ from: Double, _ to: Double) -> Float {
            samples[Int(from * rate)..<Int(to * rate)].reduce(0) { $0 + $1 * $1 }
        }
        for b in beats {
            XCTAssertGreaterThan(energy(b, b + 0.05), 10 * energy(b - 0.12, b - 0.07), "kick at \(b)")
        }
    }

    func testBeatTrackCoversTheTemplateAndExports() async throws {
        let template = Synth.template(shots: [1, 1, 1], beats: [0, 0.5, 1, 1.5])
        let url = try BeatSynth.track(for: template)
        let length = try await AVURLAsset(url: url).load(.duration).seconds
        XCTAssertEqual(length, template.duration, accuracy: 0.05)

        let clip = try await ClipProbe.probe(url: try await Synth.video([(.blue, 3.5)], size: CGSize(width: 360, height: 640)), isPhoto: false)
        let plan = CutPlanner.plan(template: template, clips: [clip.traits], arrangement: .order)
        let built = try await Composer.build(RenderSpec(plan: plan, clips: [clip], captions: [], sound: .beat, beat: url))
        let audio = try await built.asset.loadTracks(withMediaType: .audio)
        XCTAssertEqual(audio.count, 1, "the beat is under the reel")
    }
}
