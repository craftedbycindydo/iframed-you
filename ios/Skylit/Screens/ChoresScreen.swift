import SwiftUI
import SkylitCore

struct ChoresScreen: View {
    @Environment(\.theme) private var theme
    let store: FrameStore
    @State private var showsEverything = false
    @State private var newTitle = ""
    @State private var draft: ChoreEditDraft?
    @State private var showsPeople = false
    @State private var deleting: Chore?
    @FocusState private var addFocused: Bool
    @FocusState private var editField: ChoreEditDraft.Field?

    private var state: FrameState { store.state ?? FrameState(rev: 0) }
    private var people: [Person] { store.state?.people ?? [] }

    var body: some View {
        NavigationStack {
            ThemedList {
                Section {
                    InlineAddField(prompt: "Add a chore", text: $newTitle, focus: $addFocused, limit: Limits.nameLength, onSubmit: add)
                } footer: {
                    if state.chores.isEmpty {
                        Text("Chores appear on the frame for everyone to tick off. Open a chore to pick who does it and on which days.")
                    }
                }
                if state.chores.isEmpty {
                    Section {
                        ContentUnavailableView {
                            Label("No chores yet", systemImage: "checklist")
                        } description: {
                            Text("Add the jobs your household shares.")
                        }
                    }
                    .listRowBackground(Color.clear)
                } else {
                    Section {
                        Picker("View", selection: $showsEverything) {
                            Text("Today").tag(false)
                            Text("All chores").tag(true)
                        }
                        .pickerStyle(.segmented)
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                    if showsEverything {
                        everything
                    } else if let today = store.today {
                        todaySections(today)
                    }
                }
            }
            .listSectionSpacing(Space.l)
            .stateAnimation(state.chores)
            .stateAnimation(draft?.id)
            .refreshable { await store.refresh() }
            .sensoryFeedback(.selection, trigger: showsEverything)
            .onChange(of: showsEverything) { _, _ in closeEditor() }
            .screenHeader("Chores", status: store.connectionStatus, statusSymbol: store.connectionSymbol) {
                Button("People", systemImage: "person.2") { showsPeople = true }
                    .headerAction()
                Button("Add chore", systemImage: "plus") { addFocused = true }
                    .headerAction(prominent: true)
            }
            .navigationDestination(isPresented: $showsPeople) {
                PeopleScreen(store: store)
            }
        }
        .confirmationDialog("Delete “\(deleting?.title ?? "")”?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let id = deleting?.id {
                    if draft?.id == id { draft = nil }
                    Task { await store.deleteChore(id: id) }
                }
            }
        }
        .onAppear {
            #if DEBUG
            if Demo.scrollAnchor == "all" { showsEverything = true }
            if Demo.scrollAnchor == "editor", let chore = state.chores.first { openEditor(chore) }
            if Demo.scrollAnchor == "people" { showsPeople = true }
            if Demo.scrollAnchor == "add" { DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { addFocused = true } }
            #endif
        }
    }

    private func add() {
        guard let title = Limits.cleanName(newTitle) else { return }
        newTitle = ""
        addFocused = true
        Task { await store.addChore(ChoreDraft(title: title)) }
    }

    private func openEditor(_ chore: Chore) {
        save()
        draft = ChoreEditDraft(chore, people: people)
        editField = .title
    }

    private func closeEditor() {
        save()
        editField = nil
        draft = nil
    }

    private func save() {
        guard let draft, let clean = Limits.cleanName(draft.title), let chore = state.chores.first(where: { $0.id == draft.id }) else { return }
        let changed = ChoreDraft(title: clean, emoji: draft.emoji, personId: draft.personId, days: draft.days.sorted())
        guard changed != ChoreDraft(title: chore.title, emoji: chore.emoji, personId: chore.personId, days: chore.days.sorted()) else { return }
        Task { await store.updateChore(id: draft.id, changed) }
    }

    private func bind<T>(_ path: WritableKeyPath<ChoreEditDraft, T>, _ fallback: T) -> Binding<T> {
        Binding(get: { draft?[keyPath: path] ?? fallback }, set: { value in draft?[keyPath: path] = value })
    }

    @ViewBuilder private func todaySections(_ today: TodayChores) -> some View {
        Section {
            ProgressSummary(done: today.doneCount, total: today.total,
                            caption: Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()),
                            headline: summary(today))
        }
        ForEach(today.groups) { group in
            Section {
                ForEach(group.chores) { status in
                    TodayRow(status: status, tint: group.person.map { Color(hex: $0.color) }, isEditing: draft?.id == status.chore.id) {
                        Task { await store.setChore(id: status.chore.id, done: !status.isDone) }
                    } edit: {
                        if draft?.id == status.chore.id { closeEditor() } else { openEditor(status.chore) }
                    }
                    .swipeActions(edge: .trailing) {
                        Button("Edit", systemImage: "pencil") { openEditor(status.chore) }
                    }
                    .contextMenu {
                        Button("Edit", systemImage: "pencil") { openEditor(status.chore) }
                        Button("Delete", systemImage: "trash", role: .destructive) { deleting = status.chore }
                    }
                    if draft?.id == status.chore.id { editor(status.chore) }
                }
            } header: {
                SectionHeader(group.person?.name ?? "Anyone", person: group.person, showsAvatar: true,
                              count: "\(group.doneCount)/\(group.chores.count)")
            }
        }
    }

    private func summary(_ today: TodayChores) -> String {
        if today.total == 0 { return "Nothing due today" }
        if today.doneCount == today.total { return "All done for today" }
        let left = today.total - today.doneCount
        return left == 1 ? "1 chore to go" : "\(left) chores to go"
    }

    @ViewBuilder private var everything: some View {
        let known = Set(state.people.map(\.id))
        let groups: [(Person?, [Chore])] = state.people.map { person in (person, state.chores.filter { $0.personId == person.id }) }
            + [(nil, state.chores.filter { $0.personId.map { !known.contains($0) } ?? true })]
        ForEach(groups.filter { !$0.1.isEmpty }, id: \.0?.id) { person, chores in
            Section {
                ForEach(chores) { chore in
                    let isEditing = draft?.id == chore.id
                    Button {
                        if isEditing { closeEditor() } else { openEditor(chore) }
                    } label: {
                        RowLabel(chore.title, subtitle: ChoreLogic.daysSummary(chore.days), emoji: chore.emoji) {
                            RowDisclosure(isExpanded: isEditing) {
                                if isEditing { closeEditor() } else { openEditor(chore) }
                            }
                            .accessibilityHidden(true)
                        }
                    }
                    .buttonStyle(RowButtonStyle())
                    .accessibilityValue(isEditing ? "Expanded" : "Collapsed")
                    .accessibilityHint(isEditing ? "Hides the editing controls" : "Shows the editing controls")
                    .swipeActions(edge: .trailing) {
                        Button("Delete", systemImage: "trash", role: .destructive) { deleting = chore }
                    }
                    .contextMenu {
                        Button("Edit", systemImage: "pencil") { openEditor(chore) }
                        Button("Delete", systemImage: "trash", role: .destructive) { deleting = chore }
                    }
                    if isEditing { editor(chore) }
                }
            } header: {
                SectionHeader(person?.name ?? "Anyone", person: person, showsAvatar: true,
                              count: chores.count == 1 ? "1 chore" : "\(chores.count) chores")
            }
        }
    }

    @ViewBuilder private func editor(_ chore: Chore) -> some View {
        HStack(spacing: Space.m) {
            TextField("🙂", text: bind(\.emoji, ""))
                .multilineTextAlignment(.center)
                .frame(width: Size.glyph + Space.s)
                .focused($editField, equals: .emoji)
                .onChange(of: draft?.emoji) { _, new in
                    if let new, new.count > 1 { draft?.emoji = String(new.suffix(1)) }
                }
                .accessibilityLabel("Emoji")
            Divider()
            TextField("What needs doing", text: bind(\.title, ""))
                .focused($editField, equals: .title)
                .submitLabel(.done)
                .onSubmit(closeEditor)
                .onChange(of: draft?.title) { _, new in
                    if let new, new.count > Limits.nameLength { draft?.title = String(new.prefix(Limits.nameLength)) }
                }
            Button(action: closeEditor) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(theme.tint)
                    .frame(width: Size.touch, height: Size.touch)
            }
            .buttonStyle(RowButtonStyle())
            .accessibilityLabel("Finish editing")
        }
        .inlineEditorRow()
        Picker("Who does it", selection: bind(\.personId, nil)) {
            Text("Anyone").tag(String?.none)
            ForEach(people) { person in
                Text(person.name).tag(String?.some(person.id))
            }
        }
        .pickerStyle(.menu)
        .onChange(of: draft?.personId) { _, _ in save() }
        .inlineEditorRow()
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(spacing: Space.xs) {
                ForEach(0..<7, id: \.self) { day in
                    let isOn = draft?.days.contains(day) ?? false
                    Button(String(ChoreLogic.dayNames[day].prefix(1))) {
                        if isOn { draft?.days.remove(day) } else { draft?.days.insert(day) }
                        save()
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.circle)
                    .tint(isOn ? theme.tint : Theme.secondaryLabel)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel(ChoreLogic.dayNames[day])
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                }
            }
            Text(ChoreLogic.daysSummary(Array(draft?.days ?? []))).font(.note).foregroundStyle(Theme.secondaryLabel)
        }
        .padding(.vertical, Space.xs)
        .stateAnimation(draft?.days)
        .inlineEditorRow()
        Button("Delete Chore", systemImage: "trash", role: .destructive) { deleting = chore }
            .inlineEditorRow()
    }
}

