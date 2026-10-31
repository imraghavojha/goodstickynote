import AppKit

final class NoteTextView: NSTextView {
    weak var history: NoteHistory?
    private var pendingEdits: [(NoteHistory.Edit, NSRange)] = []
    private var composing = false
    override var undoManager: UndoManager? { history?.manager }
    override func shouldChangeText(in affectedCharRange: NSRange, replacementString: String?) -> Bool {
        guard super.shouldChangeText(in: affectedCharRange, replacementString: replacementString) else { return false }
        if let replacementString, NSMaxRange(affectedCharRange) <= (textStorage?.length ?? 0) {
            pendingEdits.append((NoteHistory.Edit(range: affectedCharRange, removed: affectedCharRange.length == 0 ? "" : (textStorage?.mutableString.substring(with: affectedCharRange) ?? ""), inserted: replacementString), selectedRange()))
        }
        return true
    }
    override func didChangeText() {
        for (edit, before) in pendingEdits { history?.record(edit, before: before, after: selectedRange(), composing: composing || hasMarkedText()) }
        pendingEdits.removeAll(keepingCapacity: true)
        history?.selection = selectedRange()
        super.didChangeText()
    }
    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        if !hasMarkedText() { history?.breakCoalescing() }
        composing = true
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
        composing = false
    }
    override func unmarkText() { super.unmarkText(); history?.breakCoalescing() }
    @objc func undo(_ sender: Any?) { undoManager?.undo(); restoreSelection() }
    @objc func redo(_ sender: Any?) { undoManager?.redo(); restoreSelection() }
    func restoreSelection() {
        guard let selection = history?.selection, NSMaxRange(selection) <= (textStorage?.length ?? 0) else { return }
        setSelectedRange(selection); scrollRangeToVisible(selection)
    }
    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(undo(_:)) { return history?.canUndo == true }
        if item.action == #selector(redo(_:)) { return history?.canRedo == true }
        return super.validateUserInterfaceItem(item)
    }
    var onFiles: (([URL]) -> Void)?
    var onCycle: ((Int) -> Void)?
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 48 && event.modifierFlags.contains(.control) && !event.modifierFlags.contains(.command) && !event.modifierFlags.contains(.option) {
            onCycle?(event.modifierFlags.contains(.shift) ? -1 : 1); return
        }
        super.keyDown(with: event)
    }
    override func cancelOperation(_ sender: Any?) {
        AppDelegate.shared.returnNotesToDesktop()
        window?.resignKey()
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) { return .copy }
        return super.draggingEntered(sender)
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        if !urls.isEmpty { onFiles?(urls); return true }
        return super.performDragOperation(sender)
    }
    override func paste(_ sender: Any?) {
        let urls = NSPasteboard.general.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        if !urls.isEmpty { onFiles?(urls) } else { pasteAsPlainText(sender) }
    }
}

