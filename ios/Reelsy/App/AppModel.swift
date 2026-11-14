import Observation
import SwiftUI

enum Route: Hashable {
    case template(String)
    case editor(UUID)
}

struct ExportJob: Identifiable {
    let id = UUID()
    let projectID: UUID
}

@MainActor
@Observable
final class AppModel {
    var path: [Route] = []
    /// The project being exported. Presented from the root so the cover isn't tied to a pushed screen.
    var exporting: ExportJob?
    let library: Library
    private(set) var projects: [UUID: ReelProject] = [:]

    init(library: Library? = nil) {
        self.library = library ?? Library()
    }

    func open(_ template: Template) {
        path.append(.template(template.id))
    }

    func startProject(template: Template, clips: [ClipAsset]) {
        let project = ReelProject(template: template, clips: clips)
        projects[project.id] = project
        path.append(.editor(project.id))
    }

    func closeProject(_ id: UUID) {
        projects[id]?.stop()
        projects[id] = nil
    }

    /// Drops projects whose editor is no longer on the navigation stack.
    func pruneProjects() {
        let open = Set(path.compactMap { route -> UUID? in
            if case .editor(let id) = route { return id }
            return nil
        })
        for id in projects.keys where !open.contains(id) { closeProject(id) }
    }
}
