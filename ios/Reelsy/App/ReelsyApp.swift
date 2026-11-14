import AVFoundation
import SwiftUI

@main
struct ReelsyApp: App {
    @State private var model: AppModel

    init() {
        // UI tests start from a clean install state.
        if ProcessInfo.processInfo.arguments.contains("-uitest-reset") {
            UserDefaults.standard.removeObject(forKey: "onboarded")
            UserDefaults.standard.removeObject(forKey: "exports")
            try? FileManager.default.removeItem(at: Storage.support.appendingPathComponent("templates.json"))
        }
        _model = State(initialValue: AppModel())
        Storage.sweep()
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("onboarded") private var onboarded = false

    var body: some View {
        @Bindable var model = model
        ZStack {
            Theme.bg.ignoresSafeArea()
            if onboarded {
                NavigationStack(path: $model.path) {
                    HomeView()
                        .navigationDestination(for: Route.self) { route in
                            switch route {
                            case .template(let id):
                                TemplateScreen(templateID: id)
                            case .editor(let id):
                                if let project = model.projects[id] {
                                    EditorView(project: project)
                                } else {
                                    ContentUnavailableView("This reel was closed", systemImage: "film")
                                }
                            }
                        }
                }
                .onChange(of: model.path) { _, _ in model.pruneProjects() }
                .fullScreenCover(item: $model.exporting) { job in
                    if let project = model.projects[job.projectID] {
                        ExportView(spec: project.spec, sound: project.sound) {
                            model.exporting = nil
                            model.path.removeAll()
                        } onKeepEditing: {
                            model.exporting = nil
                            project.resume()
                        }
                    } else {
                        ContentUnavailableView {
                            Label("This reel was closed", systemImage: "film")
                        } actions: {
                            Button("Close") { model.exporting = nil }
                                .buttonStyle(PillButtonStyle())
                        }
                        .background(Theme.bg.ignoresSafeArea())
                    }
                }
                .transition(.opacity)
            } else {
                OnboardingView { withAnimation(.easeInOut(duration: 0.35)) { onboarded = true } }
                    .transition(.opacity)
            }
        }
    }
}
