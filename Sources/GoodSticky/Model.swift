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
        text.split(whereSeparator: \.isNewline).first.map(String.init) ?? "Untitled note"
    }
    var theme: NoteTheme { .get(themeID) }
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

final class NoteStore {
    static let shared = NoteStore()
    var notes: [StickyNote] = []
    var preferences = Preferences()
    var onChange: (() -> Void)?
    var onImportsFinished: (() -> Void)?
    private(set) var pendingImports = 0
    var onError: ((String) -> Void)?
    let directory: URL
    private var pendingSave: DispatchWorkItem?
    private var pendingFileDeletions = Set<String>()
    private let importer = DispatchQueue(label: "app.goodsticky.attachments", qos: .utility)
    private let writer = DispatchQueue(label: "app.goodsticky.persistence", qos: .utility)
    private(set) var loadFailed = false

    init(directory: URL? = nil) {
        self.directory = directory ?? ProcessInfo.processInfo.environment["GOODSTICKY_DATA_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) } ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("GoodSticky", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: self.directory.appendingPathComponent("Attachments"), withIntermediateDirectories: true)
            let file = self.directory.appendingPathComponent("notes.json")
            if FileManager.default.fileExists(atPath: file.path) {
                let state = try JSONDecoder().decode(SavedState.self, from: Data(contentsOf: file))
                notes = state.notes
                preferences = state.preferences
                pendingFileDeletions = Set(state.pendingFileDeletions ?? [])
            }
        } catch {
            loadFailed = true
            // Never overwrite an unreadable library with an empty one.
            NSLog("GoodSticky: Could not load library: %@", error.localizedDescription)
        }
    }

    func note(_ id: UUID) -> StickyNote? { notes.first { $0.id == id } }
    func update(_ id: UUID, notify: Bool = true, _ body: (inout StickyNote) -> Void) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        body(&notes[index])
        notes[index].modified = Date()
        save()
        if notify { onChange?() }
    }
    func updateMany(_ ids: [UUID], notify: Bool = true, _ body: (inout StickyNote) -> Void) {
        let selected = Set(ids)
        let now = Date()
        var changed = false
        for index in notes.indices where selected.contains(notes[index].id) {
            body(&notes[index]); notes[index].modified = now; changed = true
        }
        guard changed else { return }
        save()
        if notify { onChange?() }
    }
    @discardableResult func add(text: String = "", theme: String? = nil) -> StickyNote {
        var note = StickyNote()
        note.text = text
        note.themeID = theme ?? preferences.defaultTheme
        note.opacity = preferences.defaultOpacity
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main {
            let frame = screen.visibleFrame
            let offset = CGFloat(notes.filter { !$0.hidden }.count % 6) * 24
            note.x = frame.midX - 110 + offset
            note.y = frame.midY - 90 - offset
        }
        notes.append(note)
        save()
        onChange?()
        return note
    }
    func delete(_ id: UUID) {
        guard let note = note(id) else { return }
        notes.removeAll { $0.id == id }
        if let stack = note.stackID {
            let remaining = notes.indices.filter { notes[$0].stackID == stack }
            if remaining.count == 1 { notes[remaining[0]].stackID = nil }
        }
        pendingFileDeletions.formUnion(note.attachments.map(\.storedName))
        save()
        onChange?()
    }
    func attachmentURL(_ attachment: Attachment) -> URL {
        directory.appendingPathComponent("Attachments").appendingPathComponent(attachment.storedName)
    }
    func attach(_ urls: [URL], to id: UUID, completion: (() -> Void)? = nil) {
        guard note(id) != nil, !loadFailed else { completion?(); return }
        pendingImports += 1
        let destination = directory.appendingPathComponent("Attachments")
        importer.async { [weak self] in
            var copied: [Attachment] = []
            var errors: [String] = []
            for url in urls {
                do {
                    let name = UUID().uuidString + "-" + url.lastPathComponent
                    let attachment = Attachment(name: url.lastPathComponent, storedName: name)
                    try FileManager.default.copyItem(at: url, to: destination.appendingPathComponent(name))
                    copied.append(attachment)
                } catch { errors.append("Couldn’t attach \(url.lastPathComponent): \(error.localizedDescription)") }
            }
            DispatchQueue.main.async {
                guard let self else { completion?(); return }
                if self.note(id) != nil {
                    self.update(id) { $0.attachments.append(contentsOf: copied) }
                } else {
                    for attachment in copied { try? FileManager.default.removeItem(at: self.attachmentURL(attachment)) }
                }
                if !errors.isEmpty { self.onError?(errors.joined(separator: "\n")) }
                completion?()
                self.pendingImports -= 1
                if self.pendingImports == 0 { self.onImportsFinished?() }
            }
        }
    }
    func removeAttachment(_ attachment: Attachment, from id: UUID) {
        guard note(id)?.attachments.contains(where: { $0.id == attachment.id }) == true else { return }
        pendingFileDeletions.insert(attachment.storedName)
        update(id) { $0.attachments.removeAll { $0.id == attachment.id } }
    }
    private func snapshot() -> SavedState {
        SavedState(notes: notes, preferences: preferences, pendingFileDeletions: Array(pendingFileDeletions))
    }
    // The atomic library commit always precedes file cleanup. Persisted tombstones
    // let a later save retry cleanup if the process exits between these operations.
    private func commit(_ state: SavedState) throws -> Set<String> {
        try JSONEncoder().encode(state).write(to: directory.appendingPathComponent("notes.json"), options: .atomic)
        let referenced = Set(state.notes.flatMap { $0.attachments.map(\.storedName) })
        var removed = Set<String>()
        for name in state.pendingFileDeletions ?? [] where !referenced.contains(name) {
            // Tombstones only name files in this library, never an arbitrary path.
            guard !name.isEmpty, name != ".", name != "..", URL(fileURLWithPath: name).lastPathComponent == name else { continue }
            let file = directory.appendingPathComponent("Attachments").appendingPathComponent(name)
            do {
                if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
                removed.insert(name)
            } catch { /* Keep the tombstone for the next commit. */ }
        }
        return removed
    }
    func save() {
        guard !loadFailed else { return }
        pendingSave?.cancel()
        let state = snapshot()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            do {
                let removed = try self.commit(state)
                DispatchQueue.main.async { self.pendingFileDeletions.subtract(removed) }
            } catch {
                DispatchQueue.main.async { self.onError?("Couldn’t save your notes: \(error.localizedDescription)") }
            }
        }
        pendingSave = work
        writer.asyncAfter(deadline: .now() + 0.35, execute: work)
    }
    func flush() throws {
        guard !loadFailed else { return }
        pendingSave?.cancel()
        let state = snapshot()
        let removed = try writer.sync { try commit(state) }
        pendingFileDeletions.subtract(removed)
    }
}
