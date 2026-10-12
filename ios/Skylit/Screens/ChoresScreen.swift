import SwiftUI
import SkylitCore

struct ChoresScreen: View {
    @Environment(\.theme) private var theme
    let store: FrameStore
    @State private var showsEverything = false
    @State private var editor: ChoreEditor.Target?
    @State private var showsPeople = false

    private var state: FrameState { store.state ?? FrameState(rev: 0) }

    var body: some View {
        Screen(title: "Chores", store: store) {
            IconButton(symbol: "person.2", label: "People") { showsPeople = true }
            IconButton(symbol: "plus", label: "Add chore", filled: true) { editor = .new }
        } content: {
            Picker("View", selection: $showsEverything) {
                Text("Today").tag(false)
                Text("All chores").tag(true)
            }
            .pickerStyle(.segmented)
            if state.chores.isEmpty {
                empty
            } else if showsEverything {
                everything
            } else if let today = store.today {
                todayView(today)
            }
        }
        .sheet(item: $editor) { target in
            ChoreEditor(store: store, target: target).environment(\.theme, theme)
        }
        .sheet(isPresented: $showsPeople) {
            PeopleSheet(store: store).environment(\.theme, theme)
        }
        .onAppear {
            #if DEBUG
            if Demo.scrollAnchor == "all" { showsEverything = true }
            if Demo.scrollAnchor == "editor", let chore = state.chores.first { editor = .existing(chore) }
            if Demo.scrollAnchor == "people" { showsPeople = true }
            #endif
        }
    }

