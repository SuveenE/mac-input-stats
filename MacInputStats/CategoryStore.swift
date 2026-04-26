import Foundation
import SwiftUI

@MainActor
final class CategoryStore: ObservableObject {
    @Published private(set) var categories: [AppCategory] = []

    #if DEBUG
    private let userDefaultsKey = "InputStats.projects.v1.dev"
    #else
    private let userDefaultsKey = "InputStats.projects.v1"
    #endif

    init() { load() }

    var hasCategories: Bool { !categories.isEmpty }

    var assignedAppNames: Set<String> {
        categories.reduce(into: Set<String>()) { $0.formUnion($1.appNames) }
    }

    func add(_ category: AppCategory) {
        categories.append(category)
        save()
    }

    func update(_ category: AppCategory) {
        guard let idx = categories.firstIndex(where: { $0.id == category.id }) else { return }
        categories[idx] = category
        save()
    }

    func delete(id: UUID) {
        categories.removeAll { $0.id == id }
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(categories) {
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let decoded = try? JSONDecoder().decode([AppCategory].self, from: data) else { return }
        categories = decoded
    }
}
