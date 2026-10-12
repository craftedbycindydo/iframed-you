import Foundation
import Observation

public struct UploadStatus: Equatable, Sendable {
    public var index: Int
    public var total: Int
    public var fraction: Double

    public var overall: Double {
        total == 0 ? 0 : (Double(index) + fraction) / Double(total)
    }
}

@MainActor
@Observable
public final class FrameStore {
    public enum Link: Equatable, Sendable {
        case connecting
        case online
        case offline
    }

    public let frame: PairedFrame
    public private(set) var state: FrameState?
    public private(set) var photos: [PhotoRef] = []
    public private(set) var devices: [PairedDevice] = []
    public private(set) var link: Link = .connecting
    public private(set) var upload: UploadStatus?
    public var notice: String?
    public var removedItem: ShoppingItem?

    public var onUnauthorized: (() -> Void)?
    public var relocate: (() async -> URL?)?

    private var api: FrameAPI
    private let now: () -> Date
    private var inFlight = 0
    private var needsFullState = false
    private var confirmed: FrameState?

    public init(frame: PairedFrame, api: FrameAPI, now: @escaping () -> Date = Date.init) {
        self.frame = frame
        self.api = api
        self.now = now
    }

    public var today: TodayChores? {
        state.map { ChoreLogic.today($0, now: now()) }
    }

    public func refresh() async {
        await load(since: nil)
    }

    public func poll() async {
        await load(since: state?.rev)
    }

    public var isAlbumSyncing: Bool {
        state?.settings.icloudAlbum?.syncing == true
    }

    public func runPolling(every interval: Duration = .seconds(5), whileSyncing fast: Duration = .seconds(2)) async {
        while !Task.isCancelled {
            try? await Task.sleep(for: isAlbumSyncing ? fast : interval)
            if Task.isCancelled { return }
            await poll()
        }
    }

    private func load(since rev: Int?) async {
        if link == .offline, let url = await relocate?() {
            api.baseURL = url
        }
        do {
            if let fresh = try await api.state(since: needsFullState ? nil : rev) {
                state = fresh
                confirmed = fresh
            }
            needsFullState = false
            link = .online
        } catch {
            handle(error)
        }
    }

    @discardableResult
    private func handle(_ error: Error) -> FrameError {
        let failure = FrameError.from(error)
        switch failure {
        case .unauthorized:
            onUnauthorized?()
        case .timeout, .offline, .connectionLost, .pinMismatch:
            link = .offline
        case .cancelled:
            break
        default:
            notice = failure.userMessage
        }
        return failure
    }

    @discardableResult
    private func perform(tempId: String? = nil, optimistic: (inout FrameState) -> Void,
                         _ call: (FrameAPI) async throws -> MutationResult) async -> Bool {
        guard let before = state else { return false }
        var eager = before
        optimistic(&eager)
        state = eager
        inFlight += 1
        defer { inFlight -= 1 }
        do {
            let result = try await call(api)
            link = .online
            guard var current = state else { return true }
            let (expected, overflowed) = current.rev.addingReportingOverflow(1)
            if tempId == nil { optimistic(&current) }
            let settled = Self.settle(&current, result, tempId: tempId)
            if settled, !overflowed, result.rev == expected, !needsFullState, inFlight == 1 {
                current.rev = expected
                state = current
                confirmed = current
            } else {
                state = current
                await refresh()
            }
            return true
        } catch {
            needsFullState = true
            if inFlight == 1 { state = confirmed ?? before }
            if case .api = handle(error) { await refresh() }
            return false
        }
    }

    private static func settle(_ state: inout FrameState, _ result: MutationResult, tempId: String?) -> Bool {
        if let tempId {
            state.people.removeAll { $0.id == tempId }
            state.chores.removeAll { $0.id == tempId }
            state.shopping.removeAll { $0.id == tempId }
            state.calendars.removeAll { $0.id == tempId }
        }
        if let person = result.person { upsert(&state.people, person) }
        if let chore = result.chore { upsert(&state.chores, chore) }
        if let item = result.item { upsert(&state.shopping, item) }
        if let calendar = result.calendar { upsert(&state.calendars, calendar) }
        let returnedObject = result.person != nil || result.chore != nil || result.item != nil || result.calendar != nil
        return tempId == nil || returnedObject
    }

    private static func upsert<T: Identifiable>(_ list: inout [T], _ value: T) where T.ID == String {
        if let index = list.firstIndex(where: { $0.id == value.id }) {
            list[index] = value
        } else {
            list.append(value)
        }
    }

