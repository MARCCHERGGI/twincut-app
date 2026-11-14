import AVFoundation
import StoreKit
import SwiftUI

/// Renders the reel to a 1080p MP4, then hands it to Photos or the share sheet.
struct ExportView: View {
    let spec: RenderSpec
    let sound: SoundMode
    let onDone: () -> Void
    let onKeepEditing: () -> Void

    @Environment(\.requestReview) private var requestReview
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    @State private var attempt = 0
    @State private var progress = 0.0
    @State private var output: URL?
    @State private var error: String?
    @State private var saved = false
    @State private var saving = false
    @State private var saveError: String?
    @State private var saveDenied = false
    @State private var confirmLeave = false
    @State private var player: AVQueuePlayer?
    @State private var looper: AVPlayerLooper?


    var body: some View {
        VStack(spacing: 0) {
            if let output {
                result(output)
            } else if let error {
                failure(error)
            } else {
                rendering
            }
        }
        .background(Theme.bg.ignoresSafeArea())
        .task(id: attempt) { if error == nil { await render() } }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .background, output == nil, error == nil else { return }
            Log.export.notice("export stopped: app went to the background")
            error = "The export stops when you leave Twincut. Tap Try again and keep Twincut open until it finishes."
            attempt += 1  // cancels the running render; the new task sees the error and waits
        }
        .onAppear { Log.export.notice("export screen shown") }
        .onDisappear {
            Log.export.notice("export screen closed")
            player?.pause()
            looper = nil
            player = nil
        }
    }

    // MARK: States

    private var rendering: some View {
        VStack(spacing: 26) {
            Spacer()
            ZStack {
                Circle().stroke(Theme.raised, lineWidth: 10)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.15), value: progress)
                Text("\(Int((progress * 100).rounded()))%")
                    .scaledFont(34, .bold, relativeTo: .largeTitle, digits: true)
                    .contentTransition(.numericText())
            }
            .frame(width: 150, height: 150)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Exporting")
            .accessibilityValue("\(Int((progress * 100).rounded())) percent")
            VStack(spacing: 6) {
                Text("Exporting in 1080p").font(.title3.weight(.bold))
                Text("Keep Twincut open until it's done.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.text2)
            }
            Spacer()
            Button("Cancel") { onKeepEditing() }
                .buttonStyle(SecondaryButtonStyle())
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
        }
    }

    private func failure(_ message: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "exclamationmark.triangle.fill")
                .scaledFont(40, relativeTo: .largeTitle)
                .foregroundStyle(Theme.danger)
            Text("Export didn't finish").font(.title2.weight(.bold))
            Text(message)
                .font(.body)
                .foregroundStyle(Theme.text2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
            Spacer()
            VStack(spacing: 10) {
                Button("Try again") {
                    error = nil
                    progress = 0
                    attempt += 1
                }
                .buttonStyle(PrimaryButtonStyle())
                Button("Back to editing") { onKeepEditing() }
                    .buttonStyle(SecondaryButtonStyle())
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
        }
    }

    private func result(_ url: URL) -> some View {
        VStack(spacing: 18) {
            HStack {
                Button("Edit") { onKeepEditing() }
                    .foregroundStyle(Theme.text2)
                Spacer()
                Text("Your reel").font(.headline)
                Spacer()
                Button("Done") {
                    if saved { onDone() } else { confirmLeave = true }
                }
                .font(.headline)
                .accessibilityIdentifier("done-button")
                .confirmationDialog("Leave without saving?", isPresented: $confirmLeave, titleVisibility: .visible) {
                    Button("Save to Photos") { Task { await save(); if saved { onDone() } } }
                    Button("Leave without saving", role: .destructive) { onDone() }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This reel isn't in Photos yet. Leaving closes the editor.")
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)

            GeometryReader { geo in
                let w = min(geo.size.width - 80, geo.size.height * 9 / 16)
                Group {
                    if let player {
                        PlayerLayerView(player: player)
                    } else {
                        Color.black
                    }
                }
                .frame(width: w, height: w * 16 / 9)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Theme.stroke))
                .frame(width: geo.size.width, height: geo.size.height)
                .accessibilityLabel("Finished reel, playing on a loop")
            }

            if sound == .off {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "music.note")
                        .foregroundStyle(Theme.accent)
                    Text("This reel has no sound. Add a song in the app you post it to.")
                        .font(.footnote)
                        .foregroundStyle(Theme.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 24)
            }

            HStack(spacing: 10) {
                Button {
                    Task { await save() }
                } label: {
                    Label(saved ? "Saved" : saving ? "Saving…" : "Save", systemImage: saved ? "checkmark" : "arrow.down.to.line")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(saving || saved)
                .accessibilityIdentifier("save-button")

                ShareLink(item: url) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.headline)
                        .frame(width: 52, height: 52)
                        .background(Circle().fill(Theme.raised))
                        .foregroundStyle(Theme.text)
                }
                .accessibilityLabel("Share")
            }
            .padding(.horizontal, 20)

            if let saveError {
                Text(saveError)
                    .font(.footnote)
                    .foregroundStyle(Theme.danger)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                if saveDenied, let settings = URL(string: UIApplication.openSettingsURLString) {
                    Button("Open Settings") { openURL(settings) }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                        .accessibilityIdentifier("open-settings")
                }
            }
        }
        .padding(.bottom, 12)
        .sensoryFeedback(.success, trigger: saved)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("export-done")
    }

    // MARK: Work

    private func render() async {
        let url = Storage.newRenderURL()
        UIApplication.shared.isIdleTimerDisabled = true
        // A moment to wind down if the user leaves mid-export; ended by the system if it runs out.
        nonisolated(unsafe) var background = UIBackgroundTaskIdentifier.invalid
        background = UIApplication.shared.beginBackgroundTask(withName: "export") {
            UIApplication.shared.endBackgroundTask(background)
            background = .invalid
        }
        defer {
            UIApplication.shared.isIdleTimerDisabled = false
            if background != .invalid { UIApplication.shared.endBackgroundTask(background) }
        }
        Log.export.notice("render started, \(spec.plan.segments.count) segments")
        do {
            try await Exporter.export(spec, to: url) { progress = $0 }
            try Task.checkCancellation()
            Log.export.notice("render finished")
            let item = AVPlayerItem(url: url)
            let queue = AVQueuePlayer()
            queue.isMuted = sound == .off
            looper = AVPlayerLooper(player: queue, templateItem: item)
            player = queue
            queue.play()
            withAnimation(.smooth) { output = url }
            let exports = UserDefaults.standard.integer(forKey: "exports") + 1
            UserDefaults.standard.set(exports, forKey: "exports")
            if exports == 2 {
                try? await Task.sleep(for: .seconds(2))
                if !Task.isCancelled { requestReview() }
            }
        } catch is CancellationError {
            try? FileManager.default.removeItem(at: url)
        } catch {
            Log.export.error("render failed: \(String(describing: error), privacy: .public)")
            try? FileManager.default.removeItem(at: url)
            if !Task.isCancelled { self.error = error.localizedDescription }
        }
    }

    private func save() async {
        guard !saved, !saving, let output else { return }
        saving = true
        defer { saving = false }
        do {
            saveError = nil
            saveDenied = false
            try await PhotoSaver.save(output)
            saved = true
        } catch {
            saveDenied = error is PhotoSaver.Failure
            saveError = error.localizedDescription
        }
    }
}
