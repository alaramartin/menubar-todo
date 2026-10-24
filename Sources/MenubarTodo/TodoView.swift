import AppKit
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
    /// The text while it's being edited, so the row grows as you type.
    @State private var editText = ""
    /// Where the title was clicked, to put the caret there.
    @State private var clickPoint: CGPoint?
    /// Bumped by a double click, which selects the whole title.
    @State private var selectAllRequest = 0

    private var editing: Bool { store.editingID == item.id }

    var body: some View {
        // Top-aligned so the checkbox, star and ✕ sit on a long title's first line.
        HStack(alignment: .top, spacing: 8) {
            Button { store.toggle(item.id) } label: {
                Image(systemName: item.done ? "checkmark.square.fill" : "square")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.gray)
                    .frame(height: TitleField.lineHeight)
            }
            .buttonStyle(.plain)

            // One click edits with the caret where you clicked; the field itself takes clicks only while editing.
            TitleField(title: item.title, text: $editText, editing: editing, clickPoint: clickPoint,
                       selectAllRequest: selectAllRequest,
                       font: .systemFont(ofSize: 13, weight: isGoal ? .semibold : .regular),
                       done: item.done, onCommit: commitEdit)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture(coordinateSpace: .local) { location in
                    // A fast double click's second click can arrive here before the field has taken focus.
                    if (NSApp.currentEvent?.clickCount ?? 1) >= 2 { selectAllRequest += 1 }
                    guard !editing else { return }
                    clickPoint = location
                    editText = item.title
                    store.editingID = item.id
                }

            // Star = "this is my top goal". Always visible on the goal, on hover otherwise.
            Button { store.toggleGoal(item.id) } label: {
                Image(systemName: isGoal ? "star.fill" : "star")
                    .font(.system(size: 12))
                    .foregroundStyle(isGoal ? Color.orange : Color.secondary)
                    .frame(height: TitleField.lineHeight)
            }
            .buttonStyle(.plain)
            .help(isGoal ? "Remove as top goal" : "Set as top goal")
            .opacity(isGoal || hovering ? 1 : 0)

            Button { store.delete(item.id) } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(height: TitleField.lineHeight)
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

    private func commitEdit(_ text: String) {
        store.rename(item.id, to: text)
        if store.editingID == item.id { store.editingID = nil }
    }
}

/// A row's title: wraps onto as many lines as it needs, and edits in place, growing as you type.
private struct TitleField: NSViewRepresentable {
    let title: String
    @Binding var text: String
    let editing: Bool
    let clickPoint: CGPoint?
    let selectAllRequest: Int
    let font: NSFont
    let done: Bool
    let onCommit: (String) -> Void

