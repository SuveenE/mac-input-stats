import SwiftUI

struct SettingsView: View {
    @ObservedObject var categoryStore: CategoryStore
    @ObservedObject var store: StatsStore
    var onClose: (() -> Void)?

    @State private var editingCategoryId: UUID?
    @State private var draftName: String = ""
    @State private var draftApps: Set<String> = []
    @State private var isAddingNew: Bool = false

    @AppStorage("showInputStats") private var showInputStats = true
    @AppStorage("showAITools") private var showAITools = true
    @AppStorage("showTopApps") private var showTopApps = true
    @AppStorage("showCategories") private var showCategories = true
    @AppStorage("showTrends") private var showTrends = true

    var body: some View {
        VStack(spacing: 12) {
            header
            Text("Categorize your apps by adding them to a category to see category-level stats.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            categoryList
            if !isAddingNew && editingCategoryId == nil {
                addButton
            }
            Divider().padding(.horizontal, 0)
            customizeSection
            Divider().padding(.horizontal, 0)
            permissionsLink
        }
        .padding(16)
        .frame(width: 302)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color.black.opacity(0.5), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
        .animation(.easeInOut(duration: 0.2), value: categoryStore.categories)
        .animation(.easeInOut(duration: 0.2), value: editingCategoryId)
        .animation(.easeInOut(duration: 0.2), value: isAddingNew)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button {
                onClose?()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.primary.opacity(0.6))
                    .frame(width: 22, height: 22)
                    .background(.primary.opacity(0.12), in: Circle())
            }
            .buttonStyle(.plain)
            Spacer()
            Text("Categories")
                .font(.headline)
            Spacer()
            Color.clear.frame(width: 22, height: 22)
        }
    }

    // MARK: - Category List

    private var categoryList: some View {
        VStack(spacing: 8) {
            if categoryStore.categories.isEmpty && !isAddingNew {
                Text("Group apps into categories to see combined stats.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 8)
            }

            ForEach(categoryStore.categories) { category in
                if editingCategoryId == category.id {
                    categoryEditor(existingId: category.id)
                } else {
                    categoryCard(category)
                }
            }

            if isAddingNew {
                categoryEditor(existingId: nil)
            }
        }
    }

    private func categoryCard(_ category: AppCategory) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "folder.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.blue)
                Text(category.name)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Spacer()
                Button {
                    beginEditing(category)
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.primary.opacity(0.45))
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                Button {
                    categoryStore.delete(id: category.id)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.red.opacity(0.6))
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
            }

            if !category.appNames.isEmpty {
                appChips(category.appNames.sorted())
            }
        }
        .padding(10)
        .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func appChips(_ apps: [String]) -> some View {
        FlowLayout(spacing: 4) {
            ForEach(apps, id: \.self) { app in
                Text(app)
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.blue.opacity(0.1), in: Capsule())
                    .foregroundStyle(.blue)
            }
        }
    }

    // MARK: - Editor

    private func categoryEditor(existingId: UUID?) -> some View {
        let assignedToOthers = otherAssignedApps(excluding: existingId)
        let availableApps = store.allAppNames.sorted()

        return VStack(alignment: .leading, spacing: 8) {
            TextField("Category name", text: $draftName)
                .textFieldStyle(.roundedBorder)
                .font(.body)

            if !availableApps.isEmpty {
                Text("Select apps")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)

                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(availableApps, id: \.self) { app in
                            appToggleRow(app: app, assignedToOthers: assignedToOthers, excludingId: existingId)
                        }
                    }
                }
                .frame(maxHeight: 200)
            }

            Divider()

            editorButtons(existingId: existingId)
        }
        .padding(10)
        .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func appToggleRow(app: String, assignedToOthers: Set<String>, excludingId: UUID?) -> some View {
        let isAssignedElsewhere = assignedToOthers.contains(app)
        let isSelected = draftApps.contains(app)

        return Button {
            if isSelected {
                draftApps.remove(app)
            } else {
                draftApps.insert(app)
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 13))
                    .foregroundStyle(isSelected ? .blue : .primary.opacity(0.3))
                Text(app)
                    .font(.body)
                    .foregroundStyle(.primary.opacity(isAssignedElsewhere ? 0.3 : 1))
                Spacer()
                if isAssignedElsewhere {
                    Text(categoryNameForApp(app, excluding: excludingId))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isAssignedElsewhere)
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
    }

    private func editorButtons(existingId: UUID?) -> some View {
        HStack {
            Button("Cancel") {
                cancelEditing()
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .font(.subheadline)

            Spacer()

            Button("Save") {
                saveCategory(existingId: existingId)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.blue)
            .font(.subheadline.weight(.medium))
            .disabled(draftName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    // MARK: - Add Button

    private var addButton: some View {
        Button {
            draftName = ""
            draftApps = []
            isAddingNew = true
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 12))
                Text("Add Category")
                    .font(.subheadline.weight(.medium))
            }
            .foregroundStyle(.blue)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Customize

    private var customizeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Customize")
                .font(.headline)

            VStack(spacing: 4) {
                sectionToggle("Input Stats", isOn: $showInputStats)
                sectionToggle("Time AI Worked for You", isOn: $showAITools)
                sectionToggle("Top Apps", isOn: $showTopApps)
                sectionToggle("Screen Time by Category", isOn: $showCategories)
                sectionToggle("Trends", isOn: $showTrends)
            }
        }
    }

    private func sectionToggle(_ label: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(label)
                .font(.body)
        }
        .toggleStyle(.checkbox)
    }

    // MARK: - Permissions

    private var permissionsLink: some View {
        Button {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
                NSWorkspace.shared.open(url)
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 10))
                Text("Permissions")
                    .font(.caption)
            }
            .foregroundStyle(.primary.opacity(0.45))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func beginEditing(_ category: AppCategory) {
        draftName = category.name
        draftApps = category.appNames
        editingCategoryId = category.id
        isAddingNew = false
    }

    private func cancelEditing() {
        editingCategoryId = nil
        isAddingNew = false
        draftName = ""
        draftApps = []
    }

    private func saveCategory(existingId: UUID?) {
        let trimmed = draftName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        if let id = existingId, var existing = categoryStore.categories.first(where: { $0.id == id }) {
            existing.name = trimmed
            existing.appNames = draftApps
            categoryStore.update(existing)
        } else {
            let category = AppCategory(name: trimmed, appNames: draftApps)
            categoryStore.add(category)
        }
        cancelEditing()
    }

    private func otherAssignedApps(excluding categoryId: UUID?) -> Set<String> {
        categoryStore.categories
            .filter { $0.id != categoryId }
            .reduce(into: Set<String>()) { $0.formUnion($1.appNames) }
    }

    private func categoryNameForApp(_ app: String, excluding categoryId: UUID?) -> String {
        categoryStore.categories
            .first { $0.id != categoryId && $0.appNames.contains(app) }?
            .name ?? ""
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(in: proposal.width ?? 0, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(in: bounds.width, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func layout(in width: CGFloat, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxWidth = max(maxWidth, x)
        }

        return (CGSize(width: maxWidth, height: y + rowHeight), positions)
    }
}
