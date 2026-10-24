import Foundation
import Combine

struct TodoItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var done = false
}

/// Holds the checklist and the goal, and writes them to disk on every change
/// so everything survives quitting the app and restarting the Mac.
@MainActor
final class TodoStore: ObservableObject {
    @Published var items: [TodoItem] = [] { didSet { save() } }
    /// The one item marked as the top goal (shown in the middle of the menu bar).
    @Published var goalID: UUID? { didSet { save() } }
    /// The item currently being renamed in the popup (not saved).
    @Published var editingID: UUID?

    private let fileURL: URL
    private var loading = false

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("menubar-todo", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("todos.json")
        load()
    }

    var goal: TodoItem? { items.first { $0.id == goalID } }

    /// Goal first, then everything else in the order it was added.
    var orderedItems: [TodoItem] {
        guard let goal else { return items }
        return [goal] + items.filter { $0.id != goal.id }
    }

    func add(_ title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        items.append(TodoItem(title: trimmed))
    }

    func toggle(_ id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].done.toggle()
    }

    func rename(_ id: UUID, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].title = trimmed
    }

    /// Moves an item into another item's place (used while dragging to reorder).
    func move(_ id: UUID, toPositionOf target: UUID) {
        guard id != target, target != goalID,
              let from = items.firstIndex(where: { $0.id == id }),
              let to = items.firstIndex(where: { $0.id == target }) else { return }
        items.insert(items.remove(at: from), at: to)
    }

    func delete(_ id: UUID) {
        if goalID == id { goalID = nil }
        items.removeAll { $0.id == id }
    }

    func toggleGoal(_ id: UUID) {
        goalID = (goalID == id) ? nil : id
    }

    // MARK: Persistence

    private struct Snapshot: Codable {
        var items: [TodoItem]
        var goalID: UUID?
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let snap = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        loading = true
        items = snap.items
        goalID = snap.goalID
        loading = false
    }

    private func save() {
        guard !loading else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        guard let data = try? encoder.encode(Snapshot(items: items, goalID: goalID)) else { return }
        // Atomic write so a crash or power loss mid-save can't corrupt the file.
        try? data.write(to: fileURL, options: .atomic)
    }
}
