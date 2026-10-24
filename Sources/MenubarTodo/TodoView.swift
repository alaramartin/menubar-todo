import SwiftUI

struct TodoView: View {
    @ObservedObject var store: TodoStore
    @State private var draft = ""
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
                            TodoRow(item: item, isGoal: item.id == store.goalID, store: store)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 360)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(width: 280)
        .background(Color.white)
        .environment(\.colorScheme, .light)
        .onAppear { inputFocused = true }
    }
}

private struct TodoRow: View {
    let item: TodoItem
    let isGoal: Bool
    @ObservedObject var store: TodoStore
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            Button { store.toggle(item.id) } label: {
                Image(systemName: item.done ? "checkmark.square.fill" : "square")
                    .font(.system(size: 14))
                    .foregroundStyle(item.done ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)

            Text(item.title)
                .font(.system(size: 13, weight: isGoal ? .semibold : .regular))
                .strikethrough(item.done)
                .foregroundStyle(item.done ? .secondary : .primary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

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
}
