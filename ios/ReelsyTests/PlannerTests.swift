import XCTest
@testable import Reelsy

@MainActor
final class PlannerTests: XCTestCase {
    private func traits(_ durations: [Double?]) -> [ClipTraits] {
        durations.map { ClipTraits(duration: $0, framing: nil, motion: 0.5, brightness: 0.5) }
    }

    private func assertCovers(_ plan: CutPlan, _ template: Template, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(plan.segments.first?.start ?? -1, 0, accuracy: 1e-9, file: file, line: line)
        XCTAssertEqual(plan.segments.last?.end ?? -1, template.duration, accuracy: 1e-9, file: file, line: line)
        for (a, b) in zip(plan.segments, plan.segments.dropFirst()) {
            XCTAssertEqual(a.end, b.start, accuracy: 1e-9, "gap between segments", file: file, line: line)
        }
        XCTAssertTrue(plan.segments.allSatisfy { $0.duration > 0 }, file: file, line: line)
    }

    func testOneClipPerShot() {
        let t = Synth.template(shots: [1, 2, 1.5])
        let plan = CutPlanner.plan(template: t, clips: traits([5, 5, 5]), arrangement: .order)
        assertCovers(plan, t)
        XCTAssertEqual(plan.segments.map(\.clipIndex), [0, 1, 2])
        XCTAssertEqual(plan.segments.map(\.duration), [1, 2, 1.5])
    }

    func testFewerClipsRepeatFromDifferentMoments() {
        let t = Synth.template(shots: [1, 1, 1, 1, 1, 1])
        let plan = CutPlanner.plan(template: t, clips: traits([10, 10]), arrangement: .smart)
        assertCovers(plan, t)
        XCTAssertEqual(Set(plan.segments.map(\.clipIndex)), [0, 1])
        for c in 0..<2 {
            let mine = plan.segments.filter { $0.clipIndex == c }.sorted { $0.sourceStart < $1.sourceStart }
            XCTAssertEqual(mine.count, 3)
            for (a, b) in zip(mine, mine.dropFirst()) {
                XCTAssertLessThanOrEqual(a.sourceStart + a.sourceDuration, b.sourceStart + 1e-9, "clip \(c) reuses footage")
            }
            XCTAssertLessThanOrEqual(mine.last!.sourceStart + mine.last!.sourceDuration, 10 + 1e-9)
        }
    }

    func testMoreClipsSplitLongShotsOnTheBeat() {
        let t = Synth.template(shots: [4, 1], beats: [0, 0.5, 1, 1.5, 2, 2.5, 3, 3.5, 4, 4.5])
        let plan = CutPlanner.plan(template: t, clips: traits([5, 5, 5, 5]), arrangement: .order)
        assertCovers(plan, t)
        XCTAssertEqual(plan.segments.count, 4)
        XCTAssertEqual(Set(plan.segments.map(\.clipIndex)), [0, 1, 2, 3])
        for seg in plan.segments {
            XCTAssertTrue(t.beats.contains { abs($0 - seg.start) < 1e-9 } || seg.start == 0, "split off the beat at \(seg.start)")
        }
    }

    func testShortClipPlaysSlowerToFill() {
        let t = Synth.template(shots: [2])
        let plan = CutPlanner.plan(template: t, clips: traits([0.8]), arrangement: .order)
        XCTAssertEqual(plan.segments[0].sourceDuration, 0.8, accuracy: 1e-9)
        XCTAssertEqual(plan.segments[0].duration, 2, accuracy: 1e-9)
    }

    func testPhotoFillsAnyLength() {
        let t = Synth.template(shots: [3, 2])
        let plan = CutPlanner.plan(template: t, clips: traits([nil, nil]), arrangement: .order)
        XCTAssertEqual(plan.segments.map(\.sourceDuration), [3, 2])
        XCTAssertEqual(plan.segments.map(\.sourceStart), [0, 0])
    }

