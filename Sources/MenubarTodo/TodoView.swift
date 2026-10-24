import SwiftUI

struct TodoView: View {
    @ObservedObject var store: TodoStore
    @ObservedObject var updater: Updater
    @State private var draft = ""
    @State private var dragging: UUID?
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField("Add a task…", text: $draft)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($inputFocused)
                .onSubmit {
                    store.add(draft)
                    draft = ""
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)

            Divider()

            if store.items.isEmpty {
                Text("Nothing to do.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(store.orderedItems) { item in
                            let isGoal = item.id == store.goalID
                            TodoRow(item: item, isGoal: isGoal, store: store)
                                .onDrag {
                                    dragging = item.id
                                    return NSItemProvider(object: item.id.uuidString as NSString)
                                }
                                .onDrop(of: [.text], delegate: ReorderDropDelegate(target: item.id, dragging: $dragging, store: store))
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 360)
                .fixedSize(horizontal: false, vertical: true)
            }

            if let update = updater.available {
                Divider()
                Link("Update available: version \(update.version)", destination: update.url)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
            }
        }
        .frame(width: 280)
        .background(Color.white)
        .environment(\.colorScheme, .light)
        .onAppear { inputFocused = true }
    }
}

/// Moves the dragged row into place as it passes over other rows.
private struct ReorderDropDelegate: DropDelegate {
    let target: UUID
    @Binding var dragging: UUID?
    let store: TodoStore

    func dropEntered(info: DropInfo) {
        guard let dragging, dragging != target else { return }
        withAnimation(.easeInOut(duration: 0.15)) {
            store.move(dragging, toPositionOf: target)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }
}

private struct TodoRow: View {
    let item: TodoItem
    let isGoal: Bool
    @ObservedObject var store: TodoStore
    @State private var hovering = false
    @State private var editText = ""
    @FocusState private var editFocused: Bool

    private var editing: Bool { store.editingID == item.id }

    var body: some View {
        HStack(spacing: 8) {
            Button { store.toggle(item.id) } label: {
                Image(systemName: item.done ? "checkmark.square.fill" : "square")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.gray)
            }
            .buttonStyle(.plain)

            if editing {
                TextField("", text: $editText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: isGoal ? .semibold : .regular))
                    .focused($editFocused)
                    .onSubmit(commitEdit)
                    .onAppear {
                        editText = item.title
                        editFocused = true
                    }
                    .onChange(of: editFocused) { _, focused in
                        if !focused { commitEdit() }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(item.title)
                    .font(.system(size: 13, weight: isGoal ? .semibold : .regular))
                    .strikethrough(item.done)
                    .foregroundStyle(item.done ? .secondary : .primary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { store.editingID = item.id }
                    .help("Double-click to edit")
            }

            // Star = "this is my top goal". Always visible on the goal, on hover otherwise.
            Button { store.toggleGoal(item.id) } label: {
                Image(systemName: isGoal ? "star.fill" : "star")
                    .font(.system(size: 12))
                    .foregroundStyle(isGoal ? Color.orange : Color.secondary)
            }
            .buttonStyle(.plain)
            .help(isGoal ? "Remove as top goal" : "Set as top goal")
            .opacity(isGoal || hovering ? 1 : 0)

            Button { store.delete(item.id) } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Delete")
            .opacity(hovering ? 1 : 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(hovering ? Color.black.opacity(0.04) : Color.clear)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }

    private func commitEdit() {
        // Escape clears editingID first, which turns this into a cancel.
        guard store.editingID == item.id else { return }
        store.rename(item.id, to: editText)
        store.editingID = nil
    }
}
