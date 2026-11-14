import AVFoundation
import XCTest
@testable import Reelsy

/// End to end on real media: synthetic videos in, a real MP4 out, checked frame by frame.
final class RenderTests: XCTestCase {
    func testExportMatchesThePlan() async throws {
        let red = try await ClipProbe.probe(url: try await Synth.video([(.red, 2)], size: CGSize(width: 640, height: 360)), isPhoto: false)
        let blue = try await ClipProbe.probe(url: try await Synth.video([(.blue, 2)], size: CGSize(width: 360, height: 640)), isPhoto: false)
        let green = try await ClipProbe.probe(url: try await Synth.video([(.green, 0.5)], size: CGSize(width: 400, height: 400)), isPhoto: false)
        XCTAssertEqual(red.displaySize, CGSize(width: 640, height: 360))

        let template = Synth.template(shots: [1, 1, 1])
        let plan = CutPlanner.plan(template: template, clips: [red.traits, blue.traits, green.traits], arrangement: .order)
        XCTAssertEqual(plan.segments[2].sourceDuration, 0.5, accuracy: 0.01, "short clip is slowed down")
        let caption = Caption(text: "HELLO", start: 0, end: 1.5, position: .top, size: .large, style: .boxed)
        let spec = RenderSpec(plan: plan, clips: [red, blue, green], captions: [caption], sound: .off)

        let out = Synth.tempURL()
        let last = ProgressBox()
        try await Exporter.export(spec, to: out) { last.value = $0 }
        XCTAssertEqual(last.value, 1)

        let asset = AVURLAsset(url: out)
        let duration = try await asset.load(.duration).seconds
        XCTAssertEqual(duration, 3, accuracy: 0.15)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(videoTracks.first)
        let (natural, transform) = try await track.load(.naturalSize, .preferredTransform)
        XCTAssertEqual(Reframe.displaySize(naturalSize: natural, preferredTransform: transform), CGSize(width: 1080, height: 1920))
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        XCTAssertTrue(audioTracks.isEmpty, "silent export has no audio track")

        let w = 108, h = 192
        for (time, expected) in [(0.5, "red"), (1.5, "blue"), (2.5, "green")] {
            let rgb = try await Synth.frame(out, at: time, width: w, height: h)
            let centre = Synth.pixel(rgb, x: w / 2, y: Int(Double(h) * 0.6), width: w)
            XCTAssertEqual(Synth.dominant(centre), expected, "frame at \(time): \(centre)")
            let corner = Synth.pixel(rgb, x: 3, y: h - 4, width: w)
            XCTAssertEqual(Synth.dominant(corner), expected, "fill leaves no bars at \(time): \(corner)")
        }

        // The boxed caption shows as white pixels around 22% from the top, only while it's on.
        func whiteShare(at time: Double) async throws -> Double {
            let rgb = try await Synth.frame(out, at: time, width: w, height: h)
            let row = Int(Double(h) * Template.Position.top.y)
            var white = 0, total = 0
            for y in (row - 2)...(row + 2) {
                for x in 0..<w {
                    let p = Synth.pixel(rgb, x: x, y: y, width: w)
                    if p.r > 225 && p.g > 225 && p.b > 225 { white += 1 }
                    total += 1
                }
            }
            return Double(white) / Double(total)
        }
        let during = try await whiteShare(at: 0.5)
        let after = try await whiteShare(at: 2.5)
        XCTAssertGreaterThan(during, 0.08, "caption box visible")
        XCTAssertLessThan(after, 0.01, "caption gone after its end")
    }

    /// Core Animation's export layer space is flipped; a caption drawn the wrong way up still
    /// passes a symmetric white-box check, so read the letters: a T's crossbar sits on top.
    func testCaptionIsUpright() async throws {
        let clip = try await ClipProbe.probe(url: try await Synth.video([(.red, 1.2)], size: CGSize(width: 360, height: 640)), isPhoto: false)
        let plan = CutPlanner.plan(template: Synth.template(shots: [1]), clips: [clip.traits], arrangement: .order)
        let caption = Caption(text: "TTTT", start: 0, end: 1, position: .top, size: .large, style: .boxed)
        let out = Synth.tempURL()
        try await Exporter.export(RenderSpec(plan: plan, clips: [clip], captions: [caption], sound: .off), to: out) { _ in }

        let w = 1080, h = 1920
        let rgb = try await Synth.frame(out, at: 0.5, width: w, height: h)
        let centre = Int(Template.Position.top.y * Double(h))
        var dark: [(row: Int, count: Int)] = []
        for y in (centre - 120)...(centre + 120) {
            var count = 0
            for x in 150..<(w - 150) {
                let p = Synth.pixel(rgb, x: x, y: y, width: w)
                if p.r < 70 && p.g < 70 && p.b < 70 { count += 1 }
            }
            if count > 0 { dark.append((y, count)) }
        }
        let first = try XCTUnwrap(dark.first?.row, "caption letters found")
        let last = dark.last!.row
        let peak = dark.max { $0.count < $1.count }!.row
        XCTAssertLessThan(peak, (first + last) / 2, "crossbars are in the top half of the text (rows \(first)...\(last), peak \(peak))")
        XCTAssertEqual(Double(first + last) / 2, Double(centre), accuracy: 40, "caption centred on its position")
    }

