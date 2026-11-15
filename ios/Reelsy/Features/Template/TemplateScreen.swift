import PhotosUI
import SwiftUI

struct TemplateScreen: View {
    @Environment(AppModel.self) private var model
    let templateID: String

    var body: some View {
        if let template = model.library.template(id: templateID) {
            TemplateView(template: template)
        } else {
            ContentUnavailableView("This template was deleted", systemImage: "rectangle.stack.badge.minus")
                .background(Theme.bg.ignoresSafeArea())
        }
    }
}

/// A template laid open: its edit as a strip, its numbers, and the one choice that matters
/// before picking footage: how many clips.
struct TemplateView: View {
    @Environment(AppModel.self) private var model
    let template: Template

    @State private var count: Int?
    @State private var picked: [PhotosPickerItem] = []
    @State private var importTask: Task<Void, Never>?
    @State private var importID = UUID()
    @State private var imported = 0
    @State private var importTotal = 0
    @State private var importError: String?
    @State private var showsAllShots = false

    private var clipCount: Int { count ?? template.suggestedClips }
    private var isImporting: Bool { importTask != nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                PlayingDNA(template: template)
                stats
                clipChooser
                shots
                if !template.texts.isEmpty { captions }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 140)
        }
        .scrollIndicators(.hidden)
        .background(Theme.bg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) { actions }
        .overlay { if isImporting { importOverlay } }
        .onChange(of: picked) { _, items in
            guard !items.isEmpty else { return }
            picked = []
            startImport(items.count) { progress in
                try await ClipImporter.importClips(items, progress: progress)
            }
        }
        .alert("Couldn't add those clips", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
            Button("OK", role: .cancel) { importError = nil }
        } message: {
            Text(importError ?? "")
        }
        .onDisappear {
            importTask?.cancel()
            importTask = nil
            importID = UUID()
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(template.title)
                .scaledFont(30, .bold, relativeTo: .largeTitle)
                .fixedSize(horizontal: false, vertical: true)
            Text(model.library.isStarter(template.id) ? "Starter template" : "From a reel you picked")
                .font(.subheadline)
                .foregroundStyle(Theme.text3)
        }
    }

    private var stats: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                StatChip(text: "\(template.shots.count) shots")
                StatChip(text: template.duration.secondsLabel)
                StatChip(text: template.pace.label)
                if let bpm = template.tempo?.bpm { StatChip(text: "\(Int(bpm.rounded())) BPM") }
                if !template.beats.isEmpty, template.shots.count > 1, template.source.kind != "starter" {
                    StatChip(text: "\(Int((template.onBeat * 100).rounded()))% on beat")
                }
                if !template.texts.isEmpty { StatChip(text: template.texts.count == 1 ? "1 caption" : "\(template.texts.count) captions") }
            }
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
    }

    private var clipChooser: some View {
        Card {
            VStack(alignment: .leading, spacing: 16) {
                Text("How many clips?")
                    .font(.headline)
                HStack(spacing: 18) {
                    stepButton("minus", id: "clip-count-minus", enabled: clipCount > 1) { count = clipCount - 1 }
                    Text("\(clipCount)")
                        .scaledFont(44, .bold, relativeTo: .largeTitle, digits: true)
                        .contentTransition(.numericText())
                        .frame(minWidth: 70)
                        .accessibilityIdentifier("clip-count")
                    stepButton("plus", id: "clip-count-plus", enabled: clipCount < template.maxClips) { count = clipCount + 1 }
                    Spacer(minLength: 0)
                }
                .animation(.snappy, value: clipCount)
                .sensoryFeedback(.selection, trigger: clipCount)
                Text(countHint)
                    .font(.subheadline)
                    .foregroundStyle(Theme.text2)
                    .fixedSize(horizontal: false, vertical: true)
                EditDNAView(template: template, height: 22, showsBeats: false, showsCaptions: false,
                            plan: CutPlanner.plan(template: template, clips: Array(repeating: ClipTraits(duration: nil, framing: nil, motion: 0.5, brightness: 0.5), count: clipCount), arrangement: .order))
            }
        }
    }

    private var countHint: String {
        let shots = max(1, template.shots.count)
        let per = template.duration / Double(clipCount)
        if clipCount < shots {
            return "Clips repeat to fill all \(shots) cuts, each time from a different moment. About \(per.secondsLabel) of footage per clip."
        }
        if clipCount > shots {
            return "Longer shots split on the beat so every clip gets a turn. About \(per.secondsLabel) each."
        }
        return "One clip per cut, about \(per.secondsLabel) each. You can choose which moment of each clip plays in the editor."
    }

    private func stepButton(_ symbol: String, id: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .scaledFont(20, .bold, relativeTo: .title3)
                .frame(width: 52, height: 52)
                .background(Circle().fill(Theme.raised))
                .foregroundStyle(enabled ? Theme.text : Theme.text3)
        }
        .disabled(!enabled)
        .buttonRepeatBehavior(.enabled)
        .accessibilityLabel(symbol == "plus" ? "More clips" : "Fewer clips")
        .accessibilityIdentifier(id)
    }

    private var shots: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: "Shots")
            let list = showsAllShots ? template.shots : Array(template.shots.prefix(6))
            VStack(spacing: 0) {
                ForEach(list) { shot in
                    HStack(spacing: 14) {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color(hexString: shot.color))
                            .frame(width: 34, height: 44)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(shot.hint)
                                .font(.subheadline)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("\(shot.start.secondsLabel) · \(shot.duration.secondsLabel)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(Theme.text3)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 8)
                }
            }
            if template.shots.count > 6 {
                Button(showsAllShots ? "Show fewer" : "Show all \(template.shots.count) shots") {
                    withAnimation(.snappy) { showsAllShots.toggle() }
                }
                .buttonStyle(LinkButtonStyle())
            }
        }
    }

    private var captions: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: "Captions")
            ForEach(Array(template.texts.enumerated()), id: \.offset) { _, text in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(text.start.secondsLabel)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Theme.text3)
                        .frame(width: 44, alignment: .leading)
                    Text(text.text.isEmpty ? "Your caption" : text.text)
                        .font(.subheadline)
                        .foregroundStyle(text.text.isEmpty ? Theme.text3 : Theme.text)
                    Spacer(minLength: 0)
                }
            }
            Text("Write or change the captions in the editor.")
                .font(.footnote)
                .foregroundStyle(Theme.text3)
        }
    }

    private var actions: some View {
        VStack(spacing: 10) {
            PhotosPicker(selection: $picked, maxSelectionCount: clipCount, selectionBehavior: .ordered,
                         matching: .any(of: [.videos, .images]), preferredItemEncoding: .current) {
                Text(clipCount == 1 ? "Choose 1 clip" : "Choose \(clipCount) clips")
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("choose-clips")
            Button("Try it with sample clips") {
                let n = clipCount
                Log.library.notice("sample clips tapped: \(n)")
                startImport(n) { progress in try await ClipImporter.sampleClips(count: n, progress: progress) }
            }
            .buttonStyle(LinkButtonStyle(color: Theme.text))
            .accessibilityIdentifier("use-samples")
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(alignment: .top) {
            Theme.bg
                .overlay(alignment: .top) { Rectangle().fill(Theme.stroke).frame(height: 1) }
                .ignoresSafeArea()
        }
        .disabled(isImporting)
    }

    private var importOverlay: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
            VStack(spacing: 18) {
                ProgressView(value: Double(imported), total: Double(max(1, importTotal)))
                    .tint(Theme.accent)
                    .frame(width: 200)
                Text(importTotal > 1 ? "Adding clip \(min(imported + 1, importTotal)) of \(importTotal)" : "Adding your clip")
                    .font(.headline.monospacedDigit())
                Button("Cancel") {
                    importTask?.cancel()
                    importTask = nil
                    importID = UUID()
                    UIApplication.shared.isIdleTimerDisabled = false
                }
                .buttonStyle(PillButtonStyle())
            }
            .padding(28)
            .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Theme.surface))
        }
        .transition(.opacity)
    }

    private func startImport(_ total: Int, _ load: @escaping (@escaping @MainActor (Int) -> Void) async throws -> [ClipAsset]) {
        importTask?.cancel()
        let id = UUID()
        importID = id
        imported = 0
        importTotal = total
        UIApplication.shared.isIdleTimerDisabled = true
        importTask = Task {
            defer {
                if importID == id {
                    importTask = nil
                    UIApplication.shared.isIdleTimerDisabled = false
                }
            }
            do {
                let clips = try await load { if importID == id { imported = $0 } }
                try Task.checkCancellation()
                guard importID == id, !clips.isEmpty else {
                    Log.library.notice("import dropped: current \(importID == id), clips \(clips.count)")
                    return
                }
                Log.library.notice("import done: \(clips.count) clips, opening editor")
                model.startProject(template: template, clips: clips)
            } catch is CancellationError {
                Log.library.notice("import cancelled")
            } catch {
                Log.library.error("import failed: \(String(describing: error), privacy: .public)")
                if importID == id { importError = error.localizedDescription }
            }
        }
    }
}

/// The template strip with a playhead sweeping across it in real time, so its rhythm reads
/// at a glance.
struct PlayingDNA: View {
    let template: Template
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: max(template.duration, 0.5))
            EditDNAView(template: template, height: 72, playhead: t)
        }
    }
}
