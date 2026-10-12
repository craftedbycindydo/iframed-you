import SwiftUI
import SkylitCore

struct SetupScreen: View {
    @Environment(FrameSession.self) private var session
    @Environment(\.theme) private var theme
    let store: FrameStore
    @State private var finder = LocationFinder()
    @State private var isLocating = false
    @State private var cityQuery = ""
    @State private var cityResults: [FrameLocation]?
    @State private var isSearching = false
    @State private var showsCalendarForm = false
    @State private var revoking: PairedDevice?
    @State private var confirmsUnpair = false

    private var settings: FrameSettings { store.state?.settings ?? FrameSettings() }
    private var calendars: [CalendarFeed] { store.state?.calendars ?? [] }

    var body: some View {
        ScrollViewReader { proxy in
            Screen(title: "Frame", store: store) {
                EmptyView()
            } content: {
                location
                appearance
                ICloudAlbumCard(store: store).id("icloud")
                calendarSection.id("calendars")
                devices.id("devices")
                connection
            }
            .onAppear {
                #if DEBUG
                if let anchor = Demo.scrollAnchor {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { proxy.scrollTo(anchor, anchor: .top) }
                    if anchor == "calendarForm" { showsCalendarForm = true }
                }
                #endif
            }
        }
        .task { await store.loadDevices() }
        .sheet(isPresented: $showsCalendarForm) {
            CalendarForm(store: store).environment(\.theme, theme)
        }
    }

