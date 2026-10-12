import SwiftUI
import SkylitCore

struct ShoppingScreen: View {
    @Environment(\.theme) private var theme
    let store: FrameStore
    @State private var newName = ""
    @State private var editing: ShoppingItem?
    @State private var confirmsClear = false
    @State private var removed: ShoppingItem?
    @FocusState private var addFocused: Bool

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
                        ForEach(open) { row($0) }
                    } header: {
                        SectionHeader("To buy", count: "\(open.count)")
                    }
                }
                if !ticked.isEmpty {
                    Section {
                        ForEach(ticked) { row($0) }
                    } header: {
                        SectionHeader("In the basket") {
                            Button("Clear completed") { confirmsClear = true }
                        }
                    }
                }
            }
            .stateAnimation(items)
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
        .sheet(item: $editing) { item in
            ItemEditor(store: store, item: item).environment(\.theme, theme)
        }
        .onAppear {
            #if DEBUG
            if Demo.scrollAnchor == "editor" { editing = items.dropFirst().first }
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
        removed = item
        Task { await store.deleteItem(id: item.id) }
    }

    private func row(_ item: ShoppingItem) -> some View {
        Button {
            Task { await store.setItem(id: item.id, done: !item.done) }
        } label: {
            RowLabel(title: item.name, subtitle: item.note, isDimmed: item.done) {
                DoneMark(isOn: item.done)
            } trailing: {
                if item.qty > 1 { RowValue(text: "×\(item.qty)") }
            }
        }
        .buttonStyle(RowButtonStyle())
        .sensoryFeedback(.success, trigger: item.done) { _, done in done }
        .accessibilityLabel(item.qty > 1 ? "\(item.name), \(item.qty)" : item.name)
        .accessibilityValue(item.done ? "In the basket" : "To buy")
        .accessibilityHint(item.done ? "Moves back to the list" : "Marks as bought")
        .swipeActions(edge: .leading) {
            Button("Edit", systemImage: "pencil") { editing = item }.tint(theme.tint)
        }
        .swipeActions(edge: .trailing) {
            Button("Delete", systemImage: "trash", role: .destructive) { remove(item) }
        }
        .contextMenu {
            Button("Edit", systemImage: "pencil") { editing = item }
            Button(item.done ? "Put Back" : "Mark Bought", systemImage: item.done ? "arrow.uturn.backward" : "checkmark") {
                Task { await store.setItem(id: item.id, done: !item.done) }
            }
            Button("Delete", systemImage: "trash", role: .destructive) { remove(item) }
        }
    }
}

struct ItemEditor: View {
    @Environment(\.dismiss) private var dismiss
    let store: FrameStore
    let item: ShoppingItem
    @State private var name = ""
    @State private var qty = 1
    @State private var note = ""

    var body: some View {
        NavigationStack {
            ThemedList {
                Section {
                    TextField("Item", text: $name)
                        .onChange(of: name) { _, new in
                            if new.count > Limits.nameLength { name = String(new.prefix(Limits.nameLength)) }
                        }
                    Stepper(value: $qty, in: Limits.quantity) {
                        LabeledContent("Quantity", value: "\(qty)")
                    }
                    TextField("Note", text: $note, prompt: Text("Brand, size, shop"))
                        .onChange(of: note) { _, new in
                            if new.count > Limits.nameLength { note = String(new.prefix(Limits.nameLength)) }
                        }
                }
                Section {
                    Button("Delete Item", role: .destructive) {
                        Task { await store.deleteItem(id: item.id) }
                        dismiss()
                    }
                }
            }
            .navigationTitle("Edit Item")
            .navigationBarTitleDisplayMode(.inline)
            .editorToolbar(canConfirm: Limits.cleanName(name) != nil, onConfirm: save)
        }
        .onAppear {
            name = item.name
            qty = item.qty
            note = item.note
        }
        .presentationDetents([.medium, .large])
    }

    private func save() {
        guard let clean = Limits.cleanName(name) else { return }
        let draft = ShoppingDraft(name: clean, qty: qty, note: note.trimmingCharacters(in: .whitespacesAndNewlines))
        Task { await store.updateItem(id: item.id, draft) }
    }
}
