import AppKit

extension AppDelegate {
    func seedWelcomeNotes() {
        let first = store.add(text: "Draft notes\n\nReview the outline\nSend the first draft", theme: "butter")
        let second = store.add(text: "Weekend\n\nCoffee beans\nBook the train", theme: "sage")
        let third = store.add(text: "Ideas\n\nA short list for later.", theme: "lilac")
        if let screen = NSScreen.main {
            for (index, id) in [first.id, second.id, third.id].enumerated() {
                store.update(id, notify: false) { $0.x = screen.visibleFrame.minX + 40 + CGFloat(index) * 240; $0.y = screen.visibleFrame.maxY - 230 }
            }
        }
    }
    func runSmokeTest() {
        checkUndoHistory { [self] in runSmokeScenarios() }
    }
    private func runSmokeScenarios() {
        let savedCount = store.notes.count
        func capture(_ view: NSView?, _ name: String) {
            guard let index = CommandLine.arguments.firstIndex(of: "--snapshot-dir"), CommandLine.arguments.count > index + 1, let view else { return }
            let directory = URL(fileURLWithPath: CommandLine.arguments[index + 1])
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            view.layoutSubtreeIfNeeded()
            guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try? bitmap.representation(using: .png, properties: [:])?.write(to: directory.appendingPathComponent(name + ".png"))
        }
        library?.window?.contentView?.layoutSubtreeIfNeeded(); library?.layoutRows()
        capture(library?.window?.contentView, "library")
        capture(widgets.values.first?.surface, "widget")
        if preferences == nil { preferences = PreferencesController() }
        capture(preferences?.window?.contentView, "preferences")
        let first = store.add(text: "Smoke test\nRound-trip", theme: "sky")
        let second = store.add(text: "Second smoke note", theme: "rose")
        store.update(first.id) { $0.opacity = 0.65 }
        stack(first.id, with: second.id)
        let stackID = store.note(first.id)!.stackID!
        let stacked = widgets[stackID.uuidString]?.ids.count == 2
        let image = NSImage(size: NSSize(width: 16, height: 16))
        image.lockFocus(); NSColor.systemBlue.setFill(); NSBezierPath(rect: NSRect(x: 0, y: 0, width: 16, height: 16)).fill(); image.unlockFocus()
        let picture = Attachment(name: "layout.png", storedName: "layout.png")
        let file = Attachment(name: "layout.txt", storedName: "layout.txt")
        do {
            let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
            try bitmap.representation(using: .png, properties: [:])!.write(to: store.attachmentURL(picture))
            try Data("layout".utf8).write(to: store.attachmentURL(file))
        } catch { preconditionFailure("Fixture creation failed: \(error)") }
        store.update(first.id) { $0.attachments = [picture, file] }
        let stackWidget = widgets[stackID.uuidString]!
        stackWidget.window?.setContentSize(NSSize(width: 220, height: 180))
        let dragWindow = stackWidget.window!
        let originalTop = dragWindow.frame.maxY
        let down = NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: 214, y: 6), modifierFlags: [], timestamp: 0, windowNumber: dragWindow.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
        let dragged = NSEvent.mouseEvent(with: .leftMouseDragged, location: NSPoint(x: 130, y: 94), modifierFlags: [], timestamp: 0, windowNumber: dragWindow.windowNumber, context: nil, eventNumber: 2, clickCount: 1, pressure: 1)!
        stackWidget.grip.mouseDown(with: down); stackWidget.grip.mouseDragged(with: dragged)
        let resizeGesture = dragWindow.frame.width == 140 && dragWindow.frame.height == 96 && dragWindow.frame.maxY == originalTop
        stackWidget.window?.setContentSize(NSSize(width: 140, height: 96))
        stackWidget.surface.layoutSubtreeIfNeeded()
        capture(stackWidget.surface, "minimum-stack")
        let minimumLayout = stackWidget.display.frame.height >= 28 && stackWidget.attachments.frame.height <= 60 && !stackWidget.dots.isHidden && stackWidget.dots.frame.height == 14 && stackWidget.dots.frame.maxX <= stackWidget.grip.frame.minX + 6
        stackWidget.window?.setContentSize(NSSize(width: 220, height: 280)); stackWidget.layoutNote()
        capture(stackWidget.surface, "attachments")
        let appearance = NoteAppearanceController(noteID: first.id)
        capture(appearance.view, "appearance")
        setPinned(first.id, pinned: true)
        let sharedPin = store.note(second.id)?.pinned == true
        stackWidget.activeID = second.id; stackWidget.refresh()
        stackWidget.beginEditing().setSelectedRange(NSRange(location: 3, length: 2))
        store.update(first.id) { $0.hidden = true }
        let preservedOnHide = widgets[stackID.uuidString] === stackWidget && stackWidget.activeID == second.id && stackWidget.textView?.selectedRange() == NSRange(location: 3, length: 2)
        store.update(first.id) { $0.hidden = false }
        let activeTabPreserved = preservedOnHide && widgets[stackID.uuidString] === stackWidget && stackWidget.activeID == second.id && stackWidget.textView?.selectedRange() == NSRange(location: 3, length: 2)
        stackWidget.activeID = first.id; stackWidget.refresh()

