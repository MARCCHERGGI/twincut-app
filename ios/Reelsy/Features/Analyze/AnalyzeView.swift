import AVFoundation
import PhotosUI
import SwiftUI

/// Where the reel to copy comes from.
enum ReelSource {
    case photos(PhotosPickerItem)
    /// A movie chosen in Files (security-scoped, copied before reading).
    case file(URL)
    /// A direct link to a video file.
    case link(VideoLink)
    /// The bundled sample reel, for anyone with no reel saved yet.
    case sample

    /// The first step's label, or nil when there's nothing to fetch.
    var fetchLabel: String? {
        switch self {
        case .photos: "Copying from Photos"
        case .file: "Copying from Files"
        case .link: "Downloading the video"
        case .sample: nil
        }
    }
}

/// Reads the chosen reel into a template, showing each stage as it really happens.
struct AnalyzeView: View {
    let source: ReelSource
    let onDone: (Template) -> Void
    let onCancel: () -> Void

    @State private var stage: AnalysisStage?
    @State private var error: String?
    @State private var attempt = 0


    var body: some View {
        VStack(spacing: 32) {
            HStack {
                Button("Cancel", action: onCancel)
                    .foregroundStyle(Theme.text2)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)

            Spacer()
            if let message = error {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .scaledFont(40, relativeTo: .largeTitle)
                        .foregroundStyle(Theme.danger)
                    Text("Couldn't read that video")
                        .font(.title2.weight(.bold))
                    Text(message)
                        .font(.body)
                        .foregroundStyle(Theme.text2)
                        .multilineTextAlignment(.center)
                    Button("Try again") {
                        error = nil
                        stage = nil
                        attempt += 1
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.top, 8)
                    Button("Back", action: onCancel)
                        .buttonStyle(SecondaryButtonStyle())
                }
                .padding(.horizontal, 28)
            } else {
                ScanningBars(active: stage != .done)
                    .frame(height: 120)
                    .padding(.horizontal, 28)
                VStack(alignment: .leading, spacing: 14) {
                    if let fetch = source.fetchLabel {
                        row(fetch, done: stage != nil, active: stage == nil)
                    }
                    ForEach(AnalysisStage.allCases.filter { $0 != .done }, id: \.self) { s in
                        row(s.label, done: (stage ?? .reading) > s, active: stage == s)
                    }
                }
                .padding(.horizontal, 36)
                Text("Everything happens on this device. The video isn't uploaded or kept.")
                    .font(.footnote)
                    .foregroundStyle(Theme.text3)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            Spacer()
        }
        .background(Theme.bg.ignoresSafeArea())
        .task(id: attempt) { if error == nil { await run() } }
        .sensoryFeedback(.success, trigger: stage == .done)
    }

    private func row(_ text: String, done: Bool, active: Bool) -> some View {
        HStack(spacing: 12) {
            ZStack {
                if done {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent)
                } else if active {
                    ProgressView().controlSize(.small).tint(Theme.text)
                } else {
                    Image(systemName: "circle").foregroundStyle(Theme.text3)
                }
            }
            .frame(width: 22)
            Text(text)
                .font(.body.weight(active ? .semibold : .regular))
                .foregroundStyle(done || active ? Theme.text : Theme.text3)
        }
        .accessibilityElement(children: .combine)
    }

    private func run() async {
        UIApplication.shared.isIdleTimerDisabled = true
        defer { UIApplication.shared.isIdleTimerDisabled = false }
        do {
            var template: Template
            switch source {
            case .photos, .file, .link:
                let url: URL
                switch source {
                case .photos(let item): url = try await ClipImporter.movieURL(item)
                case .file(let picked): url = try await ClipImporter.copyFile(picked)
                case .link(let link): url = try await LinkDownloader.download(link)
                case .sample: throw AnalysisError.noVideo
                }
                defer { try? FileManager.default.removeItem(at: url) }
                template = try await ReferenceAnalyzer.analyze(url: url) { stage = $0 }
                // Keep each caption's timing, place and size; the words are the creator's, the user writes their own.
                for i in template.texts.indices { template.texts[i].text = "" }
            case .sample:
                guard let url = Bundle.main.url(forResource: "sample-reel", withExtension: "mp4") else { throw AnalysisError.noVideo }
                template = try await ReferenceAnalyzer.analyze(url: url) { stage = $0 }
                template.id = "sample-reel"  // reading it again replaces it rather than adding a copy
                template.title = "Sample reel"
            }
            if !Task.isCancelled { onDone(template) }
        } catch is CancellationError {
            return
        } catch {
            Log.analysis.error("analysis failed: \(String(describing: error), privacy: .public)")
            let interrupted = (error as NSError).code == AVError.operationInterrupted.rawValue
            withAnimation {
                self.error = interrupted
                    ? "Reading stopped when Twincut left the screen. Tap Try again and keep Twincut open."
                    : error.localizedDescription
            }
        }
    }
}

struct ScanningBars: View {
    let active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let colors: [Color] = ([0xE4FF3A, 0x5EE0FF, 0xFF6BA8, 0xB28CFF, 0xFFB547, 0x4DF0A8, 0xFF7A59, 0x8FB3FF] as [UInt32]).map { Color(hex: $0) }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !active || reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 4) {
                ForEach(0..<16, id: \.self) { i in
                    let wave = 0.5 + 0.5 * sin(t * 3 + Double(i) * 0.55)
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(colors[i % colors.count])
                        .frame(height: 30 + 90 * wave)
                        .opacity(0.4 + 0.6 * wave)
                }
            }
            .frame(maxHeight: .infinity)
        }
        .accessibilityHidden(true)
    }
}

struct WhatToCopyView: View {
    @Environment(\.dismiss) private var dismiss

    private let steps: [(app: String, icon: String, text: String)] = [
        ("Your own videos", "person.crop.square", "Any video in Photos or Files works: your posts, drafts and edits."),
        ("Someone else's video", "person.2", "Only when you have the right to use it, like a creator who shares an edit for others to use."),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(steps, id: \.app) { step in
                        Card {
                            HStack(alignment: .top, spacing: 14) {
                                Image(systemName: step.icon)
                                    .font(.title3)
                                    .foregroundStyle(Theme.accent)
                                    .frame(width: 28)
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(step.app).font(.headline)
                                    Text(step.text)
                                        .font(.subheadline)
                                        .foregroundStyle(Theme.text2)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                    Text("Twincut keeps the timing, colours and where captions sit. It keeps none of the video, its sound or its caption words.")
                        .font(.footnote)
                        .foregroundStyle(Theme.text3)
                        .padding(.top, 6)
                }
                .padding(20)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("What can I copy?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.large])
    }
}
