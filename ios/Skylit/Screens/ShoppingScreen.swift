import SwiftUI
import SkylitCore

struct ShoppingScreen: View {
    @Environment(\.theme) private var theme
    let store: FrameStore
    @State private var newName = ""
    @State private var draft: ItemDraft?
    @State private var confirmsClear = false
    @State private var removed: ShoppingItem?
    @FocusState private var addFocused: Bool
    @FocusState private var editField: ItemDraft.Field?

    private var items: [ShoppingItem] { store.state?.shopping ?? [] }
    private var open: [ShoppingItem] { items.filter { !$0.done } }
    private var ticked: [ShoppingItem] { items.filter(\.done) }
    private var isFull: Bool { items.count >= Limits.shoppingItems }

    var body: some View {
        NavigationStack {
            ThemedList {
                Section {
                    InlineAddField(prompt: "Add an item", text: $newName, focus: $addFocused, limit: Limits.nameLength, onSubmit: add)
                        .disabled(isFull)
                } footer: {
                    if isFull {
                        Text("The list holds up to \(Limits.shoppingItems) items.")
                    }
                }
                if items.isEmpty {
                    Section {
                        ContentUnavailableView {
                            Label("The list is empty", systemImage: "basket")
                        } description: {
                            Text("Anything you add shows on the frame straight away.")
                        }
                    }
                    .listRowBackground(Color.clear)
                }
                if !open.isEmpty {
                    Section {
                        ForEach(open) { rows($0) }
                    } header: {
                        SectionHeader("To buy", count: "\(open.count)")
                    }
                }
                if !ticked.isEmpty {
                    Section {
                        ForEach(ticked) { rows($0) }
                    } header: {
                        SectionHeader("In the basket") {
                            Button("Clear completed") { confirmsClear = true }
                        }
                    }
                }
            }
            .stateAnimation(items)
            .stateAnimation(draft?.id)
            .refreshable { await store.refresh() }
            .screenHeader("Shopping", status: store.connectionStatus, statusSymbol: store.connectionSymbol)
            .sensoryFeedback(.success, trigger: items.count) { old, new in new > old }
            .confirmationDialog("Remove every ticked item from the list?", isPresented: $confirmsClear, titleVisibility: .visible) {
                Button("Clear \(ticked.count) Completed", role: .destructive) {
                    Task { await store.clearDoneItems() }
                }
            }
        }
        .overlay(alignment: .bottom) {
            NoticeToast(notice: Binding(get: { removed.map { "Removed \($0.name)" } }, set: { if $0 == nil { removed = nil } }),
                        actionLabel: "Undo") {
                guard let item = removed else { return }
                Task { await store.addItem(ShoppingDraft(name: item.name, qty: item.qty, note: item.note)) }
            }
            .padding(.bottom, Space.s)
            .stateAnimation(removed)
        }
        .onAppear {
            #if DEBUG
            if Demo.scrollAnchor == "editor", let item = items.dropFirst().first { openEditor(item) }
            if Demo.scrollAnchor == "add" { DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { addFocused = true } }
            #endif
        }
    }

    private func add() {
        guard let name = Limits.cleanName(newName), !isFull else { return }
        newName = ""
        addFocused = true
        Task { await store.addItem(ShoppingDraft(name: name)) }
    }

    private func remove(_ item: ShoppingItem) {
        if draft?.id == item.id { draft = nil }
        removed = item
        Task { await store.deleteItem(id: item.id) }
    }

    private func openEditor(_ item: ShoppingItem) {
        save()
        draft = ItemDraft(item)
        editField = .name
    }

    private func closeEditor() {
        save()
        editField = nil
        draft = nil
    }

    private func save() {
        guard let draft, let clean = Limits.cleanName(draft.name) else { return }
        let changed = ShoppingDraft(name: clean, qty: draft.qty, note: draft.note.trimmingCharacters(in: .whitespacesAndNewlines))
        guard let item = items.first(where: { $0.id == draft.id }),
              changed != ShoppingDraft(name: item.name, qty: item.qty, note: item.note) else { return }
        Task { await store.updateItem(id: draft.id, changed) }
    }

