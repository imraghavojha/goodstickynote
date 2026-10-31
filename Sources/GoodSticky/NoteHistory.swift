import Foundation

/// Session undo stores changed text and selections, never a text view or layout manager.
final class NoteHistory {
    struct Edit {
        var range: NSRange
        var removed: String
        var inserted: String
        var insertedLength: Int
        init(range: NSRange, removed: String, inserted: String) {
            self.range = range; self.removed = removed; self.inserted = inserted
            insertedLength = inserted.utf16.count
        }
    }
    struct Group {
        var edits: [Edit]
        var before: NSRange
        var after: NSRange
    }
    private var past: [Group] = []
    private var future: [Group] = []
    private var lastEditTime = Date.distantPast
    private var canCoalesce = false
    var selection = NSRange(location: 0, length: 0)
    var apply: ((String) -> Void)?
    var text: (() -> String?)?
    lazy var manager = HistoryUndoManager(history: self)
    var canUndo: Bool { !past.isEmpty }
    var canRedo: Bool { !future.isEmpty }

    func breakCoalescing() { canCoalesce = false }

    func record(_ edit: Edit, before: NSRange, after: NSRange, composing: Bool = false, time: Date = Date()) {
        guard edit.removed != edit.inserted else { return }
        future.removeAll(keepingCapacity: true)
        let contiguous = canCoalesce && time.timeIntervalSince(lastEditTime) < 2 && past.last?.after == before
        var merged = false
        if contiguous {
            let group = past.count - 1
            let index = past[group].edits.count - 1
            let previousRange = past[group].edits[index].range
            if previousRange.length == 0 && edit.range.length == 0 &&
                edit.range.location == previousRange.location + past[group].edits[index].insertedLength &&
                !edit.inserted.contains("\n") {
                past[group].edits[index].inserted += edit.inserted
                past[group].edits[index].insertedLength += edit.insertedLength
                merged = true
            } else if past[group].edits[index].inserted.isEmpty && edit.inserted.isEmpty {
                if NSMaxRange(edit.range) == previousRange.location {
                    past[group].edits[index].range = NSRange(location: edit.range.location, length: edit.range.length + previousRange.length)
                    past[group].edits[index].removed = edit.removed + past[group].edits[index].removed
                    merged = true
                } else if edit.range.location == previousRange.location {
                    past[group].edits[index].range.length += edit.range.length
                    past[group].edits[index].removed += edit.removed
                    merged = true
                }
            }
            if !merged && composing { past[group].edits.append(edit); merged = true }
            if merged { past[group].after = after }
        }
        if !merged { past.append(Group(edits: [edit], before: before, after: after)) }
        selection = after
        lastEditTime = time
        // Selection replacements and pastes form their own undo steps.
        canCoalesce = composing || (before.length == 0 && (edit.inserted.isEmpty || (edit.range.length == 0 && edit.inserted.count == 1 && !edit.inserted.contains("\n"))))
    }

    func undo() { move(undoing: true) }
    func redo() { move(undoing: false) }
    private func move(undoing: Bool) {
        guard let original = text?(), let group = undoing ? past.last : future.last else { return }
        let buffer = NSMutableString(string: original)
        let edits = undoing ? Array(group.edits.reversed()) : group.edits
        for edit in edits {
            let expected = undoing ? edit.inserted : edit.removed
            let range = NSRange(location: edit.range.location, length: undoing ? edit.insertedLength : edit.range.length)
            guard NSMaxRange(range) <= buffer.length, buffer.substring(with: range) == expected else {
                // External content replacement invalidates positions; never apply a stale edit.
                clear(); return
            }
            buffer.replaceCharacters(in: range, with: undoing ? edit.removed : edit.inserted)
        }
        if undoing { past.removeLast(); future.append(group) }
        else { future.removeLast(); past.append(group) }
        selection = undoing ? group.before : group.after
        breakCoalescing()
        apply?(buffer as String)
    }
    func clear() {
        past.removeAll(); future.removeAll(); breakCoalescing()
    }
}

/// Keeps AppKit's Undo/Redo menus and responder chain working with detached history.
final class HistoryUndoManager: UndoManager {
    private weak var history: NoteHistory?
    init(history: NoteHistory) { self.history = history; super.init(); disableUndoRegistration() }
    override var canUndo: Bool { history?.canUndo == true }
    override var canRedo: Bool { history?.canRedo == true }
    override func undo() { history?.undo() }
    override func redo() { history?.redo() }
    override func removeAllActions() { history?.clear() }
}
