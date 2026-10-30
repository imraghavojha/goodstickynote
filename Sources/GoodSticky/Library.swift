import AppKit
import Carbon.HIToolbox
import ServiceManagement

final class LibraryController: NSWindowController, NSSearchFieldDelegate, NSWindowDelegate {
    let root = SurfaceView(fill: canvas, radius: 0)
    let grid = FlippedView()
    let scroll = NSScrollView()
    let search = NSSearchField()
    let count = label("", size: 11, color: secondaryInk)
    let filter = NSSegmentedControl(labels: ["Desktop", "Hidden", "All"], trackingMode: .selectOne, target: nil, action: nil)
    private var cards: [NoteCard] = []
    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 430), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        super.init(window: window)
        window.title = "Notes"; window.backgroundColor = canvas; window.appearance = NSAppearance(named: .aqua)
        window.isReleasedWhenClosed = false; window.minSize = NSSize(width: 310, height: 240); window.delegate = self
        window.contentView = root; window.center()
        search.placeholderString = "Search notes"; search.delegate = self; search.sendsSearchStringImmediately = true
        filter.selectedSegment = 0; filter.target = self; filter.action = #selector(filterChanged)
        let new = ActionButton("New note", symbol: "plus") { AppDelegate.shared.createNote() }
        let settings = ActionButton("Preferences", symbol: "slider.horizontal.3") { AppDelegate.shared.showPreferences() }
        scroll.drawsBackground = false; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true; scroll.documentView = grid
        for view in [search, filter, new, settings, scroll, count] { view.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(view) }
        NSLayoutConstraint.activate([
            search.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14), search.topAnchor.constraint(equalTo: root.topAnchor, constant: 14), search.heightAnchor.constraint(equalToConstant: 28),
            new.leadingAnchor.constraint(equalTo: search.trailingAnchor, constant: 8), new.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12), new.centerYAnchor.constraint(equalTo: search.centerYAnchor), new.widthAnchor.constraint(equalToConstant: 28), new.heightAnchor.constraint(equalToConstant: 28),
            filter.leadingAnchor.constraint(equalTo: search.leadingAnchor), filter.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -14), filter.topAnchor.constraint(equalTo: search.bottomAnchor, constant: 12),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 6), scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -6), scroll.topAnchor.constraint(equalTo: filter.bottomAnchor, constant: 12), scroll.bottomAnchor.constraint(equalTo: count.topAnchor, constant: -10),
            count.leadingAnchor.constraint(equalTo: search.leadingAnchor), count.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -15),
            settings.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -14), settings.centerYAnchor.constraint(equalTo: count.centerYAnchor), settings.widthAnchor.constraint(equalToConstant: 24), settings.heightAnchor.constraint(equalToConstant: 24)
        ])
        root.layoutSubtreeIfNeeded(); refresh()
        NotificationCenter.default.addObserver(self, selector: #selector(layoutRows), name: NSWindow.didResizeNotification, object: window)
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc func filterChanged() { refresh() }
    func refresh() {
        let existing = Dictionary(uniqueKeysWithValues: cards.compactMap { card in card.note.map { ($0.id, card) } })
        let query = search.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let notes = NoteStore.shared.notes.filter {
            (filter.selectedSegment == 2 || (filter.selectedSegment == 1 ? $0.hidden : !$0.hidden)) &&
            (query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.text.localizedCaseInsensitiveContains(query) || $0.attachments.contains { $0.name.localizedCaseInsensitiveContains(query) })
        }.sorted { $0.created < $1.created }
        let previous = cards
        cards = notes.map { note in existing[note.id].flatMap { $0.note == note ? $0 : nil } ?? NoteCard(note: note) }
        let retained = Set(cards.map(ObjectIdentifier.init))
        previous.filter { !retained.contains(ObjectIdentifier($0)) }.forEach { $0.removeFromSuperview() }
        for card in cards where card.superview == nil { grid.addSubview(card) }
        count.stringValue = "\(notes.count) \(notes.count == 1 ? "note" : "notes")"
        layoutRows()
    }
    @objc func layoutRows() {
        let width = max(280, scroll.contentSize.width)
        for (index, card) in cards.enumerated() { card.frame = NSRect(x: 6, y: CGFloat(index) * 72, width: width - 12, height: 66) }
        grid.frame = NSRect(x: 0, y: 0, width: width, height: max(scroll.contentSize.height, CGFloat(cards.count) * 72))
    }
    func controlTextDidChange(_ obj: Notification) { refresh() }
    func present() {
        refresh(); window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    func windowWillClose(_ notification: Notification) {
        if AppDelegate.shared.library === self { AppDelegate.shared.library = nil }
    }
    deinit { NotificationCenter.default.removeObserver(self) }
}

final class NoteCard: NSView {
    let note: StickyNote?
    private var tracking: NSTrackingArea?
    private var hovering = false
    private var buttons: [ActionButton] = []
    init(note: StickyNote?) {
        self.note = note; super.init(frame: .zero)
        setAccessibilityElement(true); setAccessibilityRole(.button); setAccessibilityLabel(note?.title ?? "New note")
        guard let note else { return }
        let copy = ActionButton("Copy note", symbol: "doc.on.doc") {
            NSPasteboard.general.clearContents(); NSPasteboard.general.setString(note.text, forType: .string)
        }
        let hide = ActionButton(note.hidden ? "Show note" : "Hide note", symbol: note.hidden ? "arrow.uturn.backward" : "minus") {
            NoteStore.shared.update(note.id) { $0.hidden.toggle() }
        }
        setAccessibilityCustomActions([
            NSAccessibilityCustomAction(name: "Copy") { copy.actionHandler?(); return true },
            NSAccessibilityCustomAction(name: note.hidden ? "Show" : "Hide") { hide.actionHandler?(); return true }
        ])
        for button in [copy, hide] {
            button.isHidden = true; button.contentTintColor = primaryInk; addSubview(button); buttons.append(button)
            button.focusChanged = { [weak self] focused in
                if focused { self?.showControls(true) }
                else { DispatchQueue.main.async { [weak self] in self?.updateControls() } }
            }
        }
    }
    required init?(coder: NSCoder) { fatalError() }
    override var acceptsFirstResponder: Bool { true }
    override func becomeFirstResponder() -> Bool { showControls(true); return true }
    override func resignFirstResponder() -> Bool { DispatchQueue.main.async { [weak self] in self?.updateControls() }; return true }
    func showControls(_ show: Bool) { buttons.forEach { $0.isHidden = !show }; needsDisplay = true }
    func updateControls() {
        let focus = window?.firstResponder as? NSView
        showControls(hovering || focus === self || focus?.isDescendant(of: self) == true)
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas(); if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(rect: bounds, options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect], owner: self); addTrackingArea(tracking!)
    }
    override func mouseEntered(with event: NSEvent) { hovering = true; updateControls() }
    override func mouseExited(with event: NSEvent) { hovering = false; updateControls() }
    override func layout() {
        super.layout()
        for (index, button) in buttons.enumerated() { button.frame = NSRect(x: bounds.width - 31 - CGFloat(index) * 26, y: 23, width: 24, height: 24) }
    }
    override func accessibilityPerformPress() -> Bool {
        if let note { AppDelegate.shared.library?.close(); AppDelegate.shared.reveal(note.id) }; return true
    }
    override func mouseDown(with event: NSEvent) { _ = accessibilityPerformPress() }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 49 { _ = accessibilityPerformPress() } else { super.keyDown(with: event) }
    }
    override func menu(for event: NSEvent) -> NSMenu? {
        guard let note else { return nil }
        let menu = NSMenu()
        menu.addItem(ClosureMenuItem("Open") { AppDelegate.shared.reveal(note.id) })
        menu.addItem(ClosureMenuItem("Delete…") { AppDelegate.shared.confirmDelete(note.id) })
        return menu
    }
    override func draw(_ dirtyRect: NSRect) {
        guard let note else { return }
        let focused = window?.firstResponder === self
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 7, yRadius: 7)
        (hovering || focused ? NSColor.white : NSColor.white.withAlphaComponent(0.55)).setFill(); path.fill()
        (focused ? accent : NSColor.hex(0xE5E7E0)).setStroke(); path.lineWidth = 1; path.stroke()
        note.theme.paper.setFill(); NSBezierPath(roundedRect: NSRect(x: 12, y: 17, width: 4, height: 32), xRadius: 2, yRadius: 2).fill()
        let available = bounds.width - (buttons.first?.isHidden == false ? 85 : 38)
        let style = NSMutableParagraphStyle(); style.lineBreakMode = .byTruncatingTail
        (note.title as NSString).draw(in: NSRect(x: 25, y: 35, width: available, height: 18), withAttributes: [.font: NSFont.systemFont(ofSize: 13, weight: .medium), .foregroundColor: primaryInk, .paragraphStyle: style])
        let preview = note.text.split(whereSeparator: \.isNewline).dropFirst().first.map(String.init) ?? (note.attachments.isEmpty ? "" : "\(note.attachments.count) attachments")
        (preview as NSString).draw(in: NSRect(x: 25, y: 14, width: available, height: 17), withAttributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: secondaryInk, .paragraphStyle: style])
    }
}

