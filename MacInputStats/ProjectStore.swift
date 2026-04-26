import Foundation
import SwiftUI

@MainActor
final class ProjectStore: ObservableObject {
    @Published private(set) var projects: [Project] = []

    #if DEBUG
    private let userDefaultsKey = "InputStats.projects.v1.dev"
    #else
    private let userDefaultsKey = "InputStats.projects.v1"
    #endif

    init() { load() }

    var hasProjects: Bool { !projects.isEmpty }

    var assignedAppNames: Set<String> {
        projects.reduce(into: Set<String>()) { $0.formUnion($1.appNames) }
    }

    func add(_ project: Project) {
        projects.append(project)
        save()
    }

    func update(_ project: Project) {
        guard let idx = projects.firstIndex(where: { $0.id == project.id }) else { return }
        projects[idx] = project
        save()
    }

    func delete(id: UUID) {
        projects.removeAll { $0.id == id }
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(projects) {
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let decoded = try? JSONDecoder().decode([Project].self, from: data) else { return }
        projects = decoded
    }
}
