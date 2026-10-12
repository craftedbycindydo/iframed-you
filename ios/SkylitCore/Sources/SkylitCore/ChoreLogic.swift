import Foundation

public struct ChoreStatus: Equatable, Identifiable, Sendable {
    public let chore: Chore
    public let isDone: Bool

    public var id: String { chore.id }
}

public struct ChoreGroup: Equatable, Identifiable, Sendable {
    public let person: Person?
    public let chores: [ChoreStatus]

    public var id: String { person?.id ?? "anyone" }
    public var doneCount: Int { chores.filter(\.isDone).count }
}

public struct TodayChores: Equatable, Sendable {
    public let date: String
    public let groups: [ChoreGroup]

    public var total: Int { groups.reduce(0) { $0 + $1.chores.count } }
    public var doneCount: Int { groups.reduce(0) { $0 + $1.doneCount } }
    public var progress: Double { total == 0 ? 0 : Double(doneCount) / Double(total) }
}

public enum ChoreLogic {
    public static let dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    public static func timeZone(for state: FrameState) -> TimeZone {
        state.settings.location?.timezone.flatMap(TimeZone.init(identifier:)) ?? .current
    }

    private static func calendar(_ timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    public static func dateString(_ date: Date, timeZone: TimeZone) -> String {
        let parts = calendar(timeZone).dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    public static func weekday(_ date: Date, timeZone: TimeZone) -> Int {
        calendar(timeZone).component(.weekday, from: date) - 1
    }

    public static func isDue(_ chore: Chore, weekday: Int) -> Bool {
        chore.days.isEmpty || chore.days.contains(weekday)
    }

    public static func daysSummary(_ days: [Int]) -> String {
        let valid = Set(days.filter { (0...6).contains($0) })
        if valid.isEmpty || valid.count == 7 { return "Every day" }
        if valid == [1, 2, 3, 4, 5] { return "Weekdays" }
        if valid == [0, 6] { return "Weekends" }
        return valid.sorted().map { dayNames[$0] }.joined(separator: ", ")
    }

    public static func today(_ state: FrameState, now: Date = Date()) -> TodayChores {
        let zone = timeZone(for: state)
        let date = dateString(now, timeZone: zone)
        let day = weekday(now, timeZone: zone)
        let knownPeople = Set(state.people.map(\.id))
        let due = state.chores.filter { isDue($0, weekday: day) }
            .map { ChoreStatus(chore: $0, isDone: $0.done.contains(date)) }
        var groups = state.people.map { person in
            ChoreGroup(person: person, chores: due.filter { $0.chore.personId == person.id })
        }
        groups.append(ChoreGroup(person: nil, chores: due.filter { status in
            status.chore.personId.map { !knownPeople.contains($0) } ?? true
        }))
        return TodayChores(date: date, groups: groups.filter { !$0.chores.isEmpty })
    }
}
