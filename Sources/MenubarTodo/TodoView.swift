import SwiftUI

struct TodoView: View {
    @ObservedObject var store: TodoStore
    @ObservedObject var updater: Updater
    @State private var draft = ""
    @State private var dragging: UUID?
    @State private var dragY: CGFloat = 0
    @State private var grabOffset: CGFloat = 0
    @State private var rowHeights: [UUID: CGFloat] = [:]
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
                            let isDragging = dragging == item.id
                            TodoRow(item: item, isGoal: isGoal, store: store)
                                .background(GeometryReader { g in
                                    Color.clear.preference(key: RowHeightsKey.self, value: [item.id: g.size.height])
                                })
                                .background(isDragging ? Color.white : Color.clear)
                                .shadow(color: .black.opacity(isDragging ? 0.12 : 0), radius: 4, y: 1)
                                .offset(y: isDragging ? dragY - grabOffset - layoutMinY(item.id) : 0)
                                .zIndex(isDragging ? 1 : 0)
                                // The dragged row tracks the cursor exactly; only the others animate.
                                .transaction { if isDragging { $0.animation = nil } }
                                .gesture(reorderGesture(item.id), including: isGoal || store.editingID == item.id ? .subviews : .all)
                        }
                    }
                    .coordinateSpace(name: "list")
                    .onPreferenceChange(RowHeightsKey.self) { rowHeights = $0 }
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

extension TodoView {
    /// Where a row sits in the list given the current order (computed from row
    /// heights rather than measured, so it's correct the instant the order changes).
    private func layoutMinY(_ id: UUID) -> CGFloat {
        var y: CGFloat = 0
        for item in store.orderedItems {
            if item.id == id { return y }
            y += rowHeights[item.id] ?? 0
        }
        return y
    }

    /// Drag a row up or down; it swaps with a neighbour once the cursor passes that neighbour's middle.
    private func reorderGesture(_ id: UUID) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named("list"))
            .onChanged { value in
                if dragging != id {
                    dragging = id
                    grabOffset = value.startLocation.y - layoutMinY(id)
                }
                dragY = value.location.y

                let order = store.orderedItems.map(\.id)
                guard let from = order.firstIndex(of: id) else { return }
                for (index, other) in order.enumerated() where other != id && other != store.goalID {
                    let mid = layoutMinY(other) + (rowHeights[other] ?? 0) / 2
                    if (index > from && value.location.y > mid) || (index < from && value.location.y < mid) {
                        withAnimation(.easeInOut(duration: 0.15)) { store.move(id, toPositionOf: other) }
                        break
                    }
                }
            }
            .onEnded { _ in
                withAnimation(.easeOut(duration: 0.15)) { dragging = nil }
            }
    }
}

private struct RowHeightsKey: PreferenceKey {
    static let defaultValue: [UUID: CGFloat] = [:]
    static func reduce(value: inout [UUID: CGFloat], nextValue: () -> [UUID: CGFloat]) {
        value.merge(nextValue()) { $1 }
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
