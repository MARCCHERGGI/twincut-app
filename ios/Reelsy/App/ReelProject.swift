import AVFoundation
import Observation

/// One reel being made: a template, the user's clips, and the plan that fits them together.
/// Owns the live preview player.
@MainActor
@Observable
final class ReelProject: Identifiable {
    let id = UUID()
    let template: Template
    private(set) var clips: [ClipAsset]
    private(set) var plan: CutPlan
    var arrangement: Arrangement { didSet { if arrangement != oldValue { replan() } } }
    var captions: [Caption]
    /// Twincut's own beat for this template, made once when the project opens.
    let beat: URL?
    var sound: SoundMode { didSet { if sound != oldValue { refresh() } } }
    private(set) var isBuilding = false
    private(set) var previewError: String?
    private(set) var currentTime: Double = 0
    private(set) var isPlaying = false

    @ObservationIgnored let player = AVPlayer()
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var endObserver: NSObjectProtocol?
    @ObservationIgnored private var buildTask: Task<Void, Never>?

    init(template: Template, clips: [ClipAsset], arrangement: Arrangement = .smart) {
        self.template = template
        self.clips = clips
        self.arrangement = arrangement
        self.plan = CutPlanner.plan(template: template, clips: clips.map(\.traits), arrangement: arrangement)
        self.captions = template.texts.map(Caption.init)
        self.beat = try? BeatSynth.track(for: template)
        self.sound = beat == nil ? .off : .beat
        player.isMuted = false
        player.actionAtItemEnd = .none
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 30), queue: .main) { [weak self] time in
            MainActor.assumeIsolated { self?.currentTime = time.seconds }
        }
    }

    func stop() {
        closed = true
        buildTask?.cancel()
        player.pause()
        player.replaceCurrentItem(with: nil)
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        timeObserver = nil
        endObserver = nil
    }

    var spec: RenderSpec {
        RenderSpec(plan: plan, clips: clips, captions: captions, sound: sound, beat: beat)
    }

    func clip(for segment: Segment) -> ClipAsset { clips[segment.clipIndex] }

    func replan() {
        plan = CutPlanner.plan(template: template, clips: clips.map(\.traits), arrangement: arrangement)
        refresh()
    }

    func replace(clip id: UUID, with clip: ClipAsset) {
        guard let index = clips.firstIndex(where: { $0.id == id }) else { return }
        clips[index] = clip
        replan()
    }

    func moveClip(from source: Int, to destination: Int) {
        guard clips.indices.contains(source), clips.indices.contains(destination), source != destination else { return }
        let clip = clips.remove(at: source)
        clips.insert(clip, at: destination)
        arrangement = .order
        replan()
    }

    func setFill(_ fill: FillMode, forClip index: Int) {
        guard clips.indices.contains(index) else { return }
        clips[index].fill = fill
        refresh()
    }

    /// Moves where a segment reads from inside its clip, keeping its length.
    func setSourceStart(_ start: Double, forSegment index: Int) {
        guard plan.segments.indices.contains(index) else { return }
        let seg = plan.segments[index]
        let clip = clips[seg.clipIndex]
        let latest = max(0, (clip.isPhoto ? StillVideo.length : clip.duration) - seg.sourceDuration)
        plan.segments[index].sourceStart = min(max(0, start), latest)
        refresh()
    }

    func togglePlay() {
        if isPlaying { player.pause() } else { player.play() }
        isPlaying.toggle()
    }

    func seek(to seconds: Double) {
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = seconds
    }

    /// Set by `stop()`; late work (a clip import finishing) must not start playback again.
    @ObservationIgnored private var closed = false
    /// Set while the export screen is up, so a rebuild finishing then stays silent.
    @ObservationIgnored private var suspended = false

    func suspend() {
        suspended = true
        player.pause()
    }

    func resume() {
        suspended = false
        if isPlaying { player.play() }
    }

    /// Rebuilds the composition and swaps it into the player, keeping the playhead.
    func refresh() {
        guard !closed else { return }
        buildTask?.cancel()
        let spec = self.spec
        let resumeAt = currentTime
        isBuilding = true
        buildTask = Task {
            do {
                let built = try await Composer.build(spec)
                if Task.isCancelled { return }
                let item = AVPlayerItem(asset: built.asset)
                item.videoComposition = built.video
                item.audioTimePitchAlgorithm = .spectral
                if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
                endObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.player.seek(to: .zero)
                        if self?.isPlaying == true { self?.player.play() }
                    }
                }
                player.replaceCurrentItem(with: item)
                if resumeAt > 0, resumeAt < template.duration { seek(to: resumeAt) }
                previewError = nil
                isPlaying = true
                if !suspended { player.play() }
            } catch {
                if !Task.isCancelled { previewError = error.localizedDescription }
            }
            if !Task.isCancelled { isBuilding = false }
        }
    }
}
