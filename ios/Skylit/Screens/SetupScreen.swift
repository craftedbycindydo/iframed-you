import SwiftUI
import SkylitCore

struct SetupScreen: View {
    @Environment(FrameSession.self) private var session
    @Environment(\.theme) private var theme
    let store: FrameStore
    @State private var finder = LocationFinder()
    @State private var isLocating = false
    @State private var showsCitySearch = false
    @State private var addsCalendar = false
    @State private var calendarName = ""
    @State private var calendarColor = Palettes.swatches[5]
    @State private var calendarLink = ""
    @FocusState private var calendarNameFocused: Bool
    @State private var removingCalendar: CalendarFeed?
    @State private var confirmsUnpair = false

    private var settings: FrameSettings { store.state?.settings ?? FrameSettings() }
    private var calendars: [CalendarFeed] { store.state?.calendars ?? [] }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ThemedList {
                    location
                    appearance
                    mode
                    ICloudAlbumSection(store: store).id("icloud")
                    calendarSection.id("calendars")
                    devices.id("devices")
                    connection
                }
                .onAppear {
                    #if DEBUG
                    if let anchor = Demo.scrollAnchor {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { proxy.scrollTo(anchor == "calendarForm" ? "calendars" : anchor, anchor: .top) }
                        if anchor == "calendarForm" { addsCalendar = true }
                        if anchor == "city" { showsCitySearch = true }
                    }
                    #endif
                }
            }
            .refreshable { await store.refresh() }
            .sensoryFeedback(.selection, trigger: settings.appearance)
            .screenHeader("Frame", status: store.connectionStatus ?? store.frame.name,
                          statusSymbol: store.connectionSymbol ?? "wifi")
            .navigationDestination(isPresented: $showsCitySearch) {
                CitySearch(store: store)
            }
        }
        .task { await store.loadDevices() }
    }

    private var location: some View {
        Section {
            RowLabel("City", symbol: "mappin.and.ellipse", symbolTint: theme.tint) {
                VStack(alignment: .trailing, spacing: 2) {
                    RowValue(text: settings.location?.name ?? "Not set")
                    if let zone = settings.location?.timezone {
                        Text(zone.replacingOccurrences(of: "_", with: " ")).font(.note).foregroundStyle(Theme.tertiaryLabel)
                    }
                }
            }
            Button(action: useCurrentLocation) {
                HStack {
                    Label("Use this phone's location", systemImage: "location")
                    Spacer()
                    if isLocating { ProgressView() }
                }
            }
            .disabled(isLocating)
            NavigationLink {
                CitySearch(store: store)
            } label: {
                Label("Search for a city", systemImage: "magnifyingglass")
            }
        } header: {
            SectionHeader("Weather location")
        } footer: {
            Text("Sets the forecast and the sunrise and sunset times.")
        }
    }

    private func useCurrentLocation() {
        isLocating = true
        Task {
            do {
                let found = try await finder.current()
                await store.setLocation(found)
            } catch let failure as LocationFailure {
                store.notice = failure.message
            } catch {
                store.notice = LocationFailure.unavailable.message
            }
            isLocating = false
        }
    }

    private var appearance: some View {
        Section {
            PaletteGrid(selected: settings.appearance.palette) { palette in
                Task { await store.setAppearance(FrameAppearance(palette: palette, mode: settings.appearance.mode)) }
            }
        } header: {
            SectionHeader("Palette")
        } footer: {
            Text("The frame and this app share one palette.")
        }
    }

    private var mode: some View {
        Section {
            Picker("Mode", selection: Binding(get: { settings.appearance.mode }, set: { mode in
                Task { await store.setAppearance(FrameAppearance(palette: settings.appearance.palette, mode: mode)) }
            })) {
                Text("Automatic").tag("auto")
                Text("Light").tag("light")
                Text("Dark").tag("dark")
            }
            .pickerStyle(.segmented)
        } header: {
            SectionHeader("Light or dark")
        } footer: {
            Text("Automatic follows sunrise and sunset on the frame.")
        }
    }

    private var cleanLink: String { calendarLink.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canAddCalendar: Bool {
        Limits.cleanName(calendarName) != nil && cleanLink.lowercased().hasPrefix("https://") && !cleanLink.contains(" ")
    }

    private var calendarSection: some View {
        Section {
            ForEach(calendars) { calendar in
                RowLabel(calendar.name, symbol: "calendar", symbolTint: Color(hex: calendar.color))
                    .swipeActions(edge: .trailing) {
                        Button("Remove", systemImage: "trash", role: .destructive) { removingCalendar = calendar }
                    }
                    .contextMenu {
                        Button("Remove from Frame", systemImage: "trash", role: .destructive) { removingCalendar = calendar }
                    }
            }
            if calendars.count < Limits.calendars {
                Button {
                    addsCalendar.toggle()
                    calendarNameFocused = addsCalendar
                } label: {
                    HStack {
                        Label("Add a calendar", systemImage: "plus")
                        Spacer()
                        RowDisclosure(isExpanded: addsCalendar) {
                            addsCalendar.toggle()
                            calendarNameFocused = addsCalendar
                        }
                        .accessibilityHidden(true)
                    }
                }
                .accessibilityValue(addsCalendar ? "Expanded" : "Collapsed")
            }
            if addsCalendar {
                TextField("Name on the frame", text: $calendarName, prompt: Text("Family"))
                    .focused($calendarNameFocused)
                    .submitLabel(.next)
                    .onChange(of: calendarName) { _, new in
                        if new.count > Limits.calendarNameLength { calendarName = String(new.prefix(Limits.calendarNameLength)) }
                    }
                    .inlineEditorRow()
                SwatchPicker(selection: $calendarColor)
                    .inlineEditorRow()
                HStack(alignment: .top, spacing: Space.m) {
                    TextField("Paste the secret address", text: $calendarLink, axis: .vertical)
                        .lineLimit(1...4)
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .privacySensitive()
                        .accessibilityLabel("Secret address in iCal format")
                    PasteButton(payloadType: String.self) { strings in
                        calendarLink = strings.first ?? ""
                    }
                    .labelStyle(.iconOnly)
                    .buttonBorderShape(.capsule)
                }
                .inlineEditorRow()
                Button("Add calendar", systemImage: "checkmark", action: addCalendar)
                    .disabled(!canAddCalendar)
                    .inlineEditorRow()
            }
        } header: {
            SectionHeader("Calendars")
        } footer: {
            if addsCalendar {
                Text("Google Calendar on a computer: Settings, the calendar, then “Secret address in iCal format”. The address is a password; it stays on the frame.")
            } else {
                Text(calendars.count >= Limits.calendars
                     ? "The frame holds up to \(Limits.calendars) calendars."
                     : "Google Calendar feeds shown on the frame.")
            }
        }
        .stateAnimation(addsCalendar)
        .confirmationDialog("Remove \(removingCalendar?.name ?? "") from the frame?",
                            isPresented: Binding(get: { removingCalendar != nil }, set: { if !$0 { removingCalendar = nil } }), titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                if let id = removingCalendar?.id { Task { await store.deleteCalendar(id: id) } }
            }
        }
    }

    private func addCalendar() {
        guard let clean = Limits.cleanName(calendarName), canAddCalendar else { return }
        let url = cleanLink
        calendarName = ""
        calendarLink = ""
        calendarNameFocused = false
        addsCalendar = false
        Task { await store.addCalendar(name: clean, color: calendarColor, url: url) }
    }

    private var devices: some View {
        Section {
            ForEach(store.devices) { device in
                RowLabel(device.name, subtitle: detail(device), symbol: "iphone", symbolTint: theme.tint) {
                    if device.isSelf { RowValue(text: "This phone") }
                }
            }
            Button("Unpair this phone", systemImage: "xmark.circle", role: .destructive) { confirmsUnpair = true }
        } header: {
            SectionHeader("Paired phones")
        } footer: {
            Text("To remove another phone, use Settings › Phone app on the frame.")
        }
        .confirmationDialog("Unpair this phone from \(store.frame.name)? To pair again you will need to be at the frame.",
                            isPresented: $confirmsUnpair, titleVisibility: .visible) {
            Button("Unpair", role: .destructive) {
                Task { await session.unpair() }
            }
        }
    }

    private func detail(_ device: PairedDevice) -> String? {
        let parts = [device.pairedDate.map { "Paired \($0.formatted(date: .abbreviated, time: .omitted))" },
                     device.lastSeenDate.map { "Last seen \($0.formatted(date: .abbreviated, time: .omitted))" }].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var connection: some View {
        Section {
            Button("Use a different frame", systemImage: "arrow.triangle.2.circlepath") { session.leave() }
        } header: {
            SectionHeader("This phone")
        } footer: {
            Text("Everything iFramed You sends is encrypted between this phone and your frame.")
        }
    }
}