    private static func temporaryId() -> String {
        "local-\(UUID().uuidString)"
    }

    @discardableResult
    public func addPerson(name: String, color: String) async -> Bool {
        let id = Self.temporaryId()
        return await perform(tempId: id, optimistic: { $0.people.append(Person(id: id, name: name, color: color)) }) {
            try await $0.addPerson(name: name, color: color)
        }
    }

    @discardableResult
    public func updatePerson(_ person: Person) async -> Bool {
        await perform(optimistic: { Self.upsert(&$0.people, person) }) {
            try await $0.updatePerson(id: person.id, name: person.name, color: person.color)
        }
    }

    @discardableResult
    public func deletePerson(id: String) async -> Bool {
        await perform(optimistic: { state in
            state.people.removeAll { $0.id == id }
            for index in state.chores.indices where state.chores[index].personId == id {
                state.chores[index].personId = nil
            }
        }) { try await $0.deletePerson(id: id) }
    }

    @discardableResult
    public func addChore(_ draft: ChoreDraft) async -> Bool {
        let id = Self.temporaryId()
        let chore = Chore(id: id, title: draft.title, emoji: draft.emoji, personId: draft.personId, days: draft.days)
        return await perform(tempId: id, optimistic: { $0.chores.append(chore) }) { try await $0.addChore(draft) }
    }

    @discardableResult
    public func updateChore(id: String, _ draft: ChoreDraft) async -> Bool {
        await perform(optimistic: { state in
            guard let index = state.chores.firstIndex(where: { $0.id == id }) else { return }
            state.chores[index].title = draft.title
            state.chores[index].emoji = draft.emoji
            state.chores[index].personId = draft.personId
            state.chores[index].days = draft.days
        }) { try await $0.updateChore(id: id, draft) }
    }

    @discardableResult
    public func deleteChore(id: String) async -> Bool {
        await perform(optimistic: { $0.chores.removeAll { $0.id == id } }) { try await $0.deleteChore(id: id) }
    }

    @discardableResult
    public func setChore(id: String, done: Bool) async -> Bool {
        guard let state else { return false }
        let date = ChoreLogic.dateString(now(), timeZone: ChoreLogic.timeZone(for: state))
        return await perform(optimistic: { state in
            guard let index = state.chores.firstIndex(where: { $0.id == id }) else { return }
            state.chores[index].done.removeAll { $0 == date }
            if done { state.chores[index].done.append(date) }
        }) { try await $0.setChoreDone(id: id, date: date, done: done) }
    }

    @discardableResult
    public func addItem(_ draft: ShoppingDraft) async -> Bool {
        let id = Self.temporaryId()
        let item = ShoppingItem(id: id, name: draft.name, qty: draft.qty, note: draft.note)
        return await perform(tempId: id, optimistic: { $0.shopping.append(item) }) { try await $0.addItem(draft) }
    }

    @discardableResult
    public func updateItem(id: String, _ draft: ShoppingDraft) async -> Bool {
        await perform(optimistic: { state in
            guard let index = state.shopping.firstIndex(where: { $0.id == id }) else { return }
            state.shopping[index].name = draft.name
            state.shopping[index].qty = draft.qty
            state.shopping[index].note = draft.note
        }) { try await $0.updateItem(id: id, name: draft.name, qty: draft.qty, note: draft.note) }
    }

    @discardableResult
    public func setItem(id: String, done: Bool) async -> Bool {
        await perform(optimistic: { state in
            guard let index = state.shopping.firstIndex(where: { $0.id == id }) else { return }
            state.shopping[index].done = done
        }) { try await $0.updateItem(id: id, done: done) }
    }

    @discardableResult
    public func deleteItem(id: String) async -> Bool {
        removedItem = state?.shopping.first { $0.id == id }
        let removed = await perform(optimistic: { $0.shopping.removeAll { $0.id == id } }) { try await $0.deleteItem(id: id) }
        if !removed, removedItem?.id == id { removedItem = nil }
        return removed
    }

    @discardableResult
    public func undoRemove() -> Task<Bool, Never>? {
        guard let item = removedItem else { return nil }
        removedItem = nil
        return Task { await addItem(ShoppingDraft(name: item.name, qty: item.qty, note: item.note)) }
    }

    @discardableResult
    public func clearDoneItems() async -> Bool {
        await perform(optimistic: { $0.shopping.removeAll(where: \.done) }) { try await $0.clearDoneItems() }
    }