    private func sectionTitle(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).textStyle(.title).foregroundStyle(theme.ink)
            Text(detail).textStyle(.caption).foregroundStyle(theme.muted)
        }
    }

    private var location: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                sectionTitle("Weather location", "Sets the forecast and when the frame switches between light and dark.")
                HStack(spacing: 12) {
                    Image(systemName: "mappin.and.ellipse")
                        .foregroundStyle(theme.accent)
                        .frame(width: 40, height: 40)
                        .background(theme.soft, in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(settings.location?.name ?? "Not set").textStyle(.heading).foregroundStyle(theme.ink)
                        if let zone = settings.location?.timezone {
                            Text(zone.replacingOccurrences(of: "_", with: " ")).textStyle(.caption).foregroundStyle(theme.muted)
                        }
                    }
                }
                Button {
                    useCurrentLocation()
                } label: {
                    if isLocating { ProgressView().tint(theme.ink) } else { Label("Use this phone's location", systemImage: "location") }
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(isLocating)
                HStack(spacing: 8) {
                    TextField("Search for a city", text: $cityQuery)
                        .textContentType(.addressCity)
                        .submitLabel(.search)
                        .onSubmit(searchCity)
                        .fieldStyle()
                    IconButton(symbol: "magnifyingglass", label: "Search", action: searchCity)
                        .disabled(isSearching || cityQuery.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if isSearching {
                    ProgressView().tint(theme.accent).frame(maxWidth: .infinity)
                }
                if let cityResults {
                    if cityResults.isEmpty {
                        Text("No city found with that name.").textStyle(.caption).foregroundStyle(theme.muted)
                    }
                    ForEach(cityResults, id: \.name) { result in
                        Button {
                            self.cityResults = nil
                            cityQuery = ""
                            Task { await store.setLocation(result) }
                        } label: {
                            HStack {
                                Text(result.name).textStyle(.body).foregroundStyle(theme.ink).multilineTextAlignment(.leading)
                                Spacer()
                                Text("Use").textStyle(.label).foregroundStyle(theme.accent)
                            }
                            .padding(.horizontal, 14)
                            .frame(minHeight: 48)
                            .background(theme.soft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
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

    private func searchCity() {
        let query = cityQuery.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty, !isSearching else { return }
        isSearching = true
        Task {
            cityResults = await LocationFinder.search(query)
            isSearching = false
        }
    }

    private var appearance: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                sectionTitle("Appearance", "The frame and this app share one palette.")
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                    ForEach(Palettes.all) { palette in
                        let isSelected = settings.appearance.palette == palette.id
                        let sample = Theme(palette: palette.id, dark: theme.isDark)
                        Button {
                            Task { await store.setAppearance(FrameAppearance(palette: palette.id, mode: settings.appearance.mode)) }
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 5) {
                                    RoundedRectangle(cornerRadius: 4).fill(sample.panel)
                                    RoundedRectangle(cornerRadius: 4).fill(sample.accent)
                                    RoundedRectangle(cornerRadius: 4).fill(sample.soft)
                                }
                                .padding(8)
                                .frame(height: 46)
                                .background(sample.bg, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(theme.line, lineWidth: 1))
                                Text(palette.name).textStyle(.caption).foregroundStyle(theme.ink).lineLimit(1).minimumScaleFactor(0.8)
                            }
                            .padding(7)
                            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(isSelected ? theme.accent : .clear, lineWidth: 2))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(palette.name)
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                }
                Picker("Mode", selection: Binding(get: { settings.appearance.mode }, set: { mode in
                    Task { await store.setAppearance(FrameAppearance(palette: settings.appearance.palette, mode: mode)) }
                })) {
                    Text("Automatic").tag("auto")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                .pickerStyle(.segmented)
                Text("Automatic follows sunrise and sunset on the frame, and this phone's own setting here.")
                    .textStyle(.caption)
                    .foregroundStyle(theme.muted)
            }
        }
    }

    private var calendarSection: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                sectionTitle("Calendars", "Google Calendar secret iCal links shown on the frame.")
                if calendars.isEmpty {
                    Text("No calendars yet.").textStyle(.body).foregroundStyle(theme.muted)
                }
                ForEach(calendars) { calendar in
                    HStack(spacing: 12) {
                        Circle().fill(Color(hex: calendar.color)).frame(width: 14, height: 14)
                        Text(calendar.name).textStyle(.body).foregroundStyle(theme.ink)
                        Spacer()
                        Menu {
                            Button("Remove from frame", role: .destructive) {
                                Task { await store.deleteCalendar(id: calendar.id) }
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .foregroundStyle(theme.muted)
                                .frame(width: Metrics.touch, height: Metrics.touch)
                                .contentShape(Rectangle())
                        }
                        .accessibilityLabel("Options for \(calendar.name)")
                    }
                }
                Button("Add a calendar") { showsCalendarForm = true }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(calendars.count >= Limits.calendars)
                if calendars.count >= Limits.calendars {
                    Text("The frame holds up to \(Limits.calendars) calendars.").textStyle(.caption).foregroundStyle(theme.muted)
                }
            }
        }
    }

    private var devices: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                sectionTitle("Paired phones", "Every device that can manage this frame.")
                ForEach(store.devices) { device in
                    HStack(spacing: 12) {
                        Image(systemName: "iphone")
                            .foregroundStyle(theme.accent)
                            .frame(width: 40, height: 40)
                            .background(theme.soft, in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(device.name).textStyle(.body).foregroundStyle(theme.ink)
                            if let date = device.pairedDate {
                                Text("Paired \(date.formatted(date: .abbreviated, time: .omitted))").textStyle(.caption).foregroundStyle(theme.muted)
                            }
                        }
                        Spacer()
                        Button("Revoke") { revoking = device }
                            .textStyle(.label)
                            .foregroundStyle(theme.accent)
                            .frame(minHeight: Metrics.touch)
                    }
                }
                Text("Revoking the phone you are holding returns it to pairing.").textStyle(.caption).foregroundStyle(theme.muted)
            }
        }
        .confirmationDialog("Revoke \(revoking?.name ?? "")? It will need a new code from the frame to pair again.",
                            isPresented: Binding(get: { revoking != nil }, set: { if !$0 { revoking = nil } }), titleVisibility: .visible) {
            Button("Revoke", role: .destructive) {
                if let id = revoking?.id { Task { await store.revokeDevice(id: id) } }
            }
        }
    }

    private var connection: some View {
        VStack(spacing: 10) {
            Button("Use a different frame") { session.leave() }
                .buttonStyle(SecondaryButtonStyle())
            Button("Forget this frame on this phone") { confirmsUnpair = true }
                .buttonStyle(SecondaryButtonStyle(destructive: true))
                .confirmationDialog("Forget \(store.frame.name)? This phone will need a new code to pair again.", isPresented: $confirmsUnpair, titleVisibility: .visible) {
                    Button("Forget", role: .destructive) { session.forget() }
                }
        }
        .padding(.top, 4)
    }
}

struct ICloudAlbumCard: View {
    @Environment(\.theme) private var theme
    let store: FrameStore
    @State private var link = ""
    @State private var isConnecting = false
    @State private var confirmsDisconnect = false

