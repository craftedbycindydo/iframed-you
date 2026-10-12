import Foundation

public struct FrameInfo: Decodable, Equatable, Sendable {
    public let v: Int
    public let frameId: String
    public let name: String
    public let pairing: Bool

    public init(v: Int, frameId: String, name: String, pairing: Bool = false) {
        self.v = v
        self.frameId = frameId
        self.name = name
        self.pairing = pairing
    }

    private enum CodingKeys: String, CodingKey {
        case v, frameId, name, pairing
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        v = try c.decode(Int.self, forKey: .v)
        frameId = try c.decode(String.self, forKey: .frameId)
        name = Limits.display(try c.decode(String.self, forKey: .name))
        pairing = try c.decodeIfPresent(Bool.self, forKey: .pairing) ?? false
    }
}

public struct PairSession: Decodable, Equatable, Sendable {
    public let session: String
    public let nF: String
}

public struct PairResult: Decodable, Equatable, Sendable {
    public let deviceId: String
    public let frameId: String
    public let name: String
}

public struct PairedDevice: Decodable, Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let pairedAt: String
    public let lastSeen: String?
    public let isSelf: Bool

    public var pairedDate: Date? { ISO8601.date(pairedAt) }
    public var lastSeenDate: Date? { lastSeen.flatMap(ISO8601.date) }

    private enum CodingKeys: String, CodingKey {
        case id, name, pairedAt, lastSeen
        case isSelf = "self"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = Limits.display(try c.decode(String.self, forKey: .name), limit: Limits.deviceNameLength)
        pairedAt = try c.decodeIfPresent(String.self, forKey: .pairedAt) ?? ""
        lastSeen = try c.decodeIfPresent(String.self, forKey: .lastSeen)
        isSelf = try c.decodeIfPresent(Bool.self, forKey: .isSelf) ?? false
    }
}

public struct Person: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var color: String

    public init(id: String, name: String, color: String) {
        self.id = id
        self.name = name
        self.color = color
    }
}

public struct Chore: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var emoji: String
    public var personId: String?
    public var days: [Int]
    public var done: [String]

    public init(id: String, title: String, emoji: String = "", personId: String? = nil, days: [Int] = [], done: [String] = []) {
        self.id = id
        self.title = title
        self.emoji = emoji
        self.personId = personId
        self.days = days
        self.done = done
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        emoji = try c.decodeIfPresent(String.self, forKey: .emoji) ?? ""
        personId = try c.decodeIfPresent(String.self, forKey: .personId)
        days = try c.decodeIfPresent([Int].self, forKey: .days) ?? []
        done = try c.decodeIfPresent([String].self, forKey: .done) ?? []
    }
}

public struct ShoppingItem: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var qty: Int
    public var note: String
    public var done: Bool

    public init(id: String, name: String, qty: Int = 1, note: String = "", done: Bool = false) {
        self.id = id
        self.name = name
        self.qty = qty
        self.note = note
        self.done = done
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        qty = try c.decodeIfPresent(Int.self, forKey: .qty) ?? 1
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        done = try c.decodeIfPresent(Bool.self, forKey: .done) ?? false
    }
}

public struct FrameLocation: Codable, Equatable, Sendable {
    public var name: String
    public var latitude: Double
    public var longitude: Double
    public var timezone: String?

    public init(name: String, latitude: Double, longitude: Double, timezone: String? = nil) {
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.timezone = timezone
    }
}

public struct FrameAppearance: Codable, Equatable, Sendable {
    public var palette: String
    public var mode: String

    public static let standard = FrameAppearance(palette: "linen", mode: "auto")

    public init(palette: String, mode: String) {
        self.palette = palette
        self.mode = mode
    }
}

public struct ICloudAlbum: Codable, Equatable, Sendable {
    public var name: String
    public var count: Int
    public var lastSync: String?
    public var syncing: Bool
    public var error: String?

