import AppKit

@main struct ModelTests {
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError("FAIL: " + message) }
        print("PASS: " + message)
    }
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("GoodStickyTests-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let lockDirectory = directory.appendingPathComponent("LockTest")
        var firstLock: ResidentLock? = try ResidentLock(directory: lockDirectory)
        withExtendedLifetime(firstLock) {
            var rejected = false
            do { _ = try ResidentLock(directory: lockDirectory) }
            catch ResidentLock.Failure.alreadyRunning { rejected = true }
            catch { fatalError("Unexpected lock failure: \(error)") }
            check(rejected, "A second writer is rejected while the library lock is held")
        }
        firstLock = nil
        let reopenedLock = try ResidentLock(directory: lockDirectory)
        withExtendedLifetime(reopenedLock) { check(true, "Library lock is released when its owner closes") }
        let store = NoteStore(directory: directory)
        var note = StickyNote()
        note.text = "A thought\n日本語 & emoji 🌿"
        note.themeID = "graphite"; note.opacity = 0.65; note.stackID = UUID()
        note.hidden = true; note.pinned = true; note.x = -240; note.width = 420
        store.notes = [note]; store.preferences.defaultTheme = "sage"; store.preferences.keyCode = 46
        try store.flush()
        let loaded = NoteStore(directory: directory)
        check(loaded.notes == [note], "Content, Unicode, position, theme, opacity, visibility, stacking round-trip")
        check(loaded.preferences.defaultTheme == "sage" && loaded.preferences.keyCode == 46, "Shortcut and defaults persist")
        for index in 0..<100 { store.update(note.id, notify: false) { $0.text = "Edit \(index)" } }
        try store.flush()
        check(NoteStore(directory: directory).note(note.id)?.text == "Edit 99", "Debounced edits flush latest content")
        let source = directory.appendingPathComponent("original.txt")
        try Data("Keep this file".utf8).write(to: source)
        var completed = false
        store.attach([source], to: note.id) { completed = true }
        let deadline = Date().addingTimeInterval(5)
        while !completed && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
        check(completed, "Background attachment import completes")
        check(store.pendingImports == 0, "Completed imports release the quit barrier")
        let attachment = store.note(note.id)!.attachments[0]
        try FileManager.default.removeItem(at: source)
        let copied = try String(contentsOf: store.attachmentURL(attachment), encoding: .utf8)
        check(copied == "Keep this file", "Attachment is independent of original")
        let linkedSource = directory.appendingPathComponent("linked-source.txt")
        let symlink = directory.appendingPathComponent("reference.txt")
        try Data("Independent link contents".utf8).write(to: linkedSource)
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: linkedSource)
        var linked = false
        store.attach([symlink], to: note.id) { linked = true }
        let linkDeadline = Date().addingTimeInterval(5)
        while !linked && Date() < linkDeadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
        check(linked, "Symbolic-link import completes")
        let linkedAttachment = store.note(note.id)!.attachments.last!
        try FileManager.default.removeItem(at: linkedSource)
        let linkCopy = try String(contentsOf: store.attachmentURL(linkedAttachment), encoding: .utf8)
        let copyInfo = try store.attachmentURL(linkedAttachment).resourceValues(forKeys: [.isSymbolicLinkKey])
        check(linkCopy == "Independent link contents" && copyInfo.isSymbolicLink != true, "Imported symlink becomes independent file contents")
        let priorAttachments = store.note(note.id)!.attachments
        var importErrors: [String] = []; store.onError = { importErrors.append($0) }
        var folderFinished = false
        store.attach([directory], to: note.id) { folderFinished = true }
        let folderDeadline = Date().addingTimeInterval(5)
        while !folderFinished && Date() < folderDeadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
        check(folderFinished && !importErrors.isEmpty && store.note(note.id)!.attachments == priorAttachments, "Folder drops are rejected without changing attachments")
        store.onError = nil
        try store.flush()
        store.delete(note.id)
        check(FileManager.default.fileExists(atPath: store.attachmentURL(attachment).path), "Uncommitted deletion retains the copied attachment")
        let crashRecovery = NoteStore(directory: directory)
        check(crashRecovery.note(note.id)?.attachments.first == attachment, "Crash before commit restores the note and attachment reference")
        try store.flush()
        check(!FileManager.default.fileExists(atPath: store.attachmentURL(attachment).path), "Deleting note cleans up attachments")
        check(NoteStore(directory: directory).notes.isEmpty, "Note deletion persists")
        // Force a real write failure without relying on Unix permissions or the current UID.
        var failureNote = StickyNote()
        let protectedAttachment = Attachment(name: "protected.txt", storedName: "protected.txt")
        failureNote.attachments = [protectedAttachment]
        try Data("Must survive a failed save".utf8).write(to: store.attachmentURL(protectedAttachment))
        store.notes = [failureNote]; try store.flush()
        let libraryFile = directory.appendingPathComponent("notes.json")
        let backup = directory.appendingPathComponent("previous.json")
        try FileManager.default.moveItem(at: libraryFile, to: backup)
        try FileManager.default.createDirectory(at: libraryFile, withIntermediateDirectories: false)
        store.removeAttachment(protectedAttachment, from: failureNote.id)
        var saveFailed = false
        do { try store.flush() } catch { saveFailed = true }
        check(saveFailed, "Final-save errors propagate to the termination gate")
        check(FileManager.default.fileExists(atPath: store.attachmentURL(protectedAttachment).path), "Failed library commit cannot unlink an attachment")
        let lastCommitted = try JSONDecoder().decode(SavedState.self, from: Data(contentsOf: backup))
        check(lastCommitted.notes.first?.attachments.first == protectedAttachment, "Last committed state keeps its usable attachment")
        try FileManager.default.removeItem(at: libraryFile)
        try FileManager.default.moveItem(at: backup, to: libraryFile)
        try store.flush()
        check(!FileManager.default.fileExists(atPath: store.attachmentURL(protectedAttachment).path), "Successful retry commits removal before cleanup")
        // Simulate an exit after the JSON commit but before its file cleanup.
        let orphan = Attachment(name: "orphan.txt", storedName: "orphan.txt")
        try Data("cleanup".utf8).write(to: store.attachmentURL(orphan))
        let interrupted = SavedState(notes: [], preferences: Preferences(), pendingFileDeletions: [orphan.storedName])
        try JSONEncoder().encode(interrupted).write(to: libraryFile, options: .atomic)
        let recovered = NoteStore(directory: directory)
        try recovered.flush()
        check(!FileManager.default.fileExists(atPath: recovered.attachmentURL(orphan).path), "Persisted deletion tombstones recover interrupted cleanup")
        // Cancelled debounced snapshots must not overwrite a synchronous final save.
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        check(NoteStore(directory: directory).notes.isEmpty, "Cancelled delayed saves cannot overwrite the final commit")
        // Hiding a blank note deletes it; whitespace counts as blank, files or text do not.
        let blankStore = NoteStore(directory: directory.appendingPathComponent("Blank"))
        var blankStack = StickyNote(); blankStack.text = "  \n "; blankStack.stackID = UUID()
        var partner = StickyNote(); partner.text = "Keep"; partner.stackID = blankStack.stackID
        var withFile = StickyNote(); withFile.attachments = [Attachment(name: "a.txt", storedName: "a.txt")]
        blankStore.notes = [blankStack, partner, withFile]
        blankStore.updateMany([blankStack.id, partner.id, withFile.id]) { $0.hidden = true }
        check(blankStore.note(blankStack.id) == nil && blankStore.note(partner.id)?.hidden == true && blankStore.note(withFile.id) != nil, "Hidden blank notes are discarded; notes with text or files are kept")
        check(blankStore.note(partner.id)?.stackID == nil, "Discarding a blank note dissolves a stack of one")
        try blankStore.flush()
        // Side notes and snoozes persist; libraries written before they existed still load.
        let featureStore = NoteStore(directory: directory.appendingPathComponent("Features"))
        var docked = StickyNote(); docked.text = "Side"; docked.dock = "right"
        var napping = StickyNote(); napping.text = "Later"; napping.hidden = true; napping.snoozedUntil = Date(timeIntervalSince1970: 2_000_000_000)
        featureStore.notes = [docked, napping]; featureStore.preferences.snoozeOptions = [.nextWeek, .oneHour]
        try featureStore.flush()
        let reloaded = NoteStore(directory: featureStore.directory)
        check(reloaded.notes == [docked, napping] && reloaded.note(docked.id)?.dockEdge == .right, "Side-note edge and snooze time round-trip")
        check(reloaded.preferences.snoozeOptions == [.oneHour, .nextWeek], "Chosen snooze times persist in menu order")
        check(Preferences().snoozeOptions == [.tomorrowMorning, .evening, .twelveHours, .nextWeek], "Default snooze times: next morning, evening, 12 hours, next week")
        let legacy = #"{"notes":[{"id":"6F1B7A10-0C55-4E58-9D5E-2E7B8F0E9A11","text":"Old","themeID":"butter","opacity":1,"x":0,"y":0,"width":220,"height":180,"hidden":false,"pinned":false,"attachments":[],"created":0,"modified":0}],"preferences":{"keyCode":45,"modifiers":6144,"defaultTheme":"butter","defaultOpacity":1}}"#
        let legacyState = try JSONDecoder().decode(SavedState.self, from: Data(legacy.utf8))
        check(legacyState.notes.first?.dock == nil && legacyState.notes.first?.snoozedUntil == nil && legacyState.preferences.snoozeOptions == SnoozeOption.defaults, "Libraries from earlier versions load with no side notes or snoozes")
        check(reloaded.nextSnoozeWake == napping.snoozedUntil && reloaded.wakeSnoozed(at: Date(timeIntervalSince1970: 1_000_000_000)).isEmpty, "A pending snooze stays hidden")
        check(reloaded.wakeSnoozed(at: Date(timeIntervalSince1970: 2_000_000_001)) == [napping.id] && reloaded.note(napping.id)?.hidden == false && reloaded.note(napping.id)?.snoozedUntil == nil, "An ended snooze returns the note to the desktop")
        reloaded.update(napping.id) { $0.hidden = true; $0.snoozedUntil = Date(timeIntervalSince1970: 2_000_000_000) }
        reloaded.update(napping.id) { $0.hidden = false }
        check(reloaded.note(napping.id)?.snoozedUntil == nil && reloaded.nextSnoozeWake == nil, "Showing a snoozed note by hand cancels its snooze")
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "America/New_York")!
        func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int = 0) -> Date { calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))! }
        let friday = at(2026, 10, 30, 14, 30) // Friday afternoon
        check(SnoozeOption.tomorrowMorning.date(from: friday, calendar: calendar) == at(2026, 10, 31, 9), "Next morning is tomorrow at 9 AM")
        check(SnoozeOption.tomorrowMorning.date(from: at(2026, 10, 30, 2), calendar: calendar) == at(2026, 10, 30, 9), "In the small hours, next morning is the coming 9 AM")
        check(SnoozeOption.evening.date(from: friday, calendar: calendar) == at(2026, 10, 30, 21) && SnoozeOption.evening.title(from: friday, calendar: calendar) == "This evening", "Evening is tonight at 9 PM before 8 PM")
        check(SnoozeOption.evening.date(from: at(2026, 10, 30, 20, 30), calendar: calendar) == at(2026, 10, 31, 21), "Late evening snoozes to tomorrow at 9 PM")
        check(SnoozeOption.twelveHours.date(from: friday, calendar: calendar) == friday.addingTimeInterval(43_200), "12 hours from now")
        check(SnoozeOption.nextWeek.date(from: friday, calendar: calendar) == at(2026, 11, 2, 9), "Next week is Monday at 9 AM")
        check(SnoozeOption.nextWeek.date(from: at(2026, 11, 2, 7), calendar: calendar) == at(2026, 11, 9, 9), "On a Monday, next week is the following Monday")
        check(SnoozeOption.weekend.date(from: friday, calendar: calendar) == at(2026, 10, 31, 9), "This weekend is Saturday at 9 AM")
        let file = directory.appendingPathComponent("notes.json")
        let original = Data("not valid JSON".utf8); try original.write(to: file)
        let broken = NoteStore(directory: directory)
        check(broken.loadFailed, "Unreadable library detected")
        broken.notes = [StickyNote()]; broken.save(); try broken.flush()
        let untouched = try Data(contentsOf: file)
        check(untouched == original, "Unreadable library cannot be overwritten")
        print("All model checks passed.")
    }
}
