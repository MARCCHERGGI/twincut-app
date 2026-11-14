import AVFoundation

enum AnalysisStage: Int, CaseIterable, Comparable {
    case reading, cuts, beat, shots, done

    var label: String {
        switch self {
        case .reading: return "Opening the video"
        case .cuts: return "Finding every cut"
        case .beat: return "Locking onto the beat"
        case .shots: return "Reading each shot and caption"
        case .done: return "Template ready"
        }
    }

    static func < (a: AnalysisStage, b: AnalysisStage) -> Bool { a.rawValue < b.rawValue }
}

enum AnalysisError: LocalizedError {
    case noVideo, tooLong, tooShort

    var errorDescription: String? {
        switch self {
        case .noVideo: return "That file has no video Twincut can read."
        case .tooLong: return "Twincut copies videos up to 3 minutes long. Pick a shorter one."
        case .tooShort: return "That video is too short to copy an edit from."
        }
    }
}

/// Turns a reference video into a Template on the device. The video never leaves the phone
/// and is not kept: only its timing, colours and caption positions are.
enum ReferenceAnalyzer {
    static let maxSeconds = 180.0

    static func analyze(url: URL, stage: @escaping @MainActor (AnalysisStage) -> Void) async throws -> Template {
        let work = Task.detached(priority: .userInitiated) {
            try await run(url: url, stage: stage)
        }
        return try await withTaskCancellationHandler { try await work.value } onCancel: { work.cancel() }
    }

    private static func run(url: URL, stage: @escaping @MainActor (AnalysisStage) -> Void) async throws -> Template {
        await stage(.reading)
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw AnalysisError.noVideo }
        let duration = try await asset.load(.duration).seconds
        guard duration <= maxSeconds + 1 else { throw AnalysisError.tooLong }
        guard duration >= 1.5 else { throw AnalysisError.tooShort }
        let (natural, transform) = try await track.load(.naturalSize, .preferredTransform)
        let display = Reframe.displaySize(naturalSize: natural, preferredTransform: transform)

        await stage(.cuts)
        let scenes = try SceneDetector.scores(asset: asset, track: track)
        let cuts = SceneDetector.detectCuts(scenes, duration: duration)
        let bounds = [0] + cuts + [duration]
        let ranges = zip(bounds, bounds.dropFirst()).map { (start: $0, end: $1) }
        let motion = SceneDetector.shotMotion(scenes, ranges)

        await stage(.beat)
        let rhythm = try await Rhythm.samples(from: asset).flatMap { Rhythm.analyze($0) }
        let strong = rhythm.map { $0.confidence >= 1.4 } ?? false

        await stage(.shots)
        let looks = await ShotReader.read(asset: asset, shots: ranges)

        let shots = ranges.enumerated().map { i, r in
            let look = looks[i]
            return Template.Shot(
                index: i, start: round3(r.start), end: round3(r.end), color: look.color,
                brightness: look.brightness, motion: (motion[i] * 100).rounded() / 100,
                framing: look.framing, subject: look.subject, camera: motion[i] > 0.6 ? "moving" : "static",
                hint: Labels.hint(framing: look.framing, subject: look.subject, noun: look.noun, motion: motion[i], length: r.end - r.start)
            )
        }
        let texts = mergeCaptions(ranges: ranges, looks: looks)
        let pace = paceOf(shotCount: shots.count, duration: duration)
        let onBeat = strong ? Rhythm.onBeatShare(cuts: cuts, beats: rhythm!.beats) : 0

        var tags = [pace.label]
        if onBeat >= 0.6 { tags.append("On the beat") }
        if !texts.isEmpty { tags.append("Captions") }

        await stage(.done)
        return Template(
            id: UUID().uuidString,
            title: title(looks: looks, pace: pace, shotCount: shots.count),
            source: .init(kind: "photos", platform: nil),
            duration: round3(duration),
            aspect: .init(width: Int(display.width), height: Int(display.height)),
            pace: pace,
            tempo: strong ? .init(bpm: rhythm!.bpm, confidence: rhythm!.confidence) : nil,
            beats: strong ? rhythm!.beats.filter { $0 < duration } : [],
            onBeat: (onBeat * 100).rounded() / 100,
            shots: shots,
            texts: texts,
            tags: tags,
            labeledBy: "on-device",
            createdAt: Date()
        )
    }

    static func round3(_ v: Double) -> Double { (v * 1000).rounded() / 1000 }

    static func paceOf(shotCount: Int, duration: Double) -> Template.Pace {
        if shotCount <= 1 { return .single }
        let perSecond = Double(shotCount - 1) / duration
        if perSecond >= 1.5 { return .rapid }
        if perSecond >= 0.7 { return .fast }
        if perSecond >= 0.3 { return .steady }
        return .slow
    }

    static func title(looks: [ShotLook], pace: Template.Pace, shotCount: Int) -> String {
        if pace == .single { return "One-take video" }
        let nouns = looks.compactMap(\.noun)
        let counts = Dictionary(nouns.map { ($0, 1) }, uniquingKeysWith: +)
        if let top = counts.max(by: { $0.value < $1.value }), top.value * 3 >= looks.count {
            return "\(top.key.capitalizedFirst) \(shotCount >= 6 ? "montage" : "edit")"
        }
        return "\(pace.label) \(shotCount)-cut edit"
    }

    /// One caption per run of consecutive shots showing the same text.
    static func mergeCaptions(ranges: [(start: Double, end: Double)], looks: [ShotLook]) -> [Template.TextBeat] {
        var texts: [Template.TextBeat] = []
        for (i, look) in looks.enumerated() {
            guard let c = look.caption else { continue }
            if var last = texts.last, last.text.lowercased() == c.text.lowercased(), abs(last.end - ranges[i].start) < 0.05 {
                last.end = round3(ranges[i].end)
                texts[texts.count - 1] = last
            } else {
                texts.append(.init(text: c.text, start: round3(ranges[i].start), end: round3(ranges[i].end), position: c.position, size: c.size))
            }
        }
        return texts
    }
}