final class NoteAppearanceController: NSViewController {
    let noteID: UUID
    var swatches: [SwatchButton] = []
    let percentage = label("", size: 11)
    init(noteID: UUID) { self.noteID = noteID; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError() }
    override func loadView() {
        view = SurfaceView(fill: canvas, radius: 7)
        view.frame = NSRect(x: 0, y: 0, width: 238, height: 112)
        view.appearance = NSAppearance(named: .aqua)
        guard let note = NoteStore.shared.note(noteID) else { return }
        for (index, theme) in NoteTheme.all.enumerated() {
            let swatch = SwatchButton(theme: theme, size: 24)
            swatch.translatesAutoresizingMaskIntoConstraints = true
            swatch.frame = NSRect(x: CGFloat(15 + index * 29), y: 72, width: 24, height: 24)
            swatch.selected = note.themeID == theme.id
            swatch.handler = { [weak self] in
                guard let self else { return }
                NoteStore.shared.update(self.noteID) { $0.themeID = theme.id }
                self.swatches.forEach { $0.selected = $0.theme.id == theme.id }
            }
            view.addSubview(swatch); swatches.append(swatch)
        }
        let title = label("Opacity", size: 11); title.frame = NSRect(x: 16, y: 45, width: 100, height: 16); view.addSubview(title)
        percentage.stringValue = "\(Int(note.opacity * 100))%"; percentage.frame = NSRect(x: 175, y: 45, width: 48, height: 16); percentage.alignment = .right; view.addSubview(percentage)
        let slider = NSSlider(value: note.opacity, minValue: 0.35, maxValue: 1, target: self, action: #selector(changeOpacity(_:)))
        slider.frame = NSRect(x: 13, y: 14, width: 212, height: 24); slider.isContinuous = true; view.addSubview(slider)
    }
    @objc func changeOpacity(_ slider: NSSlider) {
        NoteStore.shared.update(noteID) { $0.opacity = slider.doubleValue }
        percentage.stringValue = "\(Int(slider.doubleValue * 100))%"
    }
}
final class PreferencesController: NSWindowController, NSWindowDelegate {
    let shortcutButton = ActionButton("", action: {})
    let status = label("", size: 11, color: secondaryInk)
    let percentage = label("100%", size: 12, weight: .medium)
    var monitor: Any?
    var swatches: [SwatchButton] = []
    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 390, height: 305), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        super.init(window: window)
        window.delegate = self; window.isReleasedWhenClosed = false
        window.title = "Preferences"; window.backgroundColor = canvas; window.appearance = NSAppearance(named: .aqua); window.center()
        let root = SurfaceView(fill: canvas, radius: 0); window.contentView = root
        let keyTitle = label("New note shortcut", size: 12, weight: .semibold)
        let colorTitle = label("Color", size: 12, weight: .semibold)
        let opacityTitle = label("Opacity", size: 12, weight: .semibold)
        shortcutButton.title = HotKeyManager.display(NoteStore.shared.preferences)
        if !AppDelegate.shared.hotKey.isRegistered { status.stringValue = "Shortcut unavailable system-wide. Choose another combination." }
        shortcutButton.isBordered = true; shortcutButton.bezelStyle = .rounded
        shortcutButton.actionHandler = { [weak self] in self?.record() }
        let colors = NSStackView(); colors.spacing = 12
        for theme in NoteTheme.all {
            let swatch = SwatchButton(theme: theme, size: 29)
            swatch.selected = NoteStore.shared.preferences.defaultTheme == theme.id
            swatch.handler = { [weak self] in
                NoteStore.shared.preferences.defaultTheme = theme.id; NoteStore.shared.save()
                self?.swatches.forEach { $0.selected = $0.theme.id == theme.id }
            }
            colors.addArrangedSubview(swatch); swatches.append(swatch)
        }
        let slider = NSSlider(value: NoteStore.shared.preferences.defaultOpacity, minValue: 0.35, maxValue: 1, target: self, action: #selector(opacityChanged(_:)))
        slider.isContinuous = true
        percentage.stringValue = "\(Int(slider.doubleValue * 100))%"
        let login = NSButton(checkboxWithTitle: "Open at login", target: self, action: #selector(toggleLogin(_:)))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        for view in [login, keyTitle, shortcutButton, status, colorTitle, colors, opacityTitle, slider, percentage] { view.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(view) }
        NSLayoutConstraint.activate([
            keyTitle.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 30), keyTitle.topAnchor.constraint(equalTo: root.topAnchor, constant: 32),
            shortcutButton.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -30), shortcutButton.centerYAnchor.constraint(equalTo: keyTitle.centerYAnchor), shortcutButton.widthAnchor.constraint(equalToConstant: 142),
            status.leadingAnchor.constraint(equalTo: keyTitle.leadingAnchor), status.topAnchor.constraint(equalTo: keyTitle.bottomAnchor, constant: 11), status.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -25),
            colorTitle.leadingAnchor.constraint(equalTo: keyTitle.leadingAnchor), colorTitle.topAnchor.constraint(equalTo: status.bottomAnchor, constant: 27),
            colors.leadingAnchor.constraint(equalTo: keyTitle.leadingAnchor), colors.topAnchor.constraint(equalTo: colorTitle.bottomAnchor, constant: 12),
            opacityTitle.leadingAnchor.constraint(equalTo: keyTitle.leadingAnchor), opacityTitle.topAnchor.constraint(equalTo: colors.bottomAnchor, constant: 27),
            percentage.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -30), percentage.centerYAnchor.constraint(equalTo: opacityTitle.centerYAnchor),
            login.leadingAnchor.constraint(equalTo: keyTitle.leadingAnchor), login.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -20),
            slider.leadingAnchor.constraint(equalTo: keyTitle.leadingAnchor), slider.trailingAnchor.constraint(equalTo: percentage.trailingAnchor), slider.topAnchor.constraint(equalTo: opacityTitle.bottomAnchor, constant: 10)
        ])
        NotificationCenter.default.addObserver(self, selector: #selector(stopRecording), name: NSWindow.willCloseNotification, object: window)
        NotificationCenter.default.addObserver(self, selector: #selector(stopRecording), name: NSWindow.didResignKeyNotification, object: window)
    }
    required init?(coder: NSCoder) { fatalError() }
    func windowWillClose(_ notification: Notification) {
        stopRecording()
        if AppDelegate.shared.preferences === self { AppDelegate.shared.preferences = nil }
    }
    @objc func toggleLogin(_ sender: NSButton) {
        do {
            if sender.state == .on { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            if SMAppService.mainApp.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        } catch {
            sender.state = SMAppService.mainApp.status == .enabled ? .on : .off
            status.stringValue = "Login setting failed: \(error.localizedDescription)"
        }
    }
    @objc func opacityChanged(_ sender: NSSlider) {
        NoteStore.shared.preferences.defaultOpacity = sender.doubleValue
        percentage.stringValue = "\(Int(sender.doubleValue * 100))%"; NoteStore.shared.save()
    }
    @objc func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor); _ = AppDelegate.shared.hotKey.register(NoteStore.shared.preferences) }
        monitor = nil; shortcutButton.title = HotKeyManager.display(NoteStore.shared.preferences)
    }
    func record() {
        stopRecording(); AppDelegate.shared.hotKey.suspend(); shortcutButton.title = "Press shortcut…"; status.stringValue = "Use ⌃, ⌥ or ⌘ with a key. Esc cancels."
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53 { self.stopRecording(); self.status.stringValue = ""; return nil }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard !flags.intersection([.control, .option, .command]).isEmpty else { return nil }
            var prefs = NoteStore.shared.preferences
            prefs.keyCode = UInt32(event.keyCode); prefs.modifiers = HotKeyManager.carbonFlags(flags)
            if AppDelegate.shared.hotKey.register(prefs) {
                NoteStore.shared.preferences = prefs; NoteStore.shared.save()
                self.status.stringValue = ""
                AppDelegate.shared.library?.refresh()
            } else {
                _ = AppDelegate.shared.hotKey.register(NoteStore.shared.preferences)
                self.status.stringValue = "That shortcut is unavailable. Try another combination."
            }
            self.stopRecording(); return nil
        }
    }
}
