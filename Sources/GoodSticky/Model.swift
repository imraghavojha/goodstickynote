import AppKit

struct NoteTheme: Identifiable {
    let id: String
    let name: String
    let paper: NSColor
    let ink: NSColor
    static let all: [NoteTheme] = [
        .init(id: "butter", name: "Butter", paper: .hex(0xF5E5A3), ink: .hex(0x4E4329)),
        .init(id: "sage", name: "Sage", paper: .hex(0xD5E3CE), ink: .hex(0x354735)),
        .init(id: "rose", name: "Rose", paper: .hex(0xF1D0CE), ink: .hex(0x64403F)),
        .init(id: "sky", name: "Sky", paper: .hex(0xCEE1EF), ink: .hex(0x334E63)),
        .init(id: "lilac", name: "Lilac", paper: .hex(0xDDD5EE), ink: .hex(0x504264)),
        .init(id: "linen", name: "Linen", paper: .hex(0xEEEAE0), ink: .hex(0x4E4A41)),
        .init(id: "graphite", name: "Graphite", paper: .hex(0x353A3B), ink: .hex(0xE8EAE4))
    ]
    static func get(_ id: String) -> NoteTheme { all.first { $0.id == id } ?? all[0] }
}

struct Attachment: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var storedName: String
}

struct StickyNote: Codable, Identifiable, Equatable {
    var id = UUID()
    var text = ""
    var themeID = "butter"
    var opacity = 1.0
    var x: Double = 180
    var y: Double = 240
    var width: Double = 220
    var height: Double = 180
    var hidden = false
    var pinned = false
    var stackID: UUID? = nil
    /// Screen edge the note is tucked into as a side note ("left" / "right"), if any.
    var dock: String? = nil
    /// When a snoozed (hidden) note comes back to the desktop.
    var snoozedUntil: Date? = nil
    var attachments: [Attachment] = []
    var created = Date()
    var modified = Date()
    var title: String {
        text.split(maxSplits: 1, whereSeparator: \.isNewline).first.map(String.init) ?? "Untitled note"
    }
    var theme: NoteTheme { .get(themeID) }
    var dockEdge: DockEdge? { dock.flatMap(DockEdge.init) }
    /// No visible text and no files: hiding it would only leave clutter behind.
    var isBlank: Bool { attachments.isEmpty && text.allSatisfy(\.isWhitespace) }
}

struct Preferences: Codable {
    var keyCode: UInt32 = 45 // N
    var modifiers: UInt32 = 0x1000 | 0x0800 // control + option (Carbon)
    var defaultTheme = "butter"
    var defaultOpacity = 1.0
    var desktopLayoutVersion: Int? = nil
    /// Snooze choices offered by a note's snooze button, in menu order. Nil means the defaults.
    var snoozeChoices: [String]? = nil
    var snoozeOptions: [SnoozeOption] {
        get { snoozeChoices.map { $0.compactMap(SnoozeOption.init) } ?? SnoozeOption.defaults }
        set { snoozeChoices = SnoozeOption.allCases.filter(newValue.contains).map(\.rawValue) }
    }
}

enum DockEdge: String { case left, right }

/// Preset snooze times. Each resolves against the current date and calendar.
enum SnoozeOption: String, CaseIterable {
    case oneHour, threeHours, twelveHours, tomorrowMorning, evening, weekend, nextWeek
    static let defaults: [SnoozeOption] = [.tomorrowMorning, .evening, .twelveHours, .nextWeek]
    func title(from now: Date = Date(), calendar: Calendar = .current) -> String {
        switch self {
        case .oneHour: return "In 1 hour"
        case .threeHours: return "In 3 hours"
        case .twelveHours: return "In 12 hours"
        case .tomorrowMorning: return calendar.isDate(date(from: now, calendar: calendar), inSameDayAs: now) ? "This morning" : "Tomorrow morning"
        case .evening: return calendar.isDate(date(from: now, calendar: calendar), inSameDayAs: now) ? "This evening" : "Tomorrow evening"
        case .weekend: return "This weekend"
        case .nextWeek: return "Next week"
        }
    }
    /// The settings label, independent of the current time.
    var settingsTitle: String {
        switch self {
        case .oneHour: return "In 1 hour"
        case .threeHours: return "In 3 hours"
        case .twelveHours: return "In 12 hours"
        case .tomorrowMorning: return "Next morning, 9 AM"
        case .evening: return "Evening, 9 PM"
        case .weekend: return "Weekend, Sat 9 AM"
        case .nextWeek: return "Next week, Mon 9 AM"
        }
    }
    func date(from now: Date = Date(), calendar: Calendar = .current) -> Date {
        func at(_ hour: Int, daysAhead: Int) -> Date {
            let day = calendar.date(byAdding: .day, value: daysAhead, to: calendar.startOfDay(for: now)) ?? now
            return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? now.addingTimeInterval(86_400)
        }
        func next(weekday: Int) -> Date {
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
            let day = calendar.nextDate(after: tomorrow.addingTimeInterval(-1), matching: DateComponents(weekday: weekday), matchingPolicy: .nextTime) ?? tomorrow
            return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day
        }
        let hour = calendar.component(.hour, from: now)
        switch self {
        case .oneHour: return now.addingTimeInterval(3_600)
        case .threeHours: return now.addingTimeInterval(3 * 3_600)
        case .twelveHours: return now.addingTimeInterval(12 * 3_600)
        // Before 5 AM, "next morning" is still the coming morning.
        case .tomorrowMorning: return at(9, daysAhead: hour < 5 ? 0 : 1)
        case .evening: return at(21, daysAhead: hour < 20 ? 0 : 1)
        case .weekend: return next(weekday: 7)
        case .nextWeek: return next(weekday: 2)
        }
    }
}

struct SavedState: Codable {
    var notes: [StickyNote]
    var preferences: Preferences
    var pendingFileDeletions: [String]? = nil
}

extension NSColor {
    static func hex(_ value: UInt32, alpha: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat((value >> 16) & 255) / 255,
                green: CGFloat((value >> 8) & 255) / 255,
                blue: CGFloat(value & 255) / 255, alpha: alpha)
    }
}
