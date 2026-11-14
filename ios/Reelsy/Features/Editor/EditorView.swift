import AVFoundation
import PhotosUI
import SwiftUI

struct EditorView: View {
    @Environment(AppModel.self) private var model
    @Bindable var project: ReelProject

    enum Tab: String, CaseIterable, Identifiable {
        case clips = "Clips", text = "Text", sound = "Sound"
        var id: String { rawValue }
    }

    @State private var tab: Tab = .clips
    @State private var slot: SlotRef?

    var body: some View {
        VStack(spacing: 14) {
            PreviewPane(project: project)
                .frame(maxWidth: .infinity)
                .frame(maxHeight: .infinity)
                .layoutPriority(1)
            EditorTimeline(project: project) { slot = SlotRef(index: $0) }
                .padding(.horizontal, 20)
            Picker("Edit", selection: $tab) {
                ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
            Group {
                switch tab {
                case .clips: ClipsPanel(project: project) { slot = SlotRef(index: $0) }
                case .text: TextPanel(project: project)
                case .sound: SoundPanel(project: project)
                }
            }
            .frame(height: 190, alignment: .top)
        }
        .padding(.top, 4)
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle(project.template.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Export") {
                    guard model.exporting == nil else { return }
                    Log.export.notice("export tapped")
                    project.suspend()
                    model.exporting = ExportJob(projectID: project.id)
                }
                .fontWeight(.semibold)
                .tint(Theme.accent)
                .disabled(project.previewError != nil)
                .accessibilityIdentifier("export-button")
            }
        }
        .task {
            if project.player.currentItem == nil { project.refresh() }
        }
        .sheet(item: $slot) { ref in
            SlotSheet(project: project, segmentIndex: ref.index)
                .presentationDetents([.medium, .large])
        }
        .onDisappear { project.player.pause() }
    }
}

struct SlotRef: Identifiable {
    let index: Int
    var id: Int { index }
}

// MARK: - Preview

struct PreviewPane: View {
    let project: ReelProject

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            let w = min(geo.size.width - 40, h * 9 / 16)
            let ph = w * 16 / 9
            ZStack {
                PlayerLayerView(player: project.player)
                CaptionOverlay(project: project, width: w)
                if project.isBuilding && project.player.currentItem == nil {
                    ProgressView().tint(.white)
                }
                if let error = project.previewError {
                    VStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill").font(.title2)
                        Text(error).font(.footnote).multilineTextAlignment(.center)
                    }
                    .foregroundStyle(Theme.text2)
                    .padding(24)
                }
                PlayBadge(project: project)
            }
            .frame(width: w, height: ph)
            .background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.stroke))
            .contentShape(Rectangle())
            .onTapGesture { project.togglePlay() }
            .frame(width: geo.size.width, height: h)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Reel preview")
            .accessibilityHint(project.isPlaying ? "Double-tap to pause" : "Double-tap to play")
            .accessibilityAddTraits([.isButton, .startsMediaSession])
            .accessibilityIdentifier("preview")
        }
    }
}

private struct PlayBadge: View {
    let project: ReelProject

    var body: some View {
        if !project.isPlaying && project.previewError == nil && project.player.currentItem != nil {
            Image(systemName: "play.fill")
                .scaledFont(28, .bold, relativeTo: .title)
                .foregroundStyle(.white)
                .frame(width: 70, height: 70)
                .background(Circle().fill(.black.opacity(0.45)))
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
        }
    }
}

/// Captions drawn over the live preview with the same view the export renders.
private struct CaptionOverlay: View {
    let project: ReelProject
    let width: CGFloat

    var body: some View {
        let time = project.currentTime
        GeometryReader { geo in
            ForEach(project.captions.filter { $0.shows(at: time) }) { caption in
                CaptionView(caption: caption, frameWidth: width)
                    .position(x: geo.size.width / 2, y: geo.size.height * caption.position.y)
            }
        }
        .allowsHitTesting(false)
        // Part of the video picture, sized to the frame like the export; the Text tab edits them.
        .accessibilityHidden(true)
    }
}

struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer
    var gravity: AVLayerVideoGravity = .resizeAspect

    final class LayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }

    func makeUIView(context: Context) -> LayerView {
        let view = LayerView()
        view.backgroundColor = .black
        view.playerLayer.player = player
        view.playerLayer.videoGravity = gravity
        return view
    }

    func updateUIView(_ view: LayerView, context: Context) {
        if view.playerLayer.player !== player { view.playerLayer.player = player }
    }
}

// MARK: - Timeline

/// The reel as coloured cuts (one colour per clip). Drag to scrub, tap a cut to edit it.
struct EditorTimeline: View {
    let project: ReelProject
    let onSelect: (Int) -> Void