    @ViewBuilder private func rows(_ item: ShoppingItem) -> some View {
        row(item)
        if draft?.id == item.id {
            editor
        }
    }

    private func row(_ item: ShoppingItem) -> some View {
        let isEditing = draft?.id == item.id
        return Button {
            Task { await store.setItem(id: item.id, done: !item.done) }
        } label: {
            RowLabel(title: item.name, subtitle: item.note, isDimmed: item.done) {
                DoneMark(isOn: item.done)
            } trailing: {
                if item.qty > 1 { RowValue(text: "×\(item.qty)") }
                RowDisclosure(isExpanded: isEditing) {
                    if isEditing { closeEditor() } else { openEditor(item) }
                }
            }
        }
        .buttonStyle(RowButtonStyle())
        .sensoryFeedback(.success, trigger: item.done) { _, done in done }
        .accessibilityLabel(item.qty > 1 ? "\(item.name), \(item.qty)" : item.name)
        .accessibilityValue(item.done ? "In the basket" : "To buy")
        .accessibilityHint(item.done ? "Moves back to the list" : "Marks as bought")
        .accessibilityAction(named: isEditing ? "Finish editing" : "Edit") {
            if isEditing { closeEditor() } else { openEditor(item) }
        }
        .swipeActions(edge: .leading) {
            Button("Edit", systemImage: "pencil") { openEditor(item) }.tint(theme.tint)
        }
        .swipeActions(edge: .trailing) {
            Button("Delete", systemImage: "trash", role: .destructive) { remove(item) }
        }
        .contextMenu {
            Button("Edit", systemImage: "pencil") { openEditor(item) }
            Button(item.done ? "Put Back" : "Mark Bought", systemImage: item.done ? "arrow.uturn.backward" : "checkmark") {
                Task { await store.setItem(id: item.id, done: !item.done) }
            }
            Button("Delete", systemImage: "trash", role: .destructive) { remove(item) }
        }
    }

    private func bind<T>(_ path: WritableKeyPath<ItemDraft, T>, _ fallback: T) -> Binding<T> {
        Binding(get: { draft?[keyPath: path] ?? fallback }, set: { value in draft?[keyPath: path] = value })
    }

    @ViewBuilder private var editor: some View {
        HStack(spacing: Space.m) {
            TextField("Item", text: bind(\.name, ""))
                .focused($editField, equals: .name)
                .submitLabel(.done)
                .onSubmit(closeEditor)
                .onChange(of: draft?.name) { _, new in
                    guard let new else { return }
                    if Limits.clipped(new, to: Limits.nameLength) != new { draft?.name = Limits.clipped(new, to: Limits.nameLength) }
                }
            TickButton(label: "Finish editing", action: closeEditor)
        }
        .inlineEditorRow()
        Stepper(value: bind(\.qty, 1), in: Limits.quantity) {
            LabeledContent("Quantity", value: "\(draft?.qty ?? 1)")
        }
        .onChange(of: draft?.qty) { _, _ in save() }
        .inlineEditorRow()
        TextField("Note", text: bind(\.note, ""), prompt: Text("Brand, size, shop"))
            .focused($editField, equals: .note)
            .submitLabel(.done)
            .onSubmit(closeEditor)
            .onChange(of: draft?.note) { _, new in
                guard let new else { return }
                if Limits.clipped(new, to: Limits.noteLength) != new { draft?.note = Limits.clipped(new, to: Limits.noteLength) }
            }
            .inlineEditorRow()
    }
}

struct ItemDraft: Equatable {
    enum Field {
        case name
        case note
    }

    let id: String
    var name: String
    var qty: Int
    var note: String

    init(_ item: ShoppingItem) {
        id = item.id
        name = item.name
        qty = item.qty
        note = item.note
    }
}
