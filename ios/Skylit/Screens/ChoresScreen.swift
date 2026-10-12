import SwiftUI
import SkylitCore

struct ChoresScreen: View {
    @Environment(\.theme) private var theme
    let store: FrameStore
    @State private var showsEverything = false
    @State private var editor: ChoreEditor.Target?
    @State private var showsPeople = false
    @State private var deleting: Chore?

    private var state: FrameState { store.state ?? FrameState(rev: 0) }

    var body: some View {
        NavigationStack {
            ThemedList {
                if !state.chores.isEmpty {
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
            .overlay {
                if state.chores.isEmpty {
                    ContentUnavailableView {
                        Label("No chores yet", systemImage: "checklist")
                    } description: {
                        Text("Add the jobs your household shares. They appear on the frame for everyone to tick off.")
                    } actions: {
                        Button("Add a chore") { editor = .new }.buttonStyle(.borderedProminent)
                    }
                }
            }
            .refreshable { await store.refresh() }
            .sensoryFeedback(.selection, trigger: showsEverything)
            .screenHeader("Chores", status: store.connectionStatus, statusSymbol: store.connectionSymbol) {
                Button("People", systemImage: "person.2") { showsPeople = true }
                    .headerAction()
                Button("Add chore", systemImage: "plus") { editor = .new }
                    .headerAction(prominent: true)
            }
        }
        .sheet(item: $editor) { target in
            ChoreEditor(store: store, target: target).environment(\.theme, theme)
        }
        .sheet(isPresented: $showsPeople) {
            PeopleSheet(store: store).environment(\.theme, theme)
        }
        .confirmationDialog("Delete “\(deleting?.title ?? "")”?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let id = deleting?.id { Task { await store.deleteChore(id: id) } }
            }
        }
        .onAppear {
            #if DEBUG
            if Demo.scrollAnchor == "all" { showsEverything = true }
            if Demo.scrollAnchor == "editor", let chore = state.chores.first { editor = .existing(chore) }
            if Demo.scrollAnchor == "people" { showsPeople = true }
            #endif
        }
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
                    TodayRow(status: status, tint: group.person.map { Color(hex: $0.color) }) {
                        Task { await store.setChore(id: status.chore.id, done: !status.isDone) }
                    }
                    .swipeActions(edge: .trailing) {
                        Button("Edit", systemImage: "pencil") { editor = .existing(status.chore) }
                    }
                    .contextMenu {
                        Button("Edit", systemImage: "pencil") { editor = .existing(status.chore) }
                        Button("Delete", systemImage: "trash", role: .destructive) { deleting = status.chore }
                    }
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
                    Button {
                        editor = .existing(chore)
                    } label: {
                        RowLabel(chore.title, subtitle: ChoreLogic.daysSummary(chore.days), emoji: chore.emoji) {
                            RowChevron()
                        }
                    }
                    .buttonStyle(RowButtonStyle())
                    .swipeActions(edge: .trailing) {
                        Button("Delete", systemImage: "trash", role: .destructive) { deleting = chore }
                    }
                    .contextMenu {
                        Button("Edit", systemImage: "pencil") { editor = .existing(chore) }
                        Button("Delete", systemImage: "trash", role: .destructive) { deleting = chore }
                    }
                }
            } header: {
                SectionHeader(person?.name ?? "Anyone", person: person, showsAvatar: true,
                              count: chores.count == 1 ? "1 chore" : "\(chores.count) chores")
            }
        }
    }
}

private struct TodayRow: View {
    let status: ChoreStatus
    let tint: Color?
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            RowLabel(title: status.chore.title, emoji: status.chore.emoji, isDimmed: status.isDone) {
                DoneMark(isOn: status.isDone, tint: tint)
            } trailing: {
                EmptyView()
            }
        }
        .buttonStyle(RowButtonStyle())
        .sensoryFeedback(.success, trigger: status.isDone) { _, done in done }
        .accessibilityLabel(status.chore.title)
        .accessibilityValue(status.isDone ? "Done" : "Not done")
        .accessibilityHint(status.isDone ? "Marks as not done" : "Marks as done")
    }
}

struct ChoreEditor: View {
    enum Target: Identifiable {
        case new
        case existing(Chore)

        var id: String {
            if case .existing(let chore) = self { return chore.id }
            return "new"
        }
    }

    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    let store: FrameStore
    let target: Target
    @State private var title = ""
    @State private var emoji = ""
    @State private var personId: String?
    @State private var days: Set<Int> = []
    @State private var confirmsDelete = false
    @FocusState private var titleFocused: Bool

    private var existing: Chore? {
        if case .existing(let chore) = target { return chore }
        return nil
    }

    private var people: [Person] { store.state?.people ?? [] }

    var body: some View {
        NavigationStack {
            ThemedList {
                Section {
                    HStack(spacing: Space.m) {
                        TextField("🙂", text: $emoji)
                            .multilineTextAlignment(.center)
                            .frame(width: Size.glyph + Space.s)
                            .onChange(of: emoji) { _, new in
                                if new.count > 1 { emoji = String(new.suffix(1)) }
                            }
                            .accessibilityLabel("Emoji")
                        Divider()
                        TextField("What needs doing", text: $title)
                            .focused($titleFocused)
                            .submitLabel(.done)
                            .onChange(of: title) { _, new in
                                if new.count > Limits.nameLength { title = String(new.prefix(Limits.nameLength)) }
                            }
                    }
                }
                Section {
                    Picker("Who does it", selection: $personId) {
                        Text("Anyone").tag(String?.none)
                        ForEach(people) { person in
                            Text(person.name).tag(String?.some(person.id))
                        }
                    }
                }
                Section {
                    HStack(spacing: Space.xs) {
                        ForEach(0..<7, id: \.self) { day in
                            let isOn = days.contains(day)
                            Button(String(ChoreLogic.dayNames[day].prefix(1))) {
                                if isOn { days.remove(day) } else { days.insert(day) }
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
                    .padding(.vertical, Space.xs)
                    .stateAnimation(days)
                } header: {
                    SectionHeader("Which days")
                } footer: {
                    Text(ChoreLogic.daysSummary(Array(days)))
                }
                if existing != nil {
                    Section {
                        Button("Delete Chore", role: .destructive) { confirmsDelete = true }
                    }
                }
            }
            .navigationTitle(existing == nil ? "New Chore" : "Edit Chore")
            .navigationBarTitleDisplayMode(.inline)
            .editorToolbar(canConfirm: Limits.cleanName(title) != nil, onConfirm: save)
            .confirmationDialog("Delete “\(existing?.title ?? "")”?", isPresented: $confirmsDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let existing { Task { await store.deleteChore(id: existing.id) } }
                    dismiss()
                }
            }
        }
        .onAppear {
            guard let existing else {
                titleFocused = true
                return
            }
            title = existing.title
            emoji = existing.emoji
            personId = people.contains { $0.id == existing.personId } ? existing.personId : nil
            days = Set(existing.days)
        }
    }

    private func save() {
        guard let clean = Limits.cleanName(title) else { return }
        let draft = ChoreDraft(title: clean, emoji: emoji, personId: personId, days: days.sorted())
        Task {
            if let existing {
                await store.updateChore(id: existing.id, draft)
            } else {
                await store.addChore(draft)
            }
        }
    }
}

struct PeopleSheet: View {
    @Environment(\.dismiss) private var dismiss
    let store: FrameStore
    @State private var addsPerson = false
    @State private var removing: Person?

    private var people: [Person] { store.state?.people ?? [] }

    var body: some View {
        NavigationStack {
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
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
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