    var body: some View {
        GeometryReader { geo in
            EditDNAView(template: project.template, height: 44, playhead: project.currentTime, showsBeats: true, showsCaptions: false, plan: project.plan)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if project.isPlaying { project.togglePlay() }
                            project.seek(to: time(at: value.location.x, width: geo.size.width))
                        }
                        .onEnded { value in
                            guard abs(value.translation.width) < 6 else { return }
                            let t = time(at: value.location.x, width: geo.size.width)
                            if let seg = project.plan.segments.first(where: { t >= $0.start && t < $0.end }) {
                                onSelect(seg.index)
                            }
                        }
                )
        }
        .frame(height: 53)
        .accessibilityElement()
        .accessibilityLabel("Timeline, \(project.plan.segments.count) cuts")
        .accessibilityValue(project.currentTime.secondsLabel)
        .accessibilityAdjustableAction { direction in
            let step = project.template.duration / 20
            let t = project.currentTime + (direction == .increment ? step : -step)
            project.seek(to: min(max(0, t), project.template.duration - 0.05))
        }
        .accessibilityIdentifier("timeline")
    }

    private func time(at x: CGFloat, width: CGFloat) -> Double {
        let d = project.template.duration
        return min(max(0, Double(x / max(width, 1)) * d), max(0, d - 0.04))
    }
}

// MARK: - Panels

private struct ClipsPanel: View {
    @Bindable var project: ReelProject
    let onSelect: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Order", selection: $project.arrangement) {
                Text("Best match").tag(Arrangement.smart)
                Text("Your order").tag(Arrangement.order)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(Array(project.clips.enumerated()), id: \.element.id) { i, clip in
                        Button {
                            if let seg = project.plan.segments.first(where: { $0.clipIndex == i }) { onSelect(seg.index) }
                        } label: {
                            ClipThumb(clip: clip, color: EditDNAView.clipColor(i), uses: project.plan.segments.filter { $0.clipIndex == i }.count)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(clip.isPhoto ? "Clip \(i + 1), photo" : "Clip \(i + 1), \(clip.duration.secondsLabel)")
                        .accessibilityIdentifier("clip-\(i)")
                    }
                }
                .padding(.horizontal, 20)
            }
            .scrollIndicators(.hidden)
            Text("Tap a clip or a cut to choose which moment plays.")
                .font(.footnote)
                .foregroundStyle(Theme.text2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 20)
        }
    }
}

struct ClipThumb: View {
    let clip: ClipAsset
    let color: Color
    var uses = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            thumbnail
            Text((clip.isPhoto ? "Photo" : clip.duration.secondsLabel) + (uses > 1 ? " · \(uses)×" : ""))
                .font(.caption.monospacedDigit())
                .foregroundStyle(Theme.text2)
                .fixedSize()
        }
    }

    private var thumbnail: some View {
        ZStack(alignment: .bottomLeading) {
            if let thumb = clip.thumbnail {
                Image(decorative: thumb, scale: 1)
                    .resizable()
                    .scaledToFill()
            } else {
                Theme.raised
            }
        }
        .frame(width: 62, height: 96)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(color, lineWidth: 3))
    }
}

private struct TextPanel: View {
    @Bindable var project: ReelProject
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if !project.captions.isEmpty {
                    let current = project.captions.first?.style ?? .clean
                    let layout = dynamicTypeSize.isAccessibilitySize
                        ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                        : AnyLayout(HStackLayout(spacing: 8))
                    layout {
                        ForEach(CaptionStyle.allCases) { style in
                            Button(style.label) {
                                for i in project.captions.indices { project.captions[i].style = style }
                            }
                            .buttonStyle(PillButtonStyle(filled: style == current))
                            .accessibilityAddTraits(style == current ? .isSelected : [])
                            .accessibilityLabel("\(style.label) captions")
                        }
                    }
                }
                ForEach($project.captions) { $caption in
                    HStack(spacing: 10) {
                        TextField("Write a caption", text: $caption.text, axis: .vertical)
                            .lineLimit(1...3)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.raised))
                            .accessibilityIdentifier("caption-field")
                        Menu {
                            Picker("Position", selection: $caption.position) {
                                Text("Top").tag(Template.Position.top)
                                Text("Middle").tag(Template.Position.middle)
                                Text("Bottom").tag(Template.Position.bottom)
                            }
                            Picker("Size", selection: $caption.size) {
                                Text("Small").tag(Template.Size.small)
                                Text("Medium").tag(Template.Size.medium)
                                Text("Large").tag(Template.Size.large)
                            }
                            Button("Jump to it", systemImage: "arrow.right.to.line") { project.seek(to: caption.start) }
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                project.captions.removeAll { $0.id == caption.id }
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .frame(width: 40, height: 40)
                                .background(Circle().fill(Theme.raised))
                        }
                        .accessibilityLabel("Caption options")
                    }
                }
                Button {
                    let start = min(project.currentTime, max(0, project.template.duration - 1))
                    project.captions.append(Caption(text: "", start: start, end: min(project.template.duration, start + 2.5), position: .middle, size: .medium, style: project.captions.first?.style ?? .clean))
                } label: {
                    Label("Add a caption here", systemImage: "plus")
                }
                .buttonStyle(PillButtonStyle())
                .accessibilityIdentifier("add-caption")
            }
            .padding(.horizontal, 20)
        }
        .scrollDismissesKeyboard(.interactively)
    }
}

