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
