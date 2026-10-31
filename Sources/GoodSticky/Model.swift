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
    var attachments: [Attachment] = []
    var created = Date()
    var modified = Date()
    var title: String {
        text.split(maxSplits: 1, whereSeparator: \.isNewline).first.map(String.init) ?? "Untitled note"
    }
    var theme: NoteTheme { .get(themeID) }
    /// No visible text and no files: hiding it would only leave clutter behind.
    var isBlank: Bool { attachments.isEmpty && text.allSatisfy(\.isWhitespace) }
}

struct Preferences: Codable {
    var keyCode: UInt32 = 45 // N
    var modifiers: UInt32 = 0x1000 | 0x0800 // control + option (Carbon)
    var defaultTheme = "butter"
    var defaultOpacity = 1.0
    var desktopLayoutVersion: Int? = nil
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