    func testSmartUsesEveryClipWithinFairShare() {
        let t = Synth.template(shots: Array(repeating: 0.5, count: 19))
        var clips = traits([4, 4, 4, 4, 4])
        clips[0].motion = 0.5
        clips[1].motion = 0.49
        let plan = CutPlanner.plan(template: t, clips: clips, arrangement: .smart)
        let uses = Dictionary(grouping: plan.segments, by: \.clipIndex).mapValues(\.count)
        XCTAssertEqual(Set(uses.keys), [0, 1, 2, 3, 4])
        XCTAssertLessThanOrEqual(uses.values.max()!, 4)
        let repeats = zip(plan.segments, plan.segments.dropFirst()).filter { $0.clipIndex == $1.clipIndex }.count
        XCTAssertEqual(repeats, 0, "the same clip back to back")
    }

    func testFrameBoundariesAreStrictlyIncreasing() {
        let t = Synth.template(shots: [0.01, 0.01, 1])
        let plan = CutPlanner.plan(template: t, clips: traits([2, 2, 2]), arrangement: .order)
        let frames = Composer.frameBoundaries(plan, fps: 30)
        for (a, b) in zip(frames, frames.dropFirst()) { XCTAssertLessThan(a, b) }
    }

    func testStartersDecodeAndPlan() throws {
        let library = Library(file: Synth.tempURL("json"))
        XCTAssertEqual(library.starters.count, 5)
        for starter in library.starters {
            XCTAssertFalse(starter.shots.isEmpty, starter.title)
            XCTAssertEqual(starter.shots.last!.end, starter.duration, accuracy: 0.002, starter.title)
            for n in [1, starter.suggestedClips, starter.maxClips] {
                let plan = CutPlanner.plan(template: starter, clips: traits(Array(repeating: 3, count: n)), arrangement: .smart)
                assertCovers(plan, starter)
                XCTAssertEqual(Set(plan.segments.map(\.clipIndex)).count, n, "\(starter.title) with \(n) clips")
            }
        }
    }

    @MainActor
    func testUnreadableLibraryIsSetAsideNotOverwritten() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("templates.json")
        try Data("not json".utf8).write(to: file)
        let library = Library(file: file)
        XCTAssertTrue(library.templates.isEmpty)
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertTrue(names.contains { $0.hasPrefix("templates-unreadable-") }, "the old file is kept: \(names)")
    }

    /// TestFlight builds 1-4 saved a "song" field; 1.0 must still open those templates.
    func testTemplatesFromEarlierBuildsStillLoad() throws {
        let json = """
        [{"version":1,"id":"old-1","title":"Old reel","source":{"kind":"photos"},"duration":6,
          "aspect":{"width":1080,"height":1920},"pace":"fast","tempo":{"bpm":120,"confidence":0.8},
          "beats":[0,0.5,1],"onBeat":0.9,"song":"old-1.m4a",
          "shots":[{"index":0,"start":0,"end":3,"color":"#ff0000","brightness":0.5,"motion":0.4,"hint":"Wide"},
                   {"index":1,"start":3,"end":6,"color":"#00ff00","brightness":0.5,"motion":0.4,"hint":"Close"}],
          "texts":[{"text":"","start":0,"end":2,"position":"top","size":"large"}],"tags":[]}]
        """
        let templates = try Template.decodeList(from: Data(json.utf8))
        XCTAssertEqual(templates.first?.id, "old-1")
        XCTAssertEqual(templates.first?.shots.count, 2)
    }

    func testLibrarySavesAndReloads() throws {
        let file = Synth.tempURL("json")
        let a = Library(file: file)
        var t = Synth.template(shots: [1, 1])
        t.title = "Mine"
        a.add(t)
        a.rename(t.id, to: "  Renamed  ")
        let b = Library(file: file)
        XCTAssertEqual(b.templates.map(\.title), ["Renamed"])
        b.delete(t.id)
        XCTAssertTrue(Library(file: file).templates.isEmpty)
    }
}

final class ReframeTests: XCTestCase {
    let render = CGSize(width: 1080, height: 1920)

    private func placed(_ natural: CGSize, _ pt: CGAffineTransform = .identity, _ mode: FillMode, focus: CGPoint = CGPoint(x: 0.5, y: 0.5)) -> CGRect {
        CGRect(origin: .zero, size: natural).applying(Reframe.transform(naturalSize: natural, preferredTransform: pt, renderSize: render, mode: mode, focus: focus))
    }

    func testLandscapeFillCoversFrame() {
        let r = placed(CGSize(width: 1920, height: 1080), .identity, .fill)
        XCTAssertLessThanOrEqual(r.minX, 0.5)
        XCTAssertGreaterThanOrEqual(r.maxX, 1079.5)
        XCTAssertEqual(r.minY, 0, accuracy: 0.5)
        XCTAssertEqual(r.height, 1920, accuracy: 0.5)
    }