    private var empty: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("No chores yet").textStyle(.heading).foregroundStyle(theme.ink)
                Text("Add the jobs your household shares. They appear on the frame for everyone to tick off.")
                    .textStyle(.caption)
                    .foregroundStyle(theme.muted)
                Button("Add a chore") { editor = .new }.buttonStyle(PrimaryButtonStyle())
            }
        }
    }

    @ViewBuilder private func todayView(_ today: TodayChores) -> some View {
        Card {
            HStack(spacing: 18) {
                ProgressRing(progress: today.progress, label: "\(today.doneCount)/\(today.total)")
                VStack(alignment: .leading, spacing: 4) {
                    Text(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                        .textStyle(.caption)
                        .foregroundStyle(theme.muted)
                    Text(summary(today)).textStyle(.heading).foregroundStyle(theme.ink)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(today.doneCount) of \(today.total) chores done today")
        }
        ForEach(today.groups) { group in
            Card(padding: 0) {
                VStack(spacing: 0) {
                    groupHeader(group.person, detail: "\(group.doneCount)/\(group.chores.count)")
                    ForEach(group.chores) { status in
                        Divider().overlay(theme.line).padding(.leading, 16)
                        TodayRow(status: status, tint: group.person.map { Color(hex: $0.color) }) {
                            Task { await store.setChore(id: status.chore.id, done: !status.isDone) }
                        }
                    }
                }
            }
        }
    }

    private func summary(_ today: TodayChores) -> String {
        if today.total == 0 { return "Nothing due today" }
        if today.doneCount == today.total { return "All done for today" }
        let left = today.total - today.doneCount
        return left == 1 ? "1 chore to go" : "\(left) chores to go"
    }

    private func groupHeader(_ person: Person?, detail: String) -> some View {
        HStack(spacing: 12) {
            Avatar(person: person)
            Text(person?.name ?? "Anyone").textStyle(.heading).foregroundStyle(theme.ink)
            Spacer()
            Text(detail).textStyle(.caption).foregroundStyle(theme.muted).monospacedDigit()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    @ViewBuilder private var everything: some View {
        let known = Set(state.people.map(\.id))
        let groups: [(Person?, [Chore])] = state.people.map { person in (person, state.chores.filter { $0.personId == person.id }) }
            + [(nil, state.chores.filter { $0.personId.map { !known.contains($0) } ?? true })]
        ForEach(groups.filter { !$0.1.isEmpty }, id: \.0?.id) { person, chores in
            Card(padding: 0) {
                VStack(spacing: 0) {
                    groupHeader(person, detail: chores.count == 1 ? "1 chore" : "\(chores.count) chores")
                    ForEach(chores) { chore in
                        Divider().overlay(theme.line).padding(.leading, 16)
                        Button {
                            editor = .existing(chore)
                        } label: {
                            HStack(spacing: 12) {
                                ChoreGlyph(emoji: chore.emoji)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(chore.title).textStyle(.body).foregroundStyle(theme.ink)
                                    Text(ChoreLogic.daysSummary(chore.days)).textStyle(.caption).foregroundStyle(theme.muted)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(theme.muted)
                            }
                            .padding(.horizontal, 16)
                            .frame(minHeight: 60)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

struct ChoreGlyph: View {
    @Environment(\.theme) private var theme
    let emoji: String

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.soft.opacity(0.6))
            if emoji.isEmpty {
                Image(systemName: "sparkle").font(.system(size: 14, weight: .semibold)).foregroundStyle(theme.muted)
            } else {
                Text(emoji).font(.system(size: 19))
            }
        }
        .frame(width: 36, height: 36)
        .accessibilityHidden(true)
    }
}

private struct TodayRow: View {
    @Environment(\.theme) private var theme
    let status: ChoreStatus
    let tint: Color?
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 12) {
                ChoreGlyph(emoji: status.chore.emoji)
                Text(status.chore.title)
                    .textStyle(.body)
                    .foregroundStyle(status.isDone ? theme.muted : theme.ink)
                    .strikethrough(status.isDone, color: theme.muted)
                    .multilineTextAlignment(.leading)
                Spacer()
                CheckCircle(isOn: status.isDone, tint: tint)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 60)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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

    private var existing: Chore? {
        if case .existing(let chore) = target { return chore }
        return nil
    }

    private var people: [Person] { store.state?.people ?? [] }

    var body: some View {
        SheetScaffold(title: existing == nil ? "New chore" : "Edit chore", canConfirm: Limits.cleanName(title) != nil, onConfirm: save) {
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    FieldLabel(text: "What needs doing")
                    HStack(spacing: 10) {
                        TextField("🙂", text: $emoji)
                            .multilineTextAlignment(.center)
                            .frame(width: 34)
                            .fieldStyle()
                            .onChange(of: emoji) { _, new in
                                if new.count > 1 { emoji = String(new.suffix(1)) }
                            }
                            .accessibilityLabel("Emoji")
                        TextField("Make bed", text: $title)
                            .fieldStyle()
                            .onChange(of: title) { _, new in
                                if new.count > Limits.nameLength { title = String(new.prefix(Limits.nameLength)) }
                            }
                    }
                }
            }
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    FieldLabel(text: "Who does it")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            personChip(nil)
                            ForEach(people) { personChip($0) }
                        }
                    }
                }
            }
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    FieldLabel(text: "Which days")
                    HStack(spacing: 6) {
                        ForEach(0..<7, id: \.self) { day in
                            let isOn = days.contains(day)
                            Button {
                                if isOn { days.remove(day) } else { days.insert(day) }
                            } label: {
                                Text(String(ChoreLogic.dayNames[day].prefix(1)))
                                    .textStyle(.label)
                                    .foregroundStyle(isOn ? theme.accentInk : theme.ink)
                                    .frame(maxWidth: .infinity, minHeight: Metrics.touch)
                                    .background(isOn ? theme.accent : theme.soft.opacity(0.6), in: Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(ChoreLogic.dayNames[day])
                            .accessibilityAddTraits(isOn ? .isSelected : [])
                        }
                    }
                    Text(ChoreLogic.daysSummary(Array(days))).textStyle(.caption).foregroundStyle(theme.muted)
                }
            }
            if let existing {
                Button("Delete chore") { confirmsDelete = true }
                    .buttonStyle(SecondaryButtonStyle(destructive: true))
                    .confirmationDialog("Delete “\(existing.title)”?", isPresented: $confirmsDelete, titleVisibility: .visible) {
                        Button("Delete", role: .destructive) {
                            Task { await store.deleteChore(id: existing.id) }
                            dismiss()
                        }
                    }
            }
        }
        .onAppear {
            guard let existing else { return }
            title = existing.title
            emoji = existing.emoji
            personId = people.contains { $0.id == existing.personId } ? existing.personId : nil
            days = Set(existing.days)
        }
    }

    private func personChip(_ person: Person?) -> some View {
        let isOn = personId == person?.id
        return Button {
            personId = person?.id
        } label: {
            HStack(spacing: 8) {
                Avatar(person: person, size: 26)
                Text(person?.name ?? "Anyone").textStyle(.label).foregroundStyle(theme.ink)
            }
            .padding(.leading, 6)
            .padding(.trailing, 14)
            .frame(minHeight: Metrics.touch)
            .background(isOn ? theme.soft : .clear, in: Capsule())
            .overlay(Capsule().strokeBorder(isOn ? theme.accent : theme.line, lineWidth: isOn ? 2 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
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
    @Environment(\.theme) private var theme
    let store: FrameStore
    @State private var editor: PersonEditor.Target?

    private var people: [Person] { store.state?.people ?? [] }

    var body: some View {
        SheetScaffold(title: "People") {
            if people.isEmpty {
                Text("Add the people who share chores. Each gets a colour on the frame.")
                    .textStyle(.caption)
                    .foregroundStyle(theme.muted)
            } else {
                Card(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(people.enumerated()), id: \.element.id) { index, person in
                            if index > 0 { Divider().overlay(theme.line).padding(.leading, 64) }
                            Button {
                                editor = .existing(person)
                            } label: {
                                HStack(spacing: 12) {
                                    Avatar(person: person)
                                    Text(person.name).textStyle(.body).foregroundStyle(theme.ink)
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(theme.muted)
                                }
                                .padding(.horizontal, 16)
                                .frame(minHeight: 60)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            Button("Add a person") { editor = .new }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(people.count >= Limits.people)
            if people.count >= Limits.people {
                Text("The frame holds up to \(Limits.people) people.").textStyle(.caption).foregroundStyle(theme.muted)
            }
        }
        .sheet(item: $editor) { target in
            PersonEditor(store: store, target: target).environment(\.theme, theme)
        }
    }
}

struct PersonEditor: View {
    enum Target: Identifiable {
        case new
        case existing(Person)

        var id: String {
            if case .existing(let person) = self { return person.id }
            return "new"
        }
    }

    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    let store: FrameStore
    let target: Target
    @State private var name = ""
    @State private var color = Palettes.swatches[0]
    @State private var confirmsDelete = false

    private var existing: Person? {
        if case .existing(let person) = target { return person }
        return nil
    }

    var body: some View {
        SheetScaffold(title: existing == nil ? "New person" : "Edit person", canConfirm: Limits.cleanName(name) != nil, onConfirm: save) {
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    FieldLabel(text: "Name")
                    TextField("Maya", text: $name)
                        .textContentType(.givenName)
                        .fieldStyle()
                        .onChange(of: name) { _, new in
                            if new.count > Limits.nameLength { name = String(new.prefix(Limits.nameLength)) }
                        }
                    FieldLabel(text: "Colour").padding(.top, 6)
                    SwatchPicker(selection: $color)
                }
            }
            if let existing {
                Button("Remove person") { confirmsDelete = true }
                    .buttonStyle(SecondaryButtonStyle(destructive: true))
                    .confirmationDialog("Remove \(existing.name)? Their chores stay and become anyone's.", isPresented: $confirmsDelete, titleVisibility: .visible) {
                        Button("Remove", role: .destructive) {
                            Task { await store.deletePerson(id: existing.id) }
                            dismiss()
                        }
                    }
            }
        }
        .onAppear {
            guard let existing else { return }
            name = existing.name
            color = existing.color
        }
        .presentationDetents([.medium, .large])
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