private struct SoundPanel: View {
    @Bindable var project: ReelProject

    private var soundNote: String {
        switch project.sound {
        case .beat: "A beat Twincut makes for this edit. It hits on every beat the cuts follow, and it's yours to post anywhere."
        case .clips: "Keeps the sound recorded with each clip."
        case .off: "Exports without sound, so you can add a song in the app you post to."
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Sound", selection: $project.sound) {
                if project.beat != nil {
                    Text("Beat").tag(SoundMode.beat)
                }
                Text("Clips").tag(SoundMode.clips)
                Text("Off").tag(SoundMode.off)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("sound-picker")
            Text(soundNote)
                .font(.subheadline)
                .foregroundStyle(Theme.text2)
                .fixedSize(horizontal: false, vertical: true)
            if let bpm = project.template.tempo?.bpm {
                Label("Cut to \(Int(bpm.rounded())) BPM", systemImage: "metronome")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.text3)
            }
        }
        .padding(.horizontal, 20)
    }
}

// MARK: - Slot sheet

/// One cut of the reel: which moment of its clip plays, how it's framed, and which clip it is.
struct SlotSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var project: ReelProject
    let segmentIndex: Int

    @State private var replacement: PhotosPickerItem?
    @State private var replacing = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            if project.plan.segments.indices.contains(segmentIndex) {
                content(project.plan.segments[segmentIndex])
            } else {
                ContentUnavailableView("This cut changed", systemImage: "scissors")
            }
        }
    }

    private func content(_ seg: Segment) -> some View {
        let clip = project.clip(for: seg)
        let length = clip.isPhoto ? StillVideo.length : clip.duration
        let latest = max(0, length - seg.sourceDuration)
        return ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 14) {
                    ClipThumb(clip: clip, color: EditDNAView.clipColor(seg.clipIndex))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Cut \(seg.index + 1) of \(project.plan.segments.count)").font(.headline)
                        Text("\(seg.duration.secondsLabel) from clip \(seg.clipIndex + 1)")
                            .font(.subheadline)
                            .foregroundStyle(Theme.text2)
                        if seg.sourceDuration < seg.duration - 0.01 {
                            Text("Slowed down to fill the cut")
                                .font(.caption)
                                .foregroundStyle(Theme.text3)
                        }
                    }
                }

                if !clip.isPhoto && latest > 0.05 {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel(text: "Moment")
                        Slider(value: Binding(
                            get: { seg.sourceStart },
                            set: { project.setSourceStart($0, forSegment: seg.index) }
                        ), in: 0...latest) { editing in
                            if !editing { project.seek(to: seg.start) }
                        }
                        .accessibilityLabel("Where this cut starts in the clip")
                        .accessibilityValue(seg.sourceStart.secondsLabel)
                        HStack {
                            Text("Starts at \(seg.sourceStart.secondsLabel)")
                            Spacer()
                            Text("of \(length.secondsLabel)")
                        }
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Theme.text3)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel(text: "Framing")
                    Picker("Framing", selection: Binding(
                        get: { clip.fill },
                        set: { project.setFill($0, forClip: seg.clipIndex) }
                    )) {
                        Text("Fill the frame").tag(FillMode.fill)
                        Text("Show it all").tag(FillMode.fit)
                    }
                    .pickerStyle(.segmented)
                }

                VStack(spacing: 10) {
                    PhotosPicker(selection: $replacement, matching: .any(of: [.videos, .images]), preferredItemEncoding: .current) {
                        Label(replacing ? "Adding…" : "Replace this clip", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(replacing)
                    if project.clips.count > 1 {
                        HStack(spacing: 10) {
                            Button("Move earlier") { move(seg.clipIndex, by: -1) }
                                .disabled(replacing || seg.clipIndex == 0)
                            Button("Move later") { move(seg.clipIndex, by: 1) }
                                .disabled(replacing || seg.clipIndex == project.clips.count - 1)
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    }
                }
                if let error {
                    Text(error).font(.footnote).foregroundStyle(Theme.danger)
                }
            }
            .padding(20)
        }
        .background(Theme.surface.ignoresSafeArea())
        .navigationTitle("Edit cut")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
        }
        .onChange(of: replacement) { _, item in
            guard let item else { return }
            replacement = nil
            replacing = true
            error = nil
            let target = project.clip(for: seg).id
            Task {
                do {
                    let clip = try await ClipImporter.importClip(item)
                    project.replace(clip: target, with: clip)
                } catch {
                    self.error = error.localizedDescription
                }
                replacing = false
            }
        }
    }

    private func move(_ clip: Int, by delta: Int) {
        project.moveClip(from: clip, to: clip + delta)
        dismiss()
    }
}