struct CitySearch: View {
    @Environment(\.dismiss) private var dismiss
    let store: FrameStore
    @State private var query = ""
    @State private var results: [FrameLocation]?
    @State private var isSearching = false

    var body: some View {
        ThemedList {
            if let results {
                if results.isEmpty {
                    Text("No city found with that name.").foregroundStyle(Theme.secondaryLabel)
                }
                ForEach(results, id: \.name) { result in
                    Button {
                        Task { await store.setLocation(result) }
                        dismiss()
                    } label: {
                        RowLabel(result.name, symbol: "mappin")
                    }
                    .buttonStyle(RowButtonStyle())
                }
            }
        }
        .overlay {
            if isSearching {
                ProgressView()
            } else if results == nil {
                ContentUnavailableView("Type a city name", systemImage: "magnifyingglass", description: Text("Used for the forecast and for sunrise and sunset."))
            }
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "City")
        .textContentType(.addressCity)
        .onSubmit(of: .search, search)
        .navigationTitle("Weather city")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func search() {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, !isSearching else { return }
        isSearching = true
        Task {
            results = await LocationFinder.search(text)
            isSearching = false
        }
    }
}

struct ICloudAlbumSection: View {
    @Environment(\.theme) private var theme
    let store: FrameStore
    @State private var link = ""
    @State private var isConnecting = false
    @State private var confirmsDisconnect = false

