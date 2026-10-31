import AppKit

extension AppDelegate {
    func checkUndoHistory() {
        func check(_ value: @autoclosure () -> Bool, _ message: String) {
            if !value() { print("FAIL: " + message); fflush(stdout); fatalError(message) }; print("PASS: " + message); fflush(stdout)
        }
        let item = store.add(text: "Original 🌿")
        var widget = widgets[item.id.uuidString]!
        var editor: NoteTextView?
        weak var releasedEditor: NoteTextView?
        autoreleasepool {
        editor = widget.beginEditing()
        editor!.setSelectedRange(NSRange(location: (editor!.string as NSString).length, length: 0))
        editor!.insertText("a", replacementRange: editor!.selectedRange())
        editor!.insertText("b", replacementRange: editor!.selectedRange())
        check(store.note(item.id)?.text == "Original 🌿ab", "Native typing updates note")
        check(editor!.undoManager?.canUndo == true, "Native Undo menu sees detached history")
        editor!.undo(nil)
        check(editor!.string == "Original 🌿", "Typing coalesces into one undo")
        editor!.redo(nil)
        check(editor!.string == "Original 🌿ab", "Redo restores coalesced typing")
        releasedEditor = editor
        widget.window?.orderOut(nil); widget.endEditing(); editor = nil

        }
        check(widget.textView == nil, "Idle note releases its editor")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak releasedEditor] in
            check(releasedEditor == nil, "History retains no editor after AppKit drains its event")
        }
        widget.window?.makeKeyAndOrderFront(nil)
        widget.window?.makeFirstResponder(widget.window)
        let undoSent = NSApp.sendAction(Selector(("undo:")), to: nil, from: nil)
        check(undoSent && widget.textView == nil && store.note(item.id)?.text == "Original 🌿", "Responder-chain undo works without recreating an editor")
        let redoSent = NSApp.sendAction(Selector(("redo:")), to: nil, from: nil)
        check(redoSent && widget.textView == nil && store.note(item.id)?.text == "Original 🌿ab", "Responder-chain redo works without recreating an editor")
        editor = widget.beginEditing()
        editor!.undo(nil)
        check(editor!.string == "Original 🌿", "Undo survives editor release")
        editor!.redo(nil)
        check(editor!.string == "Original 🌿ab", "Redo survives editor release")
        editor!.setSelectedRange(NSRange(location: 9, length: 2))
        editor!.insertText("你好", replacementRange: editor!.selectedRange())
        editor!.undo(nil)
        check(editor!.string == "Original 🌿ab" && editor!.selectedRange() == NSRange(location: 9, length: 2), "Unicode replacement restores text and selection")
        editor!.insertText("x", replacementRange: NSRange(location: 0, length: 0))
        check(editor!.undoManager?.canRedo == false, "New edit discards redo")
        editor!.undo(nil)
        editor!.setSelectedRange(NSRange(location: (editor!.string as NSString).length, length: 0))
        editor!.history?.breakCoalescing()
        editor!.deleteBackward(nil); editor!.deleteBackward(nil)
        editor!.undo(nil)
        check(editor!.string == "Original 🌿ab", "Consecutive backspaces undo together")
        editor!.history?.breakCoalescing()
        editor!.setSelectedRange(NSRange(location: 0, length: 0))
        editor!.setMarkedText("ni", selectedRange: NSRange(location: 2, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        editor!.setMarkedText("你", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        editor!.insertText("你", replacementRange: NSRange(location: NSNotFound, length: 0))
        editor!.unmarkText()
        editor!.undo(nil)
        check(editor!.string == "Original 🌿ab", "IME composition undoes as one edit")
        editor!.redo(nil)
        check(editor!.string == "你Original 🌿ab", "IME redo restores committed text")
        editor = nil
        store.update(item.id) { $0.hidden = true }
        reveal(item.id)
        widget = widgets[item.id.uuidString]!
        editor = widget.beginEditing(); editor!.undo(nil)
        check(editor!.string == "Original 🌿ab", "Undo survives hide and restore")
        let other = store.add(text: "Other")
        stack(item.id, with: other.id)
        widget = widgets[store.note(item.id)!.stackID!.uuidString]!
        widget.select(other.id); widget.beginEditing().insertText("z", replacementRange: NSRange(location: 5, length: 0))
        widget.select(item.id); widget.beginEditing().undo(nil)
        check(store.note(item.id)?.text == "Original 🌿", "Stack switching keeps each note's history")
        check(store.note(other.id)?.text == "Otherz", "Undo does not affect a sibling note")
        unstack(item.id)
        editor = widgets[item.id.uuidString]!.beginEditing(); editor!.redo(nil)
        check(editor!.string == "Original 🌿ab", "Redo survives unstacking")
        weak var releasedHistory: NoteHistory?
        releasedHistory = editor!.history
        editor = nil
        store.delete(item.id); store.delete(other.id)
        widget = widgets.values.first!
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak releasedHistory] in
            check(releasedHistory == nil, "Deleting a note releases its history")
        }
    }
}