    func testLandscapeFitLetterboxes() {
        let r = placed(CGSize(width: 1920, height: 1080), .identity, .fit)
        XCTAssertEqual(r.width, 1080, accuracy: 0.5)
        XCTAssertEqual(r.midY, 960, accuracy: 0.5)
    }

    func testFocusKeepsSubjectInFrameWithoutGaps() {
        let r = placed(CGSize(width: 1920, height: 1080), .identity, .fill, focus: CGPoint(x: 1, y: 0.5))
        XCTAssertEqual(r.maxX, 1080, accuracy: 0.5, "pushed to the right edge, no black gap")
    }

    func testRotatedPhoneVideoIsUpright() {
        // iPhone portrait video: stored landscape, rotated 90 degrees.
        let natural = CGSize(width: 1920, height: 1080)
        let rotate = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 1080, ty: 0)
        XCTAssertEqual(Reframe.displaySize(naturalSize: natural, preferredTransform: rotate), CGSize(width: 1080, height: 1920))
        let r = placed(natural, rotate, .fill)
        XCTAssertEqual(r.minX, 0, accuracy: 0.5)
        XCTAssertEqual(r.minY, 0, accuracy: 0.5)
        XCTAssertEqual(r.width, 1080, accuracy: 0.5)
        XCTAssertEqual(r.height, 1920, accuracy: 0.5)
    }
}

final class RhythmTests: XCTestCase {
    func testFindsTempoAndBeatsOfAClickTrack() throws {
        for bpm in [96.0, 120, 128] {
            let result = try XCTUnwrap(Rhythm.analyze(Synth.clicks(bpm: bpm, seconds: 12)), "\(bpm)")
            XCTAssertEqual(result.bpm, bpm, accuracy: bpm * 0.03, "tempo for \(bpm)")
            let period = 60 / bpm
            let gaps = zip(result.beats, result.beats.dropFirst()).map { $1 - $0 }
            let median = gaps.sorted()[gaps.count / 2]
            XCTAssertEqual(median, period, accuracy: 0.03, "beat spacing for \(bpm)")
            // Beats land on the clicks (offset 0.1 s), within 50 ms.
            let phase = result.beats.map { b in abs(((b - 0.1) / period).rounded() * period - (b - 0.1)) }
            XCTAssertLessThan(phase.sorted()[phase.count / 2], 0.05, "beat phase for \(bpm)")
        }
    }

    func testSilenceHasNoBeat() {
        XCTAssertNil(Rhythm.analyze([Float](repeating: 0, count: Int(Rhythm.sampleRate * 6))))
    }

    func testOnBeatShareCountsHalfBeats() {
        let beats = [0.0, 0.5, 1.0, 1.5, 2.0]
        XCTAssertEqual(Rhythm.onBeatShare(cuts: [0.5, 0.75, 1.4], beats: beats), 2.0 / 3.0, accuracy: 1e-9)
    }
}

final class SceneDetectorTests: XCTestCase {
    func testPeaksAboveTheNeighbourhoodAreCuts() {
        let fps = 30.0
        var scores = (0..<150).map { i in 0.01 + 0.005 * Double(i % 3) }
        scores[30] = 0.6
        scores[75] = 0.2  // modest, but far above its quiet neighbourhood
        scores[78] = 0.5  // too close to the last cut: keeps the stronger one
        let s = SceneScores(times: scores.indices.map { Double($0) / fps }, scores: scores)
        let cuts = SceneDetector.detectCuts(s, duration: 5)
        XCTAssertEqual(cuts.count, 2)
        XCTAssertEqual(cuts[0], 1.0, accuracy: 1e-9)
        XCTAssertEqual(cuts[1], 78 / fps, accuracy: 1e-9)
    }

    func testHandheldShakeIsNotACut() {
        let scores = (0..<120).map { i in 0.08 + 0.06 * sin(Double(i)) }
        let s = SceneScores(times: scores.indices.map { Double($0) / 30 }, scores: scores)
        XCTAssertTrue(SceneDetector.detectCuts(s, duration: 4).isEmpty)
    }
}