    /// Height of one line of a title, for lining the row's buttons up with the first line.
    static let lineHeight: CGFloat = {
        let cell = NSTextFieldCell(textCell: "A")
        cell.font = .systemFont(ofSize: 13)
        return ceil(cell.cellSize.height)
    }()

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> TitleTextField {
        let field = TitleTextField(wrappingLabelWithString: "")
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.appearance = NSAppearance(named: .aqua) // the popup is always light
        field.cell?.wraps = true
        field.cell?.isScrollable = false
        field.maximumNumberOfLines = 0
        field.lineBreakMode = .byWordWrapping
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ field: TitleTextField, context: Context) {
        context.coordinator.parent = self
        if !editing, field.currentEditor() != nil {
            // Editing was cancelled (Escape): drop the changes. This has to come before isEditable = false,
            // which would save them.
            context.coordinator.cancelled = true
            field.abortEditing()
            context.coordinator.cancelled = false
        }
        field.font = font
        field.interactive = editing
        field.isEditable = editing
        field.isSelectable = editing

        if editing {
            if let editor = field.currentEditor() as? NSTextView {
                context.coordinator.applySelectAll(editor)
                return
            }
            guard !context.coordinator.focusing else { return }
            field.attributedStringValue = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: NSColor.labelColor])
            // Focus after this update: ending another row's edit changes the store.
            context.coordinator.focusing = true
            let point = clickPoint
            DispatchQueue.main.async {
                context.coordinator.focusing = false
                guard let window = field.window, field.currentEditor() == nil, window.makeFirstResponder(field),
                      let editor = field.currentEditor() as? NSTextView else { return }
                if context.coordinator.applySelectAll(editor) { return }
                var location = (editor.string as NSString).length
                if let point {
                    let inField = NSPoint(x: point.x, y: field.isFlipped ? point.y : field.bounds.height - point.y)
                    location = editor.characterIndexForInsertion(at: editor.convert(inField, from: field))
                }
                editor.setSelectedRange(NSRange(location: location, length: 0))
            }
        } else {
            var attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: done ? NSColor.secondaryLabelColor : NSColor.labelColor,
            ]
            if done { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            field.attributedStringValue = NSAttributedString(string: title, attributes: attributes)
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView field: TitleTextField, context: Context) -> CGSize? {
        let width = proposal.width ?? 200
        func height(_ string: String) -> CGFloat {
            let cell = NSTextFieldCell(textCell: string)
            cell.font = font
            cell.wraps = true
            cell.lineBreakMode = .byWordWrapping
            return cell.cellSize(forBounds: NSRect(x: 0, y: 0, width: width, height: .greatestFiniteMagnitude)).height
        }
        let h = max(height(editing ? text : title), height("A"))
        return CGSize(width: width, height: ceil(h))
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: TitleField
        var cancelled = false
        var focusing = false
        private var appliedSelectAll = 0

        /// Selects the whole title if a double click asked for it since the last time.
        @discardableResult
        func applySelectAll(_ editor: NSTextView) -> Bool {
            guard parent.selectAllRequest != appliedSelectAll else { return false }
            appliedSelectAll = parent.selectAllRequest
            editor.selectAll(nil)
            return true
        }

        init(_ parent: TitleField) {
            self.parent = parent
            appliedSelectAll = parent.selectAllRequest
        }

        func controlTextDidChange(_ note: Notification) {
            guard let field = note.object as? NSTextField else { return }
            // Titles are one line: pasted line breaks become spaces.
            if let editor = field.currentEditor() as? NSTextView, editor.string.rangeOfCharacter(from: .newlines) != nil {
                let selection = editor.selectedRanges
                editor.string = editor.string.components(separatedBy: .newlines).joined(separator: " ")
                editor.selectedRanges = selection
            }
            parent.text = field.stringValue
        }

        func controlTextDidEndEditing(_ note: Notification) {
            guard !cancelled, let field = note.object as? NSTextField else { return }
            parent.onCommit(field.stringValue)
        }

        // Return saves, including Option-Return and Control-Return (which would otherwise start a new line).
        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            let newlines = [#selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)),
                            #selector(NSResponder.insertLineBreak(_:)), #selector(NSResponder.insertParagraphSeparator(_:))]
            guard newlines.contains(selector) else { return false }
            control.window?.makeFirstResponder(nil)
            return true
        }
    }
}

/// Lets clicks through to the row (for click-to-edit and dragging) except while it's being edited.
final class TitleTextField: NSTextField {
    var interactive = false
    override func hitTest(_ point: NSPoint) -> NSView? { interactive ? super.hitTest(point) : nil }
    override var acceptsFirstResponder: Bool { interactive && super.acceptsFirstResponder }
}

/// The field editor for row titles: a double click selects the whole title rather than one word.
final class TitleFieldEditor: NSTextView {
    override func mouseDown(with event: NSEvent) {
        if event.clickCount >= 2 { selectAll(nil) } else { super.mouseDown(with: event) }
    }

    // Paste multi-line text as one line (as a normal insert, so ⌘Z undoes it).
    override func paste(_ sender: Any?) {
        guard let text = NSPasteboard.general.string(forType: .string) else { return super.paste(sender) }
        insertText(text.components(separatedBy: .newlines).joined(separator: " "), replacementRange: selectedRange())
    }
}