    @discardableResult
    public func setLocation(_ location: FrameLocation) async -> Bool {
        await perform(optimistic: { $0.settings.location = location }) { try await $0.setLocation(location) }
    }

    @discardableResult
    public func setAppearance(_ appearance: FrameAppearance) async -> Bool {
        await perform(optimistic: { $0.settings.appearance = appearance }) { try await $0.setAppearance(appearance) }
    }

    @discardableResult
    public func addCalendar(name: String, color: String, url: String) async -> Bool {
        let id = Self.temporaryId()
        return await perform(tempId: id, optimistic: { $0.calendars.append(CalendarFeed(id: id, name: name, color: color)) }) {
            try await $0.addCalendar(name: name, color: color, url: url)
        }
    }

    @discardableResult
    public func deleteCalendar(id: String) async -> Bool {
        await perform(optimistic: { $0.calendars.removeAll { $0.id == id } }) { try await $0.deleteCalendar(id: id) }
    }

    public func thermostatAccount() async throws -> TccCredentials? {
        try await api.thermostatAccount()
    }

    public func giveThermostatAccount(_ account: TccCredentials) async throws {
        try await api.setThermostatAccount(account)
    }

    @discardableResult
    public func connectICloudAlbum(link: String) async -> Bool {
        guard let url = ICloudLink.normalized(link) else {
            notice = "That isn't an iCloud shared album link. Copy it from the album's Share Link."
            return false
        }
        do {
            _ = try await api.connectICloudAlbum(url: url)
            await refresh()
            return true
        } catch FrameError.api(400, _) {
            notice = "The frame couldn't use that album. Turn on Public Website for it in Photos, then copy the link again."
            return false
        } catch {
            handle(error)
            return false
        }
    }

    @discardableResult
    public func disconnectICloudAlbum() async -> Bool {
        await perform(optimistic: { $0.settings.icloudAlbum = nil }) { try await $0.disconnectICloudAlbum() }
    }

    public func syncICloudAlbum() async {
        do {
            try await api.syncICloudAlbum()
            state?.settings.icloudAlbum?.syncing = true
            await refresh()
        } catch {
            handle(error)
        }
    }

    public func loadPhotos() async {
        do {
            photos = try await api.photos()
            link = .online
        } catch {
            handle(error)
        }
    }

    public func photoData(id: String) async throws -> Data {
        try await api.photoData(id: id)
    }

    public func uploadPhotos(_ sources: [Data]) async {
        await uploadPhotos(count: sources.count) { sources[$0] }
    }

    public func uploadPhotos(count: Int, load: (Int) async -> Data?) async {
        guard count > 0, upload == nil else { return }
        var failed = 0
        for index in 0..<count {
            upload = UploadStatus(index: index, total: count, fraction: 0)
            guard let source = await load(index) else {
                failed += 1
                continue
            }
            do {
                let jpeg = try await Task.detached(priority: .userInitiated) { try ImagePreparation.jpeg(from: source) }.value
                let result = try await api.uploadPhoto(jpeg) { [weak self] fraction in
                    Task { @MainActor in
                        guard let self, self.upload?.index == index else { return }
                        self.upload?.fraction = fraction
                    }
                }
                if let photo = result.photo, !photos.contains(where: { $0.id == photo.id }) {
                    photos.insert(photo, at: 0)
                }
            } catch is ImagePreparationError {
                failed += 1
            } catch {
                failed += 1
                let failure = handle(error)
                if failure == .unauthorized || failure == .pinMismatch || failure.isConnectivity { break }
            }
        }
        upload = nil
        if failed > 0 {
            notice = failed == 1 ? "One photo couldn't be added." : "\(failed) photos couldn't be added."
        }
        await refresh()
        await loadPhotos()
    }

    public func deletePhoto(id: String) async {
        let before = photos
        photos.removeAll { $0.id == id }
        do {
            _ = try await api.deletePhoto(id: id)
            await refresh()
        } catch {
            photos = before
            handle(error)
        }
    }

    public func loadDevices() async {
        do {
            devices = try await api.devices()
            link = .online
        } catch {
            handle(error)
        }
    }

    public var thisDevice: PairedDevice? {
        devices.first(where: \.isSelf)
    }

    @discardableResult
    public func unpairThisPhone() async -> Bool {
        do {
            if thisDevice == nil { devices = try await api.devices() }
            guard let mine = thisDevice else { return false }
            try await api.removeDevice(id: mine.id)
            return true
        } catch {
            return false
        }
    }
}