    public var lastSyncDate: Date? { lastSync.flatMap(ISO8601.date) }

    public init(name: String, count: Int = 0, lastSync: String? = nil, syncing: Bool = false, error: String? = nil) {
        self.name = name
        self.count = count
        self.lastSync = lastSync
        self.syncing = syncing
        self.error = error
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = Limits.display(try c.decodeIfPresent(String.self, forKey: .name) ?? "")
        count = try c.decodeIfPresent(Int.self, forKey: .count) ?? 0
        lastSync = try c.decodeIfPresent(String.self, forKey: .lastSync)
        syncing = try c.decodeIfPresent(Bool.self, forKey: .syncing) ?? false
        error = try c.decodeIfPresent(String.self, forKey: .error).map { Limits.display($0, limit: Limits.noteLength) }.flatMap { $0.isEmpty ? nil : $0 }
    }
}

public enum ICloudLink {
    private static let token = "[A-Za-z0-9_-]{8,64}"
    private static let forms = [
        "^https://www\\.icloud\\.com/sharedalbum/(?:[A-Za-z-]{2,10}/)?#(\(token))$",
        "^https://share\\.icloud\\.com/photos/(\(token))/?$",
    ]

    public static func normalized(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.range(of: "^\(token)$", options: .regularExpression) != nil {
            return "https://www.icloud.com/sharedalbum/#\(trimmed)"
        }
        let matches = forms.contains { trimmed.range(of: $0, options: .regularExpression) != nil }
        return matches ? trimmed : nil
    }
}

public struct FrameSettings: Codable, Equatable, Sendable {
    public var location: FrameLocation?
    public var appearance: FrameAppearance
    public var icloudAlbum: ICloudAlbum?
    public var supportsICloudAlbum: Bool

    private enum CodingKeys: String, CodingKey {
        case location
        case appearance
        case icloudAlbum
    }

    public init(location: FrameLocation? = nil, appearance: FrameAppearance = .standard,
                icloudAlbum: ICloudAlbum? = nil, supportsICloudAlbum: Bool = true) {
        self.location = location
        self.appearance = appearance
        self.icloudAlbum = icloudAlbum
        self.supportsICloudAlbum = supportsICloudAlbum
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        location = try c.decodeIfPresent(FrameLocation.self, forKey: .location)
        appearance = try c.decodeIfPresent(FrameAppearance.self, forKey: .appearance) ?? .standard
        supportsICloudAlbum = c.contains(.icloudAlbum)
        icloudAlbum = try c.decodeIfPresent(ICloudAlbum.self, forKey: .icloudAlbum)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(location, forKey: .location)
        try c.encode(appearance, forKey: .appearance)
        if supportsICloudAlbum { try c.encode(icloudAlbum, forKey: .icloudAlbum) }
    }
}

public struct CalendarFeed: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var color: String

    public init(id: String, name: String, color: String) {
        self.id = id
        self.name = name
        self.color = color
    }
}

public struct PhotoRef: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let addedAt: String

    public init(id: String, addedAt: String) {
        self.id = id
        self.addedAt = addedAt
    }
}

public struct PhotoSummary: Codable, Equatable, Sendable {
    public var count: Int

    public init(count: Int) {
        self.count = count
    }
}

public struct FrameState: Codable, Equatable, Sendable {
    public var rev: Int
    public var people: [Person]
    public var chores: [Chore]
    public var shopping: [ShoppingItem]
    public var settings: FrameSettings
    public var calendars: [CalendarFeed]
    public var photos: PhotoSummary

