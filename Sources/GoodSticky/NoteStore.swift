import AppKit

enum AttachmentImportError: LocalizedError {
    case notRegularFile
    var errorDescription: String? { "Choose a regular file instead of a folder or Finder alias." }
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
    private var histories: [UUID: NoteHistory] = [:]
    private var pendingSave: DispatchWorkItem?
    private var pendingFileDeletions = Set<String>()
    private let importer = DispatchQueue(label: "app.goodsticky.attachments", qos: .utility)
    private let writer = DispatchQueue(label: "app.goodsticky.persistence", qos: .utility)
    private(set) var loadFailed = false

    init(directory: URL? = nil) {
        self.directory = directory ?? LibraryLocation.directory
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
        if !notes[index].hidden { notes[index].snoozedUntil = nil }
        let removed = notes[index].hidden && notes[index].isBlank
        if removed { remove(id) }
        save()
        if notify || removed { onChange?() }
    }
    func updateMany(_ ids: [UUID], notify: Bool = true, _ body: (inout StickyNote) -> Void) {
        let selected = Set(ids)
        let now = Date()
        var changed = false
        for index in notes.indices where selected.contains(notes[index].id) {
            body(&notes[index]); notes[index].modified = now; changed = true
            // A note shown by any route is no longer snoozed.
            if !notes[index].hidden { notes[index].snoozedUntil = nil }
        }
        guard changed else { return }
        let removed = discardBlankHidden(selected)
        save()
        if notify || removed { onChange?() }
    }
    /// Blank notes are deleted as soon as they are hidden; there is nothing to keep.
    @discardableResult func discardBlankHidden(_ ids: Set<UUID>? = nil) -> Bool {
        let doomed = notes.filter { $0.hidden && $0.isBlank && ids?.contains($0.id) != false }.map(\.id)
        doomed.forEach(remove)
        return !doomed.isEmpty
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
    /// Adds a fully configured note without notifying; the caller synchronizes the desktop.
    func insert(_ note: StickyNote) {
        guard !loadFailed else { return }
        notes.append(note)
        save()
    }
    /// Hidden notes whose snooze has ended return to the desktop. Returns the woken notes.
    @discardableResult func wakeSnoozed(at now: Date = Date()) -> [UUID] {
        let due = notes.filter { $0.hidden && ($0.snoozedUntil.map { $0 <= now } ?? false) }.map(\.id)
        if !due.isEmpty { updateMany(due) { $0.hidden = false } }
        return due
    }
    /// The earliest pending snooze among hidden notes.
    var nextSnoozeWake: Date? { notes.compactMap { $0.hidden ? $0.snoozedUntil : nil }.min() }
    func undoManager(for id: UUID) -> UndoManager? { histories[id]?.manager }
    func history(for id: UUID) -> NoteHistory {
        if let history = histories[id] { return history }
        let history = NoteHistory()
        history.text = { [weak self] in self?.note(id)?.text }
        history.apply = { [weak self] text in self?.update(id) { $0.text = text } }
        histories[id] = history
        return history
    }
    func delete(_ id: UUID) {
        guard note(id) != nil else { return }
        remove(id)
        save()
        onChange?()
    }
    private func remove(_ id: UUID) {
        guard let note = note(id) else { return }
        histories.removeValue(forKey: id)
        notes.removeAll { $0.id == id }
        if let stack = note.stackID {
            let remaining = notes.indices.filter { notes[$0].stackID == stack }
            if remaining.count == 1 { notes[remaining[0]].stackID = nil }
        }
        pendingFileDeletions.formUnion(note.attachments.map(\.storedName))
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
                    let source = url.resolvingSymlinksInPath()
                    let info = try source.resourceValues(forKeys: [.isRegularFileKey, .isAliasFileKey])
                    guard source.isFileURL, info.isRegularFile == true, info.isAliasFile != true else { throw AttachmentImportError.notRegularFile }
                    let name = UUID().uuidString + "-" + url.lastPathComponent
                    let attachment = Attachment(name: url.lastPathComponent, storedName: name)
                    try FileManager.default.copyItem(at: source, to: destination.appendingPathComponent(name))
                    copied.append(attachment)
                } catch { errors.append("Couldn’t attach \(url.lastPathComponent): \(error.localizedDescription)") }
            }
            DispatchQueue.main.async {
                guard let self else { completion?(); return }
                if self.note(id) != nil && !copied.isEmpty {
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
