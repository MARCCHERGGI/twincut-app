import Foundation
import Observation

/// The user's templates (newest first) plus the starters that ship with the app.
@MainActor
@Observable
final class Library {
    private(set) var templates: [Template] = []
    let starters: [Template]

    @ObservationIgnored private let file: URL

    init(file: URL = Storage.support.appendingPathComponent("templates.json"), bundle: Bundle = .main) {
        self.file = file
        let urls = (bundle.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? [])
            .filter { $0.lastPathComponent.hasPrefix("starter-") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        starters = urls.compactMap { try? Template.decode(from: Data(contentsOf: $0)) }
        if let data = try? Data(contentsOf: file) {
            do {
                templates = try Template.decodeList(from: data)
            } catch {
                // Keep the user's file for recovery instead of saving an empty list over it.
                Log.library.error("templates.json unreadable, set aside: \(String(describing: error), privacy: .public)")
                let aside = file.deletingLastPathComponent()
                    .appendingPathComponent("templates-unreadable-\(Int(Date().timeIntervalSince1970)).json")
                try? FileManager.default.moveItem(at: file, to: aside)
            }
        }
    }

    func template(id: String) -> Template? {
        templates.first { $0.id == id } ?? starters.first { $0.id == id }
    }

    func isStarter(_ id: String) -> Bool { starters.contains { $0.id == id } }

    func add(_ template: Template) {
        templates.removeAll { $0.id == template.id }
        templates.insert(template, at: 0)
        save()
    }

    func rename(_ id: String, to title: String) {
        guard let i = templates.firstIndex(where: { $0.id == id }) else { return }
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        templates[i].title = String(clean.prefix(40))
        save()
    }

    func delete(_ id: String) {
        templates.removeAll { $0.id == id }
        save()
        BeatSynth.removeTracks(for: id)
    }

    private func save() {
        do {
            try JSONEncoder.reelsy.encode(templates).write(to: file, options: .atomic)
        } catch {
            Log.library.error("templates not saved: \(String(describing: error), privacy: .public)")
        }
    }
}