    private var settings: FrameSettings { store.state?.settings ?? FrameSettings(supportsICloudAlbum: false) }
    private var hasText: Bool { !link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var isValid: Bool { ICloudLink.normalized(link) != nil }

    var body: some View {
        Section {
            if !settings.supportsICloudAlbum {
                RowLabel("Update the frame to use iCloud albums", symbol: "arrow.down.circle", symbolTint: Theme.secondaryLabel)
            } else if let album = settings.icloudAlbum {
                connected(album)
            } else {
                setup
            }
        } header: {
            SectionHeader("iCloud shared album")
        } footer: {
            footer
        }
    }

    @ViewBuilder private var footer: some View {
        if !settings.supportsICloudAlbum {
            EmptyView()
        } else if settings.icloudAlbum != nil {
            Text("The frame fetches the album from Apple itself.")
        } else if hasText, !isValid {
            Text("Paste the whole link from Share Link.").foregroundStyle(theme.tint)
        } else {
            Text("In Photos: open the shared album, turn on Public Website, then Share Link.")
        }
    }

    @ViewBuilder private var setup: some View {
        HStack(alignment: .top, spacing: Space.m) {
            TextField("Paste the album link", text: $link, axis: .vertical)
                .lineLimit(1...3)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .privacySensitive()
                .accessibilityLabel("Album link")
            PasteButton(payloadType: String.self) { strings in
                link = (strings.first ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .labelStyle(.iconOnly)
            .buttonBorderShape(.capsule)
        }
        Button(action: connect) {
            HStack {
                Label("Connect album", systemImage: "icloud")
                Spacer()
                if isConnecting { ProgressView() }
            }
        }
        .disabled(!isValid || isConnecting)
    }

    @ViewBuilder private func connected(_ album: ICloudAlbum) -> some View {
        RowLabel(album.name.isEmpty ? "Shared album" : album.name, symbol: "icloud", symbolTint: theme.tint) {
            RowValue(text: album.count == 1 ? "1 picture" : "\(album.count) pictures")
        }
        if album.syncing {
            HStack(spacing: Space.m) {
                ProgressView()
                Text("Syncing with iCloud")
            }
        } else {
            LabeledContent("Last synced", value: album.lastSyncDate.map { $0.formatted(.relative(presentation: .named)) } ?? "Not yet")
        }
        if let error = album.error {
            Label(error, systemImage: "exclamationmark.triangle")
                .font(.note)
                .foregroundStyle(theme.tint)
        }
        Button("Sync now", systemImage: "arrow.clockwise") {
            Task { await store.syncICloudAlbum() }
        }
        .disabled(album.syncing)
        Button("Disconnect album", role: .destructive) { confirmsDisconnect = true }
            .confirmationDialog("Disconnect this album? Its pictures are removed from the frame. Pictures sent from phones stay.",
                                isPresented: $confirmsDisconnect, titleVisibility: .visible) {
                Button("Disconnect", role: .destructive) {
                    Task { await store.disconnectICloudAlbum() }
                }
            }
    }

    private func connect() {
        let entered = link
        isConnecting = true
        Task {
            if await store.connectICloudAlbum(link: entered) { link = "" }
            isConnecting = false
        }
    }
}