    public init(rev: Int, people: [Person] = [], chores: [Chore] = [], shopping: [ShoppingItem] = [],
                settings: FrameSettings = FrameSettings(), calendars: [CalendarFeed] = [], photos: PhotoSummary = PhotoSummary(count: 0)) {
        self.rev = rev
        self.people = people
        self.chores = chores
        self.shopping = shopping
        self.settings = settings
        self.calendars = calendars
        self.photos = photos
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rev = try c.decode(Int.self, forKey: .rev)
        people = try c.decodeIfPresent([Person].self, forKey: .people) ?? []
        chores = try c.decodeIfPresent([Chore].self, forKey: .chores) ?? []
        shopping = try c.decodeIfPresent([ShoppingItem].self, forKey: .shopping) ?? []
        settings = try c.decodeIfPresent(FrameSettings.self, forKey: .settings) ?? FrameSettings(supportsICloudAlbum: false)
        calendars = try c.decodeIfPresent([CalendarFeed].self, forKey: .calendars) ?? []
        photos = try c.decodeIfPresent(PhotoSummary.self, forKey: .photos) ?? PhotoSummary(count: 0)
    }
}

public struct MutationResult: Decodable, Equatable, Sendable {
    public var rev: Int?
    public var person: Person?
    public var chore: Chore?
    public var item: ShoppingItem?
    public var calendar: CalendarFeed?
    public var photo: PhotoRef?

    public init(rev: Int? = nil) {
        self.rev = rev
    }
}

public struct ChoreDraft: Equatable, Sendable {
    public var title: String
    public var emoji: String
    public var personId: String?
    public var days: [Int]

    public init(title: String, emoji: String = "", personId: String? = nil, days: [Int] = []) {
        self.title = title
        self.emoji = emoji
        self.personId = personId
        self.days = days
    }
}

public struct ShoppingDraft: Equatable, Sendable {
    public var name: String
    public var qty: Int
    public var note: String

    public init(name: String, qty: Int = 1, note: String = "") {
        self.name = name
        self.qty = qty
        self.note = note
    }
}

public enum ISO8601 {
    public static func date(_ text: String) -> Date? {
        let plain = ISO8601DateFormatter()
        if let date = plain.date(from: text) { return date }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text)
    }
}

public enum Limits {
    public static let people = 12
    public static let chores = 100
    public static let shoppingItems = 200
    public static let calendars = 6
    public static let nameLength = 80
    public static let calendarNameLength = 60
    public static let photoMinimumEdges = (long: 320, short: 240)
    public static let quantity = 1...99
    public static let photoBytes = 15 * 1024 * 1024
    public static let photoEdge = 2560
    public static let deviceNameLength = 40
    public static let noteLength = 200
    public static let jsonResponseBytes = 1024 * 1024
    public static let photoResponseBytes = 16 * 1024 * 1024

    private static let directionMarks: Set<UInt32> = [0x061C, 0x200E, 0x200F, 0x202A, 0x202B, 0x202C, 0x202D, 0x202E, 0x2066, 0x2067, 0x2068, 0x2069]

    private static func isUnsafe(_ scalar: Unicode.Scalar) -> Bool {
        scalar.properties.generalCategory == .control || directionMarks.contains(scalar.value)
    }

    public static func display(_ text: String, limit: Int = nameLength) -> String {
        let kept = String(String.UnicodeScalarView(text.unicodeScalars.filter { !isUnsafe($0) }))
        return String(kept.trimmingCharacters(in: .whitespacesAndNewlines).prefix(limit))
    }

    public static func cleanDeviceName(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...deviceNameLength).contains(trimmed.count), !trimmed.unicodeScalars.contains(where: isUnsafe) else { return nil }
        return trimmed
    }

    public static func responseBytes(for request: URLRequest) -> Int {
        let isPhoto = (request.httpMethod ?? "GET") == "GET" && (request.url?.path ?? "").hasPrefix("/v1/photos/")
        return isPhoto ? photoResponseBytes : jsonResponseBytes
    }

    public static func cleanName(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return (1...nameLength).contains(trimmed.count) ? trimmed : nil
    }

    public static func isHexColor(_ text: String) -> Bool {
        text.range(of: "^#[0-9A-Fa-f]{6}$", options: .regularExpression) != nil
    }
}