    private var settings: FrameSettings { store.state?.settings ?? FrameSettings(supportsICloudAlbum: false) }
    private var hasText: Bool { !link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var isValid: Bool { ICloudLink.normalized(link) != nil }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("iCloud shared album").textStyle(.title).foregroundStyle(theme.ink)
                    Text("The frame fetches the album from Apple itself, so it stays up to date while this phone is away.")
                        .textStyle(.caption)
                        .foregroundStyle(theme.muted)
                }
                if !settings.supportsICloudAlbum {
                    Label("Update the frame to use iCloud albums.", systemImage: "arrow.down.circle")
                        .textStyle(.body)
                        .foregroundStyle(theme.muted)
                } else if let album = settings.icloudAlbum {
                    connected(album)
                } else {
                    setup
                }
            }
        }
    }

    @ViewBuilder private var setup: some View {
        VStack(alignment: .leading, spacing: 8) {
            step(1, "In Photos, open the shared album and tap the People icon.")
            step(2, "Turn on Public Website.")
            step(3, "Tap Share Link, then Copy.")
        }
        TextField("Paste the album link", text: $link, axis: .vertical)
            .lineLimit(1...3)
            .keyboardType(.URL)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .privacySensitive()
            .padding(.vertical, 10)
            .fieldStyle()
            .accessibilityLabel("Album link")
        if hasText, !isValid {
            Text("Paste the whole link from Share Link, or just the code after the # sign.")
                .textStyle(.caption)
                .foregroundStyle(theme.accent)
        }
        HStack(spacing: 10) {
            PasteButton(payloadType: String.self) { strings in
                link = (strings.first ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .tint(theme.accent)
            Spacer()
        }
        Button {
            connect()
        } label: {
            if isConnecting { ProgressView().tint(theme.accentInk) } else { Text("Connect album") }
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(!isValid || isConnecting)
        Text("Anyone with this link can see the album, so it is sent only to your frame and is not kept on this phone.")
            .textStyle(.caption)
            .foregroundStyle(theme.muted)
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number)")
                .textStyle(.label)
                .foregroundStyle(theme.ink)
                .frame(width: 24, height: 24)
                .background(theme.soft, in: Circle())
            Text(text).textStyle(.body).foregroundStyle(theme.ink)
        }
    }

    @ViewBuilder private func connected(_ album: ICloudAlbum) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "icloud")
                .foregroundStyle(theme.accent)
                .frame(width: 40, height: 40)
                .background(theme.soft, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(album.name.isEmpty ? "Shared album" : album.name).textStyle(.heading).foregroundStyle(theme.ink)
                Text(album.count == 1 ? "1 picture on the frame" : "\(album.count) pictures on the frame")
                    .textStyle(.caption)
                    .foregroundStyle(theme.muted)
            }
        }
        if album.syncing {
            HStack(spacing: 10) {
                ProgressView().tint(theme.accent)
                Text("Syncing with iCloud").textStyle(.body).foregroundStyle(theme.ink)
            }
        } else if let date = album.lastSyncDate {
            Text("Last synced \(date.formatted(.relative(presentation: .named)))").textStyle(.body).foregroundStyle(theme.muted)
        } else {
            Text("Not synced yet").textStyle(.body).foregroundStyle(theme.muted)
        }
        if let error = album.error {
            Label(error, systemImage: "exclamationmark.triangle")
                .textStyle(.caption)
                .foregroundStyle(theme.accent)
        }
        Button("Sync now") {
            Task { await store.syncICloudAlbum() }
        }
        .buttonStyle(SecondaryButtonStyle())
        .disabled(album.syncing)
        Button("Disconnect album") { confirmsDisconnect = true }
            .buttonStyle(SecondaryButtonStyle(destructive: true))
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

struct CalendarForm: View {
    @Environment(\.theme) private var theme
    let store: FrameStore
    @State private var name = ""
    @State private var color = Palettes.swatches[5]
    @State private var link = ""

    private var cleanLink: String { link.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSave: Bool {
        Limits.cleanName(name) != nil && cleanLink.lowercased().hasPrefix("https://") && !cleanLink.contains(" ")
    }

    var body: some View {
        SheetScaffold(title: "Add calendar", confirmLabel: "Add", canConfirm: canSave, onConfirm: save) {
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    FieldLabel(text: "Name on the frame")
                    TextField("Family", text: $name)
                        .fieldStyle()
                        .onChange(of: name) { _, new in
                            if new.count > Limits.calendarNameLength { name = String(new.prefix(Limits.calendarNameLength)) }
                        }
                    FieldLabel(text: "Colour").padding(.top, 6)
                    SwatchPicker(selection: $color)
                }
            }
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    FieldLabel(text: "Secret address in iCal format")
                    TextField("Paste the secret address", text: $link, axis: .vertical)
                        .lineLimit(1...4)
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .privacySensitive()
                        .padding(.vertical, 10)
                        .fieldStyle()
                    PasteButton(payloadType: String.self) { strings in
                        link = strings.first ?? ""
                    }
                    .tint(theme.accent)
                    Text("In Google Calendar on a computer: Settings, pick the calendar, then copy “Secret address in iCal format”. The link goes straight to your frame over Wi-Fi and is not kept on this phone.")
                        .textStyle(.caption)
                        .foregroundStyle(theme.muted)
                }
            }
        }
    }

    private func save() {
        guard let clean = Limits.cleanName(name) else { return }
        let url = cleanLink
        Task { await store.addCalendar(name: clean, color: color, url: url) }
    }
}