struct ChoreEditDraft: Equatable {
    enum Field {
        case emoji
        case title
    }

    let id: String
    var title: String
    var emoji: String
    var personId: String?
    var days: Set<Int>

    init(_ chore: Chore, people: [Person]) {
        id = chore.id
        title = chore.title
        emoji = chore.emoji
        personId = people.contains { $0.id == chore.personId } ? chore.personId : nil
        days = Set(chore.days)
    }
}

private struct TodayRow: View {
    let status: ChoreStatus
    let tint: Color?
    let isEditing: Bool
    let toggle: () -> Void
    let edit: () -> Void

    var body: some View {
        Button(action: toggle) {
            RowLabel(title: status.chore.title, emoji: status.chore.emoji, isDimmed: status.isDone) {
                DoneMark(isOn: status.isDone, tint: tint)
            } trailing: {
                RowDisclosure(isExpanded: isEditing, toggle: edit)
            }
        }
        .buttonStyle(RowButtonStyle())
        .sensoryFeedback(.success, trigger: status.isDone) { _, done in done }
        .accessibilityLabel(status.chore.title)
        .accessibilityValue(status.isDone ? "Done" : "Not done")
        .accessibilityHint(status.isDone ? "Marks as not done" : "Marks as done")
        .accessibilityAction(named: isEditing ? "Finish editing" : "Edit", edit)
    }
}

