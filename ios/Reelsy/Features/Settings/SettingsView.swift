import SwiftUI

enum Links {
    static let privacy = URL(string: "https://twincut.pages.dev/privacy")!
    static let terms = URL(string: "https://twincut.pages.dev/terms")!
    static let support = URL(string: "https://twincut.pages.dev/support")!
    static let email = URL(string: "mailto:hergienterprises@gmail.com?subject=Twincut%20support")!
}

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @AppStorage("onboarded") private var onboarded = true

    @State private var cacheBytes: Int64 = 0
    @State private var confirmDelete = false
    @State private var showHowTo = false

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button("What can I copy?") { showHowTo = true }
                    Button("Show the welcome again") {
                        dismiss()
                        onboarded = false
                    }
                }

                Section {
                    Text("Twincut edits on this device. Videos are read here and never uploaded; a link to a video file is downloaded only to be read, then deleted. Your templates are saved on this device only.")
                        .font(.footnote)
                        .foregroundStyle(Theme.text2)
                } header: {
                    Text("Privacy")
                }

                Section("Storage") {
                    Button {
                        Storage.sweep(olderThan: 0)
                        cacheBytes = Self.cacheSize()
                    } label: {
                        LabeledContent("Clear imported clips", value: ByteCountFormatter.string(fromByteCount: cacheBytes, countStyle: .file))
                    }
                    if !model.library.templates.isEmpty {
                        Button("Delete all my templates", role: .destructive) { confirmDelete = true }
                    }
                }

                Section("Help") {
                    Link("Support", destination: Links.support)
                    Link("Email us", destination: Links.email)
                    Link("Privacy policy", destination: Links.privacy)
                    Link("Terms of use", destination: Links.terms)
                }

                Section("Credits") {
                    Text("The sample clips are from Pexels, used under the Pexels License. Filmed by Ben Prater, Yura Forrat, Cagri Kanmaz, Ne Hayaldesin, Wagner Silva, RonaK PitambeR ChoudharY, Burak Elci and Nui MALAMA.")
                        .font(.footnote)
                        .foregroundStyle(Theme.text2)
                }

                Section {
                    LabeledContent("Version", value: version)
                } footer: {
                    Text("Only post reels you have the right to use. Twincut copies an edit's timing, never its footage or sound.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg.ignoresSafeArea())
            .tint(Theme.accent)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .onAppear { cacheBytes = Self.cacheSize() }
            .sheet(isPresented: $showHowTo) { WhatToCopyView() }
            .confirmationDialog("Delete all your templates?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete all", role: .destructive) {
                    for t in model.library.templates { model.library.delete(t.id) }
                }
            } message: {
                Text("Starter templates stay. This can't be undone.")
            }
        }
    }

    private static func cacheSize() -> Int64 {
        let fm = FileManager.default
        var total: Int64 = 0
        for dir in [Storage.clips, Storage.renders] {
            let files = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey])) ?? []
            for file in files {
                total += Int64((try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
            }
        }
        return total
    }
}
