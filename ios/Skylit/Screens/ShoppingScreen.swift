import SwiftUI
import SkylitCore

struct ShoppingScreen: View {
    @Environment(\.theme) private var theme
    let store: FrameStore
    @State private var newName = ""
    @State private var editing: ShoppingItem?
    @State private var confirmsClear = false
    @FocusState private var addFocused: Bool

    private var items: [ShoppingItem] { store.state?.shopping ?? [] }
    private var open: [ShoppingItem] { items.filter { !$0.done } }
    private var ticked: [ShoppingItem] { items.filter(\.done) }
    private var isFull: Bool { items.count >= Limits.shoppingItems }

    var body: some View {
        Screen(title: "Shopping", store: store) {
            EmptyView()
        } content: {
            HStack(spacing: 10) {
                TextField("Add an item", text: $newName)
                    .focused($addFocused)
                    .submitLabel(.done)
                    .onSubmit(add)
                    .onChange(of: newName) { _, new in
                        if new.count > Limits.nameLength { newName = String(new.prefix(Limits.nameLength)) }
                    }
                    .modifier(PanelField())
                IconButton(symbol: "plus", label: "Add item", filled: true, action: add)
                    .disabled(Limits.cleanName(newName) == nil || isFull)
                    .opacity(Limits.cleanName(newName) == nil || isFull ? 0.45 : 1)
            }
            if isFull {
                Text("The list holds up to \(Limits.shoppingItems) items. Clear some first.").textStyle(.caption).foregroundStyle(theme.muted)
            }
            if items.isEmpty {
                Card {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("The list is empty").textStyle(.heading).foregroundStyle(theme.ink)
                        Text("Anything you add here shows on the frame straight away.").textStyle(.caption).foregroundStyle(theme.muted)
                    }
                }
            }
            if !open.isEmpty {
                section("To buy", open)
            }
            if !ticked.isEmpty {
                section("In the basket", ticked)
                Button("Clear \(ticked.count) completed") { confirmsClear = true }
                    .buttonStyle(SecondaryButtonStyle())
                    .confirmationDialog("Remove every ticked item from the list?", isPresented: $confirmsClear, titleVisibility: .visible) {
                        Button("Clear completed", role: .destructive) {
                            Task { await store.clearDoneItems() }
                        }
                    }
            }
        }
        .animation(Motion.settle, value: items)
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

    @ViewBuilder private func section(_ title: String, _ rows: [ShoppingItem]) -> some View {
        Eyebrow(text: "\(title) · \(rows.count)").padding(.top, 6)
        Card(padding: 0) {
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { Divider().overlay(theme.line).padding(.leading, 56) }
                    HStack(spacing: 0) {
                        Button {
                            Task { await store.setItem(id: item.id, done: !item.done) }
                        } label: {
                            CheckCircle(isOn: item.done)
                                .frame(width: 56, height: 60)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .sensoryFeedback(.selection, trigger: item.done)
                        .accessibilityLabel(item.done ? "Untick \(item.name)" : "Tick \(item.name)")
                        Button {
                            editing = item
                        } label: {
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name)
                                        .textStyle(.body)
                                        .foregroundStyle(item.done ? theme.muted : theme.ink)
                                        .strikethrough(item.done, color: theme.muted)
                                        .multilineTextAlignment(.leading)
                                    if !item.note.isEmpty {
                                        Text(item.note).textStyle(.caption).foregroundStyle(theme.muted).lineLimit(2)
                                    }
                                }
                                Spacer()
                                if item.qty > 1 {
                                    Text("×\(item.qty)")
                                        .textStyle(.label)
                                        .foregroundStyle(theme.ink)
                                        .monospacedDigit()
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(theme.soft, in: Capsule())
                                }
                            }
                            .padding(.trailing, 16)
                            .padding(.vertical, 8)
                            .frame(minHeight: 60)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Edits this item")
                    }
                }
            }
        }
    }
}

private struct PanelField: ViewModifier {
    @Environment(\.theme) private var theme

    func body(content: Content) -> some View {
        content
            .textStyle(.body)
            .foregroundStyle(theme.ink)
            .padding(.horizontal, 16)
            .frame(minHeight: Metrics.controlHeight)
            .background(theme.panel, in: RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous).strokeBorder(theme.line, lineWidth: 1))
    }
}

struct ItemEditor: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    let store: FrameStore
    let item: ShoppingItem
    @State private var name = ""
    @State private var qty = 1
    @State private var note = ""

    var body: some View {
        SheetScaffold(title: "Edit item", canConfirm: Limits.cleanName(name) != nil, onConfirm: save) {
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    FieldLabel(text: "Item")
                    TextField("Milk", text: $name)
                        .fieldStyle()
                        .onChange(of: name) { _, new in
                            if new.count > Limits.nameLength { name = String(new.prefix(Limits.nameLength)) }
                        }
                    Stepper(value: $qty, in: Limits.quantity) {
                        HStack {
                            Text("Quantity").textStyle(.body).foregroundStyle(theme.ink)
                            Spacer()
                            Text("\(qty)").textStyle(.heading).foregroundStyle(theme.ink).monospacedDigit()
                        }
                    }
                    .padding(.vertical, 6)
                    FieldLabel(text: "Note")
                    TextField("Brand, size, shop", text: $note)
                        .fieldStyle()
                        .onChange(of: note) { _, new in
                            if new.count > Limits.nameLength { note = String(new.prefix(Limits.nameLength)) }
                        }
                }
            }
            Button("Delete item") {
                Task { await store.deleteItem(id: item.id) }
                dismiss()
            }
            .buttonStyle(SecondaryButtonStyle(destructive: true))
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