struct PeopleScreen: View {
    let store: FrameStore
    @State private var addsPerson = false
    @State private var removing: Person?

    private var people: [Person] { store.state?.people ?? [] }

    var body: some View {
            ThemedList {
                Section {
                    ForEach(people) { person in
                        NavigationLink(value: person) {
                            RowLabel(title: person.name) { Avatar(person: person) } trailing: { EmptyView() }
                        }
                        .swipeActions(edge: .trailing) {
                            Button("Remove", systemImage: "trash", role: .destructive) { removing = person }
                        }
                    }
                } footer: {
                    Text(people.count >= Limits.people ? "The frame holds up to \(Limits.people) people." : "Each person gets a colour on the frame.")
                }
            }
            .overlay {
                if people.isEmpty {
                    ContentUnavailableView {
                        Label("No people yet", systemImage: "person.2")
                    } description: {
                        Text("Add the people who share chores.")
                    } actions: {
                        Button("Add a person") { addsPerson = true }.buttonStyle(.borderedProminent)
                    }
                }
            }
            .navigationTitle("People")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Person.self) { person in
                PersonEditor(store: store, target: .existing(person))
            }
            .navigationDestination(isPresented: $addsPerson) {
                PersonEditor(store: store, target: .new)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add person", systemImage: "plus") { addsPerson = true }
                        .disabled(people.count >= Limits.people)
                }
            }
            .confirmationDialog("Remove \(removing?.name ?? "")? Their chores stay and become anyone's.",
                                isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
                Button("Remove", role: .destructive) {
                    if let id = removing?.id { Task { await store.deletePerson(id: id) } }
                }
            }
    }
}

struct PersonEditor: View {
    enum Target {
        case new
        case existing(Person)
    }

    @Environment(\.dismiss) private var dismiss
    let store: FrameStore
    let target: Target
    @State private var name = ""
    @State private var color = Palettes.swatches[0]
    @State private var confirmsDelete = false
    @FocusState private var nameFocused: Bool

    private var existing: Person? {
        if case .existing(let person) = target { return person }
        return nil
    }

    var body: some View {
        ThemedList {
            Section {
                TextField("Name", text: $name)
                    .textContentType(.givenName)
                    .focused($nameFocused)
                    .submitLabel(.done)
                    .onChange(of: name) { _, new in
                        if new.count > Limits.nameLength { name = String(new.prefix(Limits.nameLength)) }
                    }
            }
            Section {
                SwatchPicker(selection: $color)
            } header: {
                SectionHeader("Colour")
            }
            if let existing {
                Section {
                    Button("Remove Person", role: .destructive) { confirmsDelete = true }
                        .confirmationDialog("Remove \(existing.name)? Their chores stay and become anyone's.", isPresented: $confirmsDelete, titleVisibility: .visible) {
                            Button("Remove", role: .destructive) {
                                Task { await store.deletePerson(id: existing.id) }
                                dismiss()
                            }
                        }
                }
            }
        }
        .navigationTitle(existing == nil ? "New Person" : "Edit Person")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    save()
                    dismiss()
                }
                .fontWeight(.semibold)
                .disabled(Limits.cleanName(name) == nil)
            }
        }
        .onAppear {
            guard let existing else {
                nameFocused = true
                return
            }
            name = existing.name
            color = existing.color
        }
    }

    private func save() {
        guard let clean = Limits.cleanName(name) else { return }
        Task {
            if let existing {
                await store.updatePerson(Person(id: existing.id, name: clean, color: color))
            } else {
                await store.addPerson(name: clean, color: color)
            }
        }
    }
}