    func testFitModeLeavesBars() async throws {
        let wide = try await ClipProbe.probe(url: try await Synth.video([(.red, 1.5)], size: CGSize(width: 640, height: 360)), isPhoto: false)
        var clip = wide
        clip.fill = .fit
        let template = Synth.template(shots: [1])
        let plan = CutPlanner.plan(template: template, clips: [clip.traits], arrangement: .order)
        let out = Synth.tempURL()
        try await Exporter.export(RenderSpec(plan: plan, clips: [clip], captions: [], sound: .off), to: out) { _ in }
        let rgb = try await Synth.frame(out, at: 0.5, width: 108, height: 192)
        let top = Synth.pixel(rgb, x: 54, y: 10, width: 108)
        let mid = Synth.pixel(rgb, x: 54, y: 96, width: 108)
        XCTAssertLessThan(Int(top.r) + Int(top.g) + Int(top.b), 40, "black bar above a fitted landscape clip")
        XCTAssertEqual(Synth.dominant(mid), "red")
    }

    func testPhotoBecomesStillVideo() async throws {
        let size = CGSize(width: 301, height: 400)
        let image = UIGraphicsImageRenderer(size: size, format: { let f = UIGraphicsImageRendererFormat(); f.scale = 1; return f }()).image { ctx in
            UIColor.blue.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
        let cg = try XCTUnwrap(StillVideo.upright(try XCTUnwrap(image.jpegData(compressionQuality: 0.9))))
        let url = Synth.tempURL()
        try await StillVideo.write(cg, to: url)
        let clip = try await ClipProbe.probe(url: url, isPhoto: true)
        XCTAssertEqual(clip.duration, StillVideo.length, accuracy: 0.05)
        XCTAssertEqual(clip.displaySize, CGSize(width: 300, height: 400))
        XCTAssertNil(clip.traits.duration, "photos fill any slot")
    }
}

private final class ProgressBox { var value = 0.0 }

final class AnalyzerTests: XCTestCase {
    func testFindsEveryCutInAReference() async throws {
        let lengths = [1.0, 1.5, 0.7, 1.3]
        let url = try await Synth.video([(.red, 1.0), (.green, 1.5), (.blue, 0.7), (.white, 1.3)], size: CGSize(width: 360, height: 640))
        let template = try await ReferenceAnalyzer.analyze(url: url) { _ in }

        XCTAssertEqual(template.duration, lengths.reduce(0, +), accuracy: 0.05)
        XCTAssertEqual(template.aspect.width, 360)
        XCTAssertEqual(template.aspect.height, 640)
        XCTAssertEqual(template.shots.count, 4, "shots: \(template.shots.map(\.start))")
        guard template.shots.count == 4 else { return }
        for (shot, expected) in zip(template.shots.dropFirst(), [1.0, 2.5, 3.2]) {
            XCTAssertEqual(shot.start, expected, accuracy: 2.0 / 30, "cut at \(expected)")
        }
        XCTAssertTrue(template.beats.isEmpty, "a silent video has no beat")
        XCTAssertNil(template.tempo)

        let first = Color(template.shots[0].color)
        XCTAssertGreaterThan(first.r, first.g, "first shot reads as red: \(template.shots[0].color)")
        XCTAssertGreaterThan(first.r, first.b)
        XCTAssertGreaterThan(template.shots[3].brightness, 0.8, "white shot is bright")
    }

    func testRejectsTooShort() async throws {
        let url = try await Synth.video([(.red, 1.0)], size: CGSize(width: 360, height: 640))
        do {
            _ = try await ReferenceAnalyzer.analyze(url: url) { _ in }
            XCTFail("a 1 s video should be rejected")
        } catch let error as AnalysisError {
            XCTAssertEqual(error.localizedDescription, AnalysisError.tooShort.localizedDescription)
        }
    }

    func testTemplateRoundTrips() throws {
        let t = Synth.template(shots: [1, 2], beats: [0, 0.5], texts: [.init(text: "hi", start: 0, end: 1, position: .bottom, size: .small)])
        let back = try Template.decode(from: JSONEncoder.reelsy.encode(t))
        XCTAssertEqual(back, t)
    }

    private struct Color {
        let r, g, b: Int
        init(_ hex: String) {
            let v = Int(hex.dropFirst(), radix: 16) ?? 0
            r = (v >> 16) & 0xFF
            g = (v >> 8) & 0xFF
            b = v & 0xFF
        }
    }
}