        let dotsValue = stackWidget.dots.accessibilityValue() as? String ?? ""
        let tabsAccessible = stackWidget.dots.accessibilityRole() == .tabGroup && dotsValue.hasPrefix("Note 1 of 2") && stackWidget.dots.range == 0..<2
        // Clicking the second dot shows the second note; a swipe brings the first back.
        let secondDot = NSPoint(x: stackWidget.dots.bounds.midX + PageDots.pitch / 2, y: stackWidget.dots.bounds.midY)
        if let index = stackWidget.dots.index(at: secondDot) { stackWidget.dots.onSelect?(index) }
        let dotSelects = stackWidget.activeID == second.id && stackWidget.dots.current == 1
        stackWidget.scroll?.onSwipe?(-1)
        let swipeSwitches = dotSelects && stackWidget.activeID == first.id && stackWidget.dots.current == 0
        let flush = widgets.values.allSatisfy { $0.window?.hasShadow == false && $0.surface.layer?.borderWidth == 0 }
        if let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .control, timestamp: 0, windowNumber: stackWidget.window!.windowNumber, context: nil, characters: "\t", charactersIgnoringModifiers: "\t", isARepeat: false, keyCode: 48) {
            stackWidget.textView?.keyDown(with: event)
        }
        let keyboardCycle = stackWidget.activeID == second.id
        stackWidget.activeID = first.id; stackWidget.refresh()
        showLibrary()
        library?.refresh()
        let card = library?.grid.subviews.compactMap { $0 as? NoteCard }.first { $0.note != nil }
        let cardFocused = card.map { library?.window?.makeFirstResponder($0) == true } ?? false
        let focusedControls = card?.subviews.compactMap { $0 as? NSButton }.filter { $0.toolTip == "Copy note" }.allSatisfy { !$0.isHidden } == true

        setPinned(first.id, pinned: false)
        bringAllForward()
        // Focusing another widget must not lower previously raised notes.
        for widget in widgets.values { widget.window?.makeKeyAndOrderFront(nil) }
        let allRaised = widgets.values.allSatisfy { $0.window?.level == .floating }
        returnNotesToDesktop()

        store.update(first.id) { $0.hidden = true }
        let hidden = widgets[stackID.uuidString]?.ids.count == 1
        reveal(first.id)
        let restored = widgets[stackID.uuidString]?.ids.count == 2
        store.update(first.id) { $0.stackID = nil }
        let unstacked = widgets[first.id.uuidString] != nil
        library?.close()
        preferences?.close()
        let staysAfterClosingUI = library == nil && widgets.values.allSatisfy { $0.window?.isVisible == true } && NSRunningApplication.current.activationPolicy == .accessory
        let importSource = store.directory.appendingPathComponent("import-source.txt")
        try! Data("import fixture".utf8).write(to: importSource)
        store.attach([importSource], to: second.id)
        let systemReply = replyToTermination
        var cancellationReply: Bool?
        replyToTermination = { cancellationReply = $0 }
        let delayedReply = applicationShouldTerminate(NSApp) == .terminateLater
        let quitWaitVisible = delayedReply && waitingToQuit && quitProgress?.window?.isVisible == true
        cancelPendingQuit()
        let quitWaitCancelled = !waitingToQuit && quitProgress == nil && cancellationReply == false
        replyToTermination = systemReply
        let broken = Attachment(name: "broken.png", storedName: "broken.png")
        try! Data("invalid picture".utf8).write(to: store.attachmentURL(broken))
        func finish(coalesced: Bool, failedPreviewCollapsed: Bool) {
            if store.pendingImports > 0 {
                let previous = store.onImportsFinished
                store.onImportsFinished = { [self] in
                    self.store.onImportsFinished = previous
                    previous?()
                    finish(coalesced: coalesced, failedPreviewCollapsed: failedPreviewCollapsed)
                }
                return
            }
            store.delete(first.id); store.delete(second.id)
            // Hiding a blank note deletes it; hidden notes delete without a confirmation.
            let blank = store.add()
            store.update(blank.id) { $0.hidden = true }
            let blankDiscarded = store.note(blank.id) == nil && widgets[blank.id.uuidString] == nil
            let kept = store.add(text: "Keep me hidden")
            store.update(kept.id) { $0.hidden = true }
            showLibrary(); library?.filter.selectedSegment = 1; library?.refresh()
            let hiddenCard = library?.cards.first { $0.note?.id == kept.id }
            let trashVisible = hiddenCard?.deleteButton?.isHidden == false
            capture(library?.window?.contentView, "library-hidden")
            hiddenCard?.deleteButton?.actionHandler?()
            let hiddenDeleted = trashVisible && store.note(kept.id) == nil
            library?.close()
            // Notes overlap freely; only a note dropped squarely on top of another stacks.
            let lower = store.add(text: "Drop target"), upper = store.add(text: "Dragged note")
            store.updateMany([lower.id, upper.id]) { $0.pinned = true }
            let target = widgets[lower.id.uuidString]!, dragged = widgets[upper.id.uuidString]!
            let screen = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
            target.window?.setFrame(NSRect(x: screen.minX + 80, y: screen.minY + 80, width: 220, height: 180), display: true)
            dragged.window?.setFrame(NSRect(x: screen.minX + 420, y: screen.minY + 80, width: 220, height: 180), display: true)
            target.window?.level = .floating; dragged.window?.level = .floating
            target.window?.orderFrontRegardless(); dragged.beginMove()
            func drag(to origin: NSPoint) {
                dragged.window?.setFrameOrigin(origin)
                // Let WindowServer apply the new frames and ordering, as between real drag events.
                CATransaction.flush(); RunLoop.current.run(until: Date().addingTimeInterval(0.1))
                dragged.trackDrag(at: NSPoint(x: origin.x + 40, y: origin.y + 166))
            }
            let base = target.window!.frame.origin
            drag(to: NSPoint(x: base.x + 110, y: base.y + 30))
            let overlapOnly = !target.surface.stackTarget
            drag(to: NSPoint(x: base.x + 10, y: base.y - 8))
            let armed = target.surface.stackTarget && dragged.surface.layer?.animation(forKey: "stackArm") != nil
            drag(to: NSPoint(x: base.x + 150, y: base.y))
            let disarmed = !target.surface.stackTarget
            drag(to: NSPoint(x: base.x + 6, y: base.y + 4))
            let highlighted = target.surface.stackTarget
            let releasePoint = NSPoint(x: dragged.window!.frame.minX + 40, y: dragged.window!.frame.minY + 166)
            dragged.finishMove(at: releasePoint)
            let dropStacked = overlapOnly && armed && disarmed && highlighted && !target.surface.stackTarget && store.note(lower.id)?.stackID != nil && store.note(lower.id)?.stackID == store.note(upper.id)?.stackID
            store.delete(lower.id); store.delete(upper.id)
            // Swiping past the last note adds a page; leaving a blank page discards it.
            let page = store.add(text: "First page")
            let pageWidget = widgets[page.id.uuidString]!
            pageWidget.cycle(1, extending: true)
            let swipeAdds = store.note(page.id)?.stackID.flatMap { widgets[$0.uuidString] } === pageWidget && pageWidget.ids.count == 2 && pageWidget.activeID != page.id && store.note(pageWidget.activeID)?.isBlank == true
            pageWidget.cycle(1, extending: true)
            let blankNotRepeated = pageWidget.ids.count == 2
            pageWidget.cycle(-1, extending: true)
            let blankPageDiscarded = swipeAdds && blankNotRepeated && pageWidget.ids == [page.id] && store.note(page.id)?.stackID == nil && widgets[page.id.uuidString] === pageWidget
            pageWidget.window?.resignKey()
            store.delete(page.id)
            // Side notes: tucked into the edge as a tab, slid out on demand, tucked away again.
            let side = store.add(text: "Side note")
            let sideWidget = widgets[side.id.uuidString]!
            let sideScreen = sideWidget.window?.screen ?? NSScreen.main!
            let edgePoint = NSPoint(x: sideScreen.frame.maxX - 1, y: sideScreen.frame.midY)
            let rightIsOuter = !NSScreen.screens.contains { $0 !== sideScreen && $0.frame.minX >= sideScreen.frame.maxX - 1 && $0.frame.minY <= edgePoint.y && $0.frame.maxY >= edgePoint.y }
            let edgeDetected = !rightIsOuter || sideWidget.dockEdge(at: edgePoint, frame: sideWidget.window!.frame) == .right
            let notEdge = sideWidget.dockEdge(at: NSPoint(x: sideScreen.frame.midX, y: sideScreen.frame.midY), frame: NSRect(x: sideScreen.frame.midX, y: sideScreen.frame.midY, width: 220, height: 180)) == nil
            sideWidget.dock(to: .right, at: edgePoint)
            // The remaining checks wait on real timers from the top-level run loop, so nested
            // run loops never hold AppKit's pending autorelease work (see checkUndoHistory).
            WidgetController.after(0.4) { [self] in
            let edgeX = sideScreen.visibleFrame.maxX
            let tucked = sideWidget.collapsed && sideWidget.window?.isVisible == false && sideWidget.tab?.isVisible == true && sideWidget.tab?.frame.maxX == edgeX && store.note(side.id)?.dock == "right"
            sideWidget.expand()
            let slidOut = !sideWidget.collapsed && sideWidget.window?.isVisible == true && sideWidget.window?.frame.maxX == edgeX && sideWidget.tab?.isVisible == false && sideWidget.window?.level == .floating
            let pointerAway = !(sideWidget.window?.frame.insetBy(dx: -6, dy: -6).contains(NSEvent.mouseLocation) ?? true)
            WidgetController.after(0.9) { [self] in
            let autoTucked = !pointerAway || (sideWidget.collapsed && sideWidget.window?.isVisible == false)
            sideWidget.expand(); sideWidget.undock()
            let undocked = store.note(side.id)?.dock == nil && !sideWidget.collapsed && sideWidget.tab == nil && sideWidget.window?.isVisible == true
            let sideNotes = edgeDetected && notEdge && tucked && slidOut && autoTucked && undocked
            if !sideNotes { print("Side notes: edge=\(edgeDetected) notEdge=\(notEdge) tucked=\(tucked) slidOut=\(slidOut) autoTucked=\(autoTucked) undocked=\(undocked)") }
            store.delete(side.id)
            // Snooze: the snooze button sits next to copy; a snoozed note returns by itself.
            let napper = store.add(text: "Nap")
            let napWidget = widgets[napper.id.uuidString]!
            napWidget.ensureControls()
            let snoozeButton = (napWidget.controls?.arrangedSubviews.map(\.toolTip) ?? []).prefix(2) == ["Copy note", "Snooze note"]
            napWidget.snooze(until: Date().addingTimeInterval(0.3))
            let snoozed = store.note(napper.id)?.hidden == true && store.note(napper.id)?.snoozedUntil != nil && widgets[napper.id.uuidString] == nil
            WidgetController.after(2.8) { [self] in
            let woke = store.note(napper.id)?.hidden == false && store.note(napper.id)?.snoozedUntil == nil && widgets[napper.id.uuidString]?.window?.level == .floating
            returnNotesToDesktop()
            let snooze = snoozeButton && snoozed && woke
            if !snooze { print("Snooze: button=\(snoozeButton) snoozed=\(snoozed) woke=\(woke)") }
            store.delete(napper.id)
            // Editors are created on demand and released back to the cheap display.
            let solo = store.add(text: "Solo")
            let soloWidget = widgets[solo.id.uuidString]!
            let idleWithoutEditor = soloWidget.textView == nil && !soloWidget.display.isHidden
            let editor = soloWidget.beginEditing()
            editor.setSelectedRange(NSRange(location: editor.string.count, length: 0)); editor.insertText(" edited", replacementRange: editor.selectedRange())
            soloWidget.window?.resignKey(); soloWidget.endEditing()
            let editorRoundTrip = idleWithoutEditor && soloWidget.textView == nil && !soloWidget.display.isHidden && soloWidget.display.text == "Solo edited" && store.note(solo.id)?.text == "Solo edited"
            store.delete(solo.id)
            do { try store.flush() } catch { preconditionFailure("Smoke save failed: \(error)") }
            print("SMOKE TEST: stacked=\(stacked) hidden=\(hidden) restored=\(restored) unstacked=\(unstacked) minimumLayout=\(minimumLayout) resizeGesture=\(resizeGesture) sharedPin=\(sharedPin) allRaised=\(allRaised) tabsAccessible=\(tabsAccessible) keyboardCycle=\(keyboardCycle) focusedControls=\(cardFocused && focusedControls) staysAfterClosingUI=\(staysAfterClosingUI) activeTabPreserved=\(activeTabPreserved) quitWaitVisible=\(quitWaitVisible) quitWaitCancelled=\(quitWaitCancelled) thumbnailCoalesced=\(coalesced) failedPreviewCollapsed=\(failedPreviewCollapsed) dotSelects=\(dotSelects) swipeSwitches=\(swipeSwitches) flush=\(flush) blankDiscarded=\(blankDiscarded) hiddenDeleted=\(hiddenDeleted) dropStacked=\(dropStacked) swipeAddsNote=\(blankPageDiscarded) sideNotes=\(sideNotes) snooze=\(snooze) editorRoundTrip=\(editorRoundTrip) cleanup=\(store.notes.count == savedCount)")
            fflush(stdout)
            precondition(stacked && hidden && restored && unstacked && minimumLayout && resizeGesture && sharedPin && allRaised && tabsAccessible && keyboardCycle && cardFocused && focusedControls && staysAfterClosingUI && activeTabPreserved && quitWaitVisible && quitWaitCancelled && coalesced && failedPreviewCollapsed && dotSelects && swipeSwitches && flush && blankDiscarded && hiddenDeleted && dropStacked && blankPageDiscarded && sideNotes && snooze && editorRoundTrip && store.notes.count == savedCount, "Desktop note regression failed")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { NSApp.terminate(nil) }
            } } }
        }
        var loaded: [NSImage?] = []
        func thumbnailLoaded(_ image: NSImage?) {
            loaded.append(image)
            guard loaded.count == 2 else { return }
            let coalesced = loaded[0] != nil && loaded[0] === loaded[1]
            // A failed image must release its reserved preview space after the async callback.
            capture(stackWidget.surface, "attachments")
            store.update(first.id) { $0.attachments = [broken] }
            ThumbnailLoader.shared.load(store.attachmentURL(broken), pixels: 440) { invalid in
                DispatchQueue.main.async {
                    stackWidget.layoutNote()
                    let collapsed = invalid == nil && stackWidget.attachments.frame.height == 22
                    finish(coalesced: coalesced, failedPreviewCollapsed: collapsed)
                }
            }
        }
        ThumbnailLoader.shared.load(store.attachmentURL(picture), pixels: 440, completion: thumbnailLoaded)
        ThumbnailLoader.shared.load(store.attachmentURL(picture), pixels: 440, completion: thumbnailLoaded)

    }
}
