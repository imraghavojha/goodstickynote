import AppKit
import Carbon.HIToolbox
import ServiceManagement

final class HotKeyManager {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var localMonitor: Any?
    private var currentPreferences: Preferences?
    private var suspended = false
    private(set) var isRegistered = false
    init() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { AppDelegate.shared.createNote() }
            return noErr
        }, 1, &eventType, nil, &handler)
        // App-local events also cover nonactivating panels and direct accessibility input.
        // Carbon consumes matching physical global events before they reach this monitor.
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, !self.suspended, let preferences = self.currentPreferences,
                  UInt32(event.keyCode) == preferences.keyCode,
                  Self.carbonFlags(event.modifierFlags) == preferences.modifiers else { return event }
            if !event.isARepeat { DispatchQueue.main.async { AppDelegate.shared.createNote() } }
            return nil
        }
    }
    func suspend() {
        suspended = true
        if let hotKey { UnregisterEventHotKey(hotKey); self.hotKey = nil }
    }
    @discardableResult func register(_ preferences: Preferences) -> Bool {
        if let hotKey { UnregisterEventHotKey(hotKey); self.hotKey = nil }
        currentPreferences = preferences; suspended = false
        let id = EventHotKeyID(signature: OSType(0x4753544B), id: 1)
        isRegistered = RegisterEventHotKey(preferences.keyCode, preferences.modifiers, id, GetApplicationEventTarget(), 0, &hotKey) == noErr
        return isRegistered
    }
    static func carbonFlags(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.control) { result |= UInt32(controlKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        return result
    }
    static func display(_ preferences: Preferences) -> String {
        var prefix = ""
        if preferences.modifiers & UInt32(controlKey) != 0 { prefix += "⌃" }
        if preferences.modifiers & UInt32(optionKey) != 0 { prefix += "⌥" }
        if preferences.modifiers & UInt32(shiftKey) != 0 { prefix += "⇧" }
        if preferences.modifiers & UInt32(cmdKey) != 0 { prefix += "⌘" }
        let keys: [UInt32: String] = [0:"A",1:"S",2:"D",3:"F",4:"H",5:"G",6:"Z",7:"X",8:"C",9:"V",11:"B",12:"Q",13:"W",14:"E",15:"R",16:"Y",17:"T",18:"1",19:"2",20:"3",21:"4",22:"6",23:"5",24:"=",25:"9",26:"7",27:"−",28:"8",29:"0",30:"]",31:"O",32:"U",33:"[",34:"I",35:"P",36:"↩",37:"L",38:"J",39:"'",40:"K",41:";",42:"\\",43:",",44:"/",45:"N",46:"M",47:".",48:"⇥",49:"Space",50:"`",51:"⌫",123:"←",124:"→",125:"↓",126:"↑"]
        return prefix + (keys[preferences.keyCode] ?? "Key \(preferences.keyCode)")
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    static var shared: AppDelegate!
    let store = NoteStore.shared
    let hotKey = HotKeyManager()
    var statusItem: NSStatusItem!
    var library: LibraryController?
    var preferences: PreferencesController?
    var widgets: [String: WidgetController] = [:]
    private var refreshing = false
    private var waitingToQuit = false
    private var outsideClickMonitor: Any?
    private var quitProgress: ImportWaitController?
    private var replyToTermination: (Bool) -> Void = { NSApp.reply(toApplicationShouldTerminate: $0) }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        NSApp.setActivationPolicy(.accessory)
        buildMainMenu()
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(showNotesRequested), name: Notification.Name("app.goodsticky.showNotes"), object: store.directory.path)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "note.text", accessibilityDescription: "GoodSticky")
        statusItem.button?.toolTip = "GoodSticky — click for notes, right-click for more"
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusClicked(_:))
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        store.onImportsFinished = { [weak self] in
            guard let self, self.waitingToQuit else { return }
            self.waitingToQuit = false
            self.quitProgress?.close(); self.quitProgress = nil
            self.replyToTermination(self.saveBeforeQuit())
        }
        store.onError = { message in
            let alert = NSAlert(); alert.messageText = "Your notes need attention"; alert.informativeText = message; alert.runModal()
        }
        if CommandLine.arguments.contains("--enable-login") {
            do {
                if SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval { try SMAppService.mainApp.unregister() }
                try SMAppService.mainApp.register()
                if SMAppService.mainApp.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
            } catch { store.onError?("Couldn’t enable Open at login: \(error.localizedDescription)") }
        }
        if !hotKey.register(store.preferences) { NSLog("GoodSticky: global shortcut unavailable") }
        let firstLaunch = !FileManager.default.fileExists(atPath: store.directory.appendingPathComponent("notes.json").path) && !store.loadFailed
        if CommandLine.arguments.contains("--smoke-test") { seedWelcomeNotes() }
        else if firstLaunch { store.add() }
        if store.preferences.desktopLayoutVersion != 2 {
            for id in store.notes.filter({ $0.width == 310 && $0.height == 320 }).map(\.id) {
                store.update(id, notify: false) { $0.width = 220; $0.height = 180 }
            }
            store.preferences.desktopLayoutVersion = 2; store.save()
        }
        // Blank notes hidden by an earlier version are cleared before anything is shown.
        if store.discardBlankHidden() { store.save() }
        store.onChange = { [weak self] in self?.synchronize() }
        synchronize()
        if store.loadFailed || CommandLine.arguments.contains("--smoke-test") || CommandLine.arguments.contains("--show-library") { showLibrary() }
        if CommandLine.arguments.contains("--show-preferences") { showPreferences() }
        if store.loadFailed {
            let alert = NSAlert(); alert.messageText = "Your library couldn’t be opened"; alert.informativeText = "Your original notes have been left untouched at \(store.directory.path). Quit GoodSticky and restore notes.json from a backup before adding notes."; alert.runModal()
        }
        if CommandLine.arguments.contains("--smoke-test") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.runSmokeTest() }
        }
    }
    @objc func showNotesRequested() { showLibrary() }
    /// Built on demand so it always reflects the current shortcut and note counts.
    func makeStatusMenu() -> NSMenu {
        let menu = NSMenu()
        func add(_ title: String, _ symbolName: String, enabled: Bool = true, _ action: @escaping () -> Void) -> NSMenuItem {
            let item = ClosureMenuItem(title, action: action); item.image = symbol(symbolName, size: 13, weight: .regular)
            item.isEnabled = enabled; if !enabled { item.target = nil; item.action = nil }
            menu.addItem(item); return item
        }
        let new = add("New Note", "square.and.pencil") { [weak self] in self?.createNote() }
        let shortcut = HotKeyManager.display(store.preferences)
        let attributed = NSMutableAttributedString(string: "New Note")
        attributed.append(NSAttributedString(string: "   " + shortcut, attributes: [.foregroundColor: NSColor.tertiaryLabelColor, .font: NSFont.menuFont(ofSize: 0)]))
        new.attributedTitle = attributed
        _ = add("All Notes…", "list.bullet.rectangle") { [weak self] in self?.showLibrary() }
        menu.addItem(.separator())
        let visible = store.notes.filter { !$0.hidden }.count, hidden = store.notes.count - visible
        _ = add("Bring Notes Forward", "square.stack.3d.up", enabled: visible > 0) { [weak self] in self?.bringAllForward() }
        _ = add(hidden > 0 ? "Show All Notes (\(hidden) hidden)" : "Show All Notes", "eye", enabled: hidden > 0) { [weak self] in
            guard let self else { return }
            self.store.updateMany(self.store.notes.map(\.id)) { $0.hidden = false }
        }
        _ = add("Hide All Notes", "eye.slash", enabled: visible > 0) { [weak self] in
            guard let self else { return }
            self.store.updateMany(self.store.notes.map(\.id)) { $0.hidden = true }
        }
        menu.addItem(.separator())
        let settings = add("Settings…", "gearshape") { [weak self] in self?.showPreferences() }; settings.keyEquivalent = ","
        menu.addItem(.separator())
        let quit = add("Quit GoodSticky", "power") { NSApp.terminate(nil) }; quit.keyEquivalent = "q"
        return menu
    }
    @objc func statusClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp || NSApp.currentEvent?.modifierFlags.contains(.option) == true {
            makeStatusMenu().popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.minY - 4), in: sender)
        } else if library?.window?.isVisible == true { library?.close() }
        else { showLibrary() }
    }
    func buildMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem(); let appMenu = NSMenu()
        appMenu.addItem(ClosureMenuItem("About GoodSticky") {
            NSApp.orderFrontStandardAboutPanel(options: [.applicationName: "GoodSticky", .applicationVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.2.0"])
        })
        let settings = ClosureMenuItem("Settings…") { self.showPreferences() }; settings.keyEquivalent = ","; appMenu.addItem(settings)
        appMenu.addItem(.separator())
        let quit = ClosureMenuItem("Quit GoodSticky") { NSApp.terminate(nil) }; quit.keyEquivalent = "q"; appMenu.addItem(quit)
        appItem.submenu = appMenu; main.addItem(appItem)
        let fileItem = NSMenuItem(); let fileMenu = NSMenu(title: "File")
        let new = ClosureMenuItem("New note") { self.createNote() }; new.keyEquivalent = "n"; fileMenu.addItem(new)
        let close = ClosureMenuItem("Close") { self.closeFrontmost() }; close.keyEquivalent = "w"; fileMenu.addItem(close)
        fileItem.submenu = fileMenu; main.addItem(fileItem)
        let editItem = NSMenuItem(); let editMenu = NSMenu(title: "Edit")
        for (title, action, key) in [("Undo", Selector(("undo:")), "z"), ("Cut", #selector(NSText.cut(_:)), "x"), ("Copy", #selector(NSText.copy(_:)), "c"), ("Paste", #selector(NSText.paste(_:)), "v"), ("Select All", #selector(NSText.selectAll(_:)), "a")] {
            editMenu.addItem(NSMenuItem(title: title, action: action, keyEquivalent: key))
        }
        editItem.submenu = editMenu; main.addItem(editItem)
        NSApp.mainMenu = main
    }
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
    func synchronize() {
        guard !refreshing else { return }; refreshing = true
        defer { refreshing = false }
        let groups = Dictionary(grouping: store.notes.filter { !$0.hidden }) { $0.stackID?.uuidString ?? $0.id.uuidString }
        var available = widgets
        var next: [String: WidgetController] = [:]
        let activeOwners = Dictionary(widgets.map { ($0.value.activeID, $0.key) }, uniquingKeysWith: { first, _ in first })
        let activeIDs = Set(activeOwners.keys)
        let ordered = groups.sorted { lhs, rhs in
            let left = Set(lhs.value.map(\.id)), right = Set(rhs.value.map(\.id))
            let leftOwnsActive = !left.isDisjoint(with: activeIDs)
            let rightOwnsActive = !right.isDisjoint(with: activeIDs)
            return leftOwnsActive != rightOwnsActive ? leftOwnsActive : lhs.key < rhs.key
        }
        for (key, notes) in ordered {
            let ids = notes.map(\.id)
            let reusableKey = available[key] != nil ? key : ids.compactMap { activeOwners[$0] }.first(where: { available[$0] != nil })
            if let reusableKey, let existing = available.removeValue(forKey: reusableKey) {
                if existing.ids != ids { existing.updateMembers(ids) }
                existing.refresh(using: notes.first { $0.id == existing.activeID }); next[key] = existing
            } else {
                let widget = WidgetController(ids: ids); next[key] = widget; widget.show()
            }
        }
        widgets = next
        for obsolete in available.values { obsolete.close() }
        if library?.window?.isVisible == true { library?.refresh() }
    }
    func closeFrontmost() {
        if let widget = widgets.values.first(where: { $0.window === NSApp.keyWindow }) {
            store.update(widget.activeID) { $0.hidden = true }
        } else { NSApp.keyWindow?.performClose(nil) }
    }
    func createNote() {
        guard !store.loadFailed else { return }
        library?.close()
        let note = store.add()
        widgets[note.id.uuidString]?.show(focus: true)
    }
    func reveal(_ id: UUID) {
        guard let note = store.note(id) else { return }
        store.update(id) { $0.hidden = false }
        let key = note.stackID?.uuidString ?? id.uuidString
        if let widget = widgets[key] { widget.activeID = id; widget.refresh(); widget.show(focus: true) }
    }
    func bringAllForward() {
        if outsideClickMonitor == nil {
            outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in self?.returnNotesToDesktop() }
        }
        for widget in widgets.values { widget.bringForward() }
    }
    func returnNotesToDesktop() {
        if let monitor = outsideClickMonitor { NSEvent.removeMonitor(monitor); outsideClickMonitor = nil }
        for widget in widgets.values { widget.returnToDesktop() }
    }
    func showLibrary() { returnNotesToDesktop(); if library == nil { library = LibraryController() }; library?.present() }
    func showPreferences() {
        returnNotesToDesktop()
        if preferences == nil { preferences = PreferencesController() }
        preferences?.window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    func stack(_ id: UUID, with otherID: UUID) {
        guard let note = store.note(id), let other = store.note(otherID) else { return }
        let stackID = other.stackID ?? UUID()
        let ids = store.notes.filter { $0.id == id || $0.id == otherID || (note.stackID != nil && $0.stackID == note.stackID) || (other.stackID != nil && $0.stackID == other.stackID) }.map(\.id)
        store.updateMany(ids, notify: false) { $0.stackID = stackID; $0.x = other.x; $0.y = other.y; $0.width = other.width; $0.height = other.height; $0.pinned = other.pinned }
        synchronize()
        widgets[stackID.uuidString]?.activeID = id; widgets[stackID.uuidString]?.refresh()
        widgets[stackID.uuidString]?.show(focus: true)
    }
    func setPinned(_ id: UUID, pinned: Bool) {
        guard let note = store.note(id) else { return }
        let ids = store.notes.filter { $0.id == id || (note.stackID != nil && $0.stackID == note.stackID) }.map(\.id)
        store.updateMany(ids) { $0.pinned = pinned }
    }
    func unstack(_ id: UUID) {
        guard let note = store.note(id) else { return }
        store.update(id, notify: false) { $0.stackID = nil; $0.x += 24; $0.y -= 24 }
        if let stack = note.stackID {
            let remaining = store.notes.filter { $0.stackID == stack }
            if remaining.count == 1 { store.update(remaining[0].id, notify: false) { $0.stackID = nil } }
        }
        synchronize(); widgets[id.uuidString]?.show(focus: true)
    }
    /// Hidden and blank notes delete immediately; only a visible note with content asks first.
    func confirmDelete(_ id: UUID) {
        guard let note = store.note(id) else { return }
        if note.hidden || note.isBlank { store.delete(id); return }
        let alert = NSAlert(); alert.messageText = "Delete “\(String(note.title.prefix(45)))”?"
        alert.informativeText = "This permanently removes the note and its local attachments. You can hide a note to keep it for later."
        alert.addButton(withTitle: "Keep note"); alert.addButton(withTitle: "Delete")
        if alert.runModal() == .alertSecondButtonReturn { store.delete(id) }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showLibrary(); return true }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if store.pendingImports > 0 {
            waitingToQuit = true
            if quitProgress == nil { quitProgress = ImportWaitController { [weak self] in self?.cancelPendingQuit() } }
            quitProgress?.showWindow(nil); quitProgress?.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return .terminateLater
        }
        return saveBeforeQuit() ? .terminateNow : .terminateCancel
    }
    func cancelPendingQuit() {
        guard waitingToQuit else { return }
        waitingToQuit = false; quitProgress?.close(); quitProgress = nil
        replyToTermination(false)
    }
    func saveBeforeQuit() -> Bool {
        do { try store.flush(); return true }
        catch {
            let alert = NSAlert()
            alert.messageText = "Couldn’t save notes"
            alert.informativeText = "Your changes are still open. Check the disk space and permissions for \(store.directory.path), then try quitting again.\n\n\(error.localizedDescription)"
            alert.addButton(withTitle: "Keep open")
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
            return false
        }
    }
    func applicationDidResignActive(_ notification: Notification) { returnNotesToDesktop() }
    func applicationWillTerminate(_ notification: Notification) {
        if CommandLine.arguments.contains("--smoke-test") { try? FileManager.default.removeItem(at: store.directory) }
    }
    func runSmokeTest() {
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
        let minimumLayout = stackWidget.scroll.frame.height >= 28 && stackWidget.attachments.frame.height <= 60 && !stackWidget.dots.isHidden && stackWidget.dots.frame.height == 14 && stackWidget.dots.frame.maxX <= stackWidget.grip.frame.minX + 6
        stackWidget.window?.setContentSize(NSSize(width: 220, height: 280)); stackWidget.layoutNote()
        capture(stackWidget.surface, "attachments")
        let appearance = NoteAppearanceController(noteID: first.id)
        capture(appearance.view, "appearance")
        setPinned(first.id, pinned: true)
        let sharedPin = store.note(second.id)?.pinned == true
        stackWidget.activeID = second.id; stackWidget.refresh()
        stackWidget.textView.setSelectedRange(NSRange(location: 3, length: 2))
        store.update(first.id) { $0.hidden = true }
        let preservedOnHide = widgets[stackID.uuidString] === stackWidget && stackWidget.activeID == second.id && stackWidget.textView.selectedRange() == NSRange(location: 3, length: 2)
        store.update(first.id) { $0.hidden = false }
        let activeTabPreserved = preservedOnHide && widgets[stackID.uuidString] === stackWidget && stackWidget.activeID == second.id && stackWidget.textView.selectedRange() == NSRange(location: 3, length: 2)
        stackWidget.activeID = first.id; stackWidget.refresh()

        let dotsValue = stackWidget.dots.accessibilityValue() as? String ?? ""
        let tabsAccessible = stackWidget.dots.accessibilityRole() == .tabGroup && dotsValue.hasPrefix("Note 1 of 2") && stackWidget.dots.range == 0..<2
        // Clicking the second dot shows the second note; a swipe brings the first back.
        let secondDot = NSPoint(x: stackWidget.dots.bounds.midX + PageDots.pitch / 2, y: stackWidget.dots.bounds.midY)
        if let index = stackWidget.dots.index(at: secondDot) { stackWidget.dots.onSelect?(index) }
        let dotSelects = stackWidget.activeID == second.id && stackWidget.dots.current == 1
        stackWidget.scroll.onSwipe?(-1)
        let swipeSwitches = dotSelects && stackWidget.activeID == first.id && stackWidget.dots.current == 0
        let flush = widgets.values.allSatisfy { $0.window?.hasShadow == false && $0.surface.layer?.borderWidth == 0 }
        if let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .control, timestamp: 0, windowNumber: stackWidget.window!.windowNumber, context: nil, characters: "\t", charactersIgnoringModifiers: "\t", isARepeat: false, keyCode: 48) {
            stackWidget.textView.keyDown(with: event)
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
            // Dropping one note's drag handle onto another stacks them.
            let lower = store.add(text: "Drop target"), upper = store.add(text: "Dragged note")
            let target = widgets[lower.id.uuidString]!, dragged = widgets[upper.id.uuidString]!
            let screen = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
            target.window?.setFrame(NSRect(x: screen.minX + 80, y: screen.minY + 80, width: 220, height: 180), display: true)
            dragged.window?.setFrame(NSRect(x: screen.minX + 420, y: screen.minY + 80, width: 220, height: 180), display: true)
            // Float both so no other app's window covers the drop point, then move the dragged
            // note so its handle is under the cursor above the target, as in a real drag.
            target.window?.level = .floating; dragged.window?.level = .floating
            target.window?.orderFrontRegardless(); dragged.window?.orderFrontRegardless()
            let dropPoint = NSPoint(x: target.window!.frame.midX, y: target.window!.frame.midY)
            dragged.window?.setFrameOrigin(NSPoint(x: dropPoint.x - 40, y: dropPoint.y - 166))
            // Let WindowServer apply the new frames and ordering, as between real drag events.
            CATransaction.flush(); RunLoop.current.run(until: Date().addingTimeInterval(0.3))
            dragged.trackStackTarget(at: dropPoint)
            let highlighted = target.surface.stackTarget
            dragged.finishMove(at: dropPoint)
            let dropStacked = highlighted && !target.surface.stackTarget && store.note(lower.id)?.stackID != nil && store.note(lower.id)?.stackID == store.note(upper.id)?.stackID
            store.delete(lower.id); store.delete(upper.id)
            do { try store.flush() } catch { preconditionFailure("Smoke save failed: \(error)") }
            print("SMOKE TEST: stacked=\(stacked) hidden=\(hidden) restored=\(restored) unstacked=\(unstacked) minimumLayout=\(minimumLayout) resizeGesture=\(resizeGesture) sharedPin=\(sharedPin) allRaised=\(allRaised) tabsAccessible=\(tabsAccessible) keyboardCycle=\(keyboardCycle) focusedControls=\(cardFocused && focusedControls) staysAfterClosingUI=\(staysAfterClosingUI) activeTabPreserved=\(activeTabPreserved) quitWaitVisible=\(quitWaitVisible) quitWaitCancelled=\(quitWaitCancelled) thumbnailCoalesced=\(coalesced) failedPreviewCollapsed=\(failedPreviewCollapsed) dotSelects=\(dotSelects) swipeSwitches=\(swipeSwitches) flush=\(flush) blankDiscarded=\(blankDiscarded) hiddenDeleted=\(hiddenDeleted) dropStacked=\(dropStacked) cleanup=\(store.notes.count == savedCount)")
            fflush(stdout)
            precondition(stacked && hidden && restored && unstacked && minimumLayout && resizeGesture && sharedPin && allRaised && tabsAccessible && keyboardCycle && cardFocused && focusedControls && staysAfterClosingUI && activeTabPreserved && quitWaitVisible && quitWaitCancelled && coalesced && failedPreviewCollapsed && dotSelects && swipeSwitches && flush && blankDiscarded && hiddenDeleted && dropStacked && store.notes.count == savedCount, "Desktop note regression failed")
            NSApp.terminate(nil)
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
