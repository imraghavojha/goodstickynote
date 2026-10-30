import AppKit
import Carbon.HIToolbox

final class LibraryController: NSWindowController, NSSearchFieldDelegate {
    let root = SurfaceView(fill: canvas, radius: 0)
    let sidebar = SurfaceView(fill: .hex(0xEEEFE8), radius: 0)
    let content = NSView()
    let grid = FlippedView()
    let scroll = NSScrollView()
    let search = NSSearchField()
    let heading = label("Notes", size: 28, weight: .semibold)
    let count = label("", size: 10, weight: .semibold, color: secondaryInk)
    var filter = "desktop"
    private var navButtons: [String: ActionButton] = [:]
    private var cards: [NoteCard] = []

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1080, height: 720), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        super.init(window: window)
        window.title = "GoodSticky"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = canvas
        window.appearance = NSAppearance(named: .aqua)
        window.minSize = NSSize(width: 850, height: 580)
        window.center()
        window.contentView = root
        setup()
        root.layoutSubtreeIfNeeded()
        refresh()
        NotificationCenter.default.addObserver(self, selector: #selector(resize), name: NSWindow.didResizeNotification, object: window)
    }
    required init?(coder: NSCoder) { fatalError() }
    func setup() {
        sidebar.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(sidebar)
        content.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(content)
        NSLayoutConstraint.activate([
            sidebar.leadingAnchor.constraint(equalTo: root.leadingAnchor), sidebar.topAnchor.constraint(equalTo: root.topAnchor), sidebar.bottomAnchor.constraint(equalTo: root.bottomAnchor), sidebar.widthAnchor.constraint(equalToConstant: 212),
            content.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor), content.topAnchor.constraint(equalTo: root.topAnchor), content.bottomAnchor.constraint(equalTo: root.bottomAnchor), content.trailingAnchor.constraint(equalTo: root.trailingAnchor)
        ])
        let brand = label("goodsticky", size: 18, weight: .semibold)
        let mark = StickyMark(frame: .zero)
        mark.translatesAutoresizingMaskIntoConstraints = false; sidebar.addSubview(mark)
        brand.translatesAutoresizingMaskIntoConstraints = false; sidebar.addSubview(brand)
        var previous: NSView = brand
        for (id, title, symbol) in [("desktop", "Desktop", "square.grid.2x2"), ("hidden", "Hidden", "tray"), ("all", "All notes", "square.stack")] {
            let button = ActionButton("  " + title, symbol: symbol) { [weak self] in self?.filter = id; self?.refresh() }
            button.imagePosition = .imageLeading; button.alignment = .left
            button.font = .systemFont(ofSize: 12, weight: .medium)
            button.wantsLayer = true; button.layer?.cornerRadius = 8
            button.translatesAutoresizingMaskIntoConstraints = false; sidebar.addSubview(button)
            NSLayoutConstraint.activate([
                button.topAnchor.constraint(equalTo: previous.bottomAnchor, constant: previous === brand ? 36 : 5),
                button.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 16), button.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -16), button.heightAnchor.constraint(equalToConstant: 38)
            ])
            previous = button; navButtons[id] = button
        }
        let settings = ActionButton("  Preferences", symbol: "slider.horizontal.3") { AppDelegate.shared.showPreferences() }
        settings.imagePosition = .imageLeading; settings.alignment = .left
        settings.translatesAutoresizingMaskIntoConstraints = false; sidebar.addSubview(settings)
        NSLayoutConstraint.activate([
            mark.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 23), mark.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: 68), mark.widthAnchor.constraint(equalToConstant: 28), mark.heightAnchor.constraint(equalToConstant: 28),
            brand.leadingAnchor.constraint(equalTo: mark.trailingAnchor, constant: 10), brand.centerYAnchor.constraint(equalTo: mark.centerYAnchor),
            settings.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 23), settings.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor, constant: -24), settings.heightAnchor.constraint(equalToConstant: 28)
        ])
        for view in [heading, count, search] { view.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(view) }
        search.placeholderString = "Search notes"; search.delegate = self
        search.bezelStyle = .roundedBezel
        search.sendsSearchStringImmediately = true
        let new = ActionButton("  New note", symbol: "plus") { AppDelegate.shared.createNote() }
        new.imagePosition = .imageLeading; new.wantsLayer = true; new.layer?.backgroundColor = accent.cgColor; new.layer?.cornerRadius = 9
        new.contentTintColor = .white; new.font = .systemFont(ofSize: 12, weight: .semibold)
        new.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(new)
        let separator = SurfaceView(fill: .hex(0xE3E5DC), radius: 0)
        separator.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(separator)
        scroll.drawsBackground = false; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true; scroll.documentView = grid
        scroll.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(scroll)
        NSLayoutConstraint.activate([
            heading.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 36), heading.topAnchor.constraint(equalTo: content.topAnchor, constant: 70),
            new.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -36), new.centerYAnchor.constraint(equalTo: heading.centerYAnchor, constant: 4), new.widthAnchor.constraint(equalToConstant: 112), new.heightAnchor.constraint(equalToConstant: 38),
            search.leadingAnchor.constraint(equalTo: heading.leadingAnchor), search.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 25), search.widthAnchor.constraint(equalToConstant: 250), search.heightAnchor.constraint(equalToConstant: 30),
            count.trailingAnchor.constraint(equalTo: new.trailingAnchor), count.centerYAnchor.constraint(equalTo: search.centerYAnchor),
            separator.topAnchor.constraint(equalTo: search.bottomAnchor, constant: 22), separator.leadingAnchor.constraint(equalTo: heading.leadingAnchor), separator.trailingAnchor.constraint(equalTo: new.trailingAnchor), separator.heightAnchor.constraint(equalToConstant: 1),
            scroll.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 24), scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 29), scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -25), scroll.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20)
        ])
    }
    func refresh() {
        guard isWindowLoaded else { return }
        heading.stringValue = filter == "hidden" ? "Hidden" : filter == "all" ? "All notes" : "Desktop"
        for (id, button) in navButtons {
            button.layer?.backgroundColor = id == filter ? NSColor.hex(0xDCE3D7).cgColor : NSColor.clear.cgColor
            button.contentTintColor = id == filter ? accent : secondaryInk
        }
        let previous = cards
        let existing = Dictionary(uniqueKeysWithValues: previous.compactMap { card in card.note.map { ($0.id, card) } })
        cards = []
        let query = search.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let notes = NoteStore.shared.notes.filter {
            (filter == "all" || (filter == "hidden" ? $0.hidden : !$0.hidden)) && (query.isEmpty || $0.text.localizedCaseInsensitiveContains(query) || $0.attachments.contains { $0.name.localizedCaseInsensitiveContains(query) })
        }.sorted { $0.created < $1.created }
        count.stringValue = "\(notes.count) \(notes.count == 1 ? "note" : "notes")"
        for note in notes {
            let card = existing[note.id].flatMap { $0.note == note ? $0 : nil } ?? NoteCard(note: note)
            if card.superview == nil { grid.addSubview(card) }
            cards.append(card)
        }
        let add = previous.first { $0.note == nil } ?? NoteCard(note: nil)
        if add.superview == nil { grid.addSubview(add) }
        cards.append(add)
        let retained = Set(cards.map(ObjectIdentifier.init))
        previous.filter { !retained.contains(ObjectIdentifier($0)) }.forEach { $0.removeFromSuperview() }
        layoutCards()
    }
    @objc func resize() { layoutCards() }
    func layoutCards() {
        let available = max(scroll.contentSize.width - 14, 500)
        let columns = available >= 730 ? 3 : 2
        let gap: CGFloat = 18
        let width = (available - CGFloat(columns - 1) * gap) / CGFloat(columns)
        let height: CGFloat = 222
        for (index, card) in cards.enumerated() {
            card.frame = NSRect(x: 7 + CGFloat(index % columns) * (width + gap), y: 4 + CGFloat(index / columns) * (height + gap), width: width, height: height)
        }
        grid.frame = NSRect(x: 0, y: 0, width: scroll.contentSize.width, height: max(scroll.contentSize.height, CGFloat((cards.count + columns - 1) / columns) * (height + gap) + 10))
    }
    func controlTextDidChange(_ obj: Notification) { refresh() }
    func present() { refresh(); window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
}

final class StickyMark: NSView {
    override func draw(_ dirtyRect: NSRect) {
        accent.setFill(); NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 7, yRadius: 7).fill()
        let paper = NSBezierPath(roundedRect: bounds.insetBy(dx: 7, dy: 6), xRadius: 2, yRadius: 2)
        NSColor.hex(0xF5E5A3).setFill(); paper.fill()
        accent.withAlphaComponent(0.35).setStroke()
        for y in [13.0, 17.0] { let line = NSBezierPath(); line.move(to: NSPoint(x: 11, y: y)); line.line(to: NSPoint(x: 20, y: y)); line.lineWidth = 1.5; line.stroke() }
    }
}

final class NoteCard: NSView {
    let note: StickyNote?
    private var tracking: NSTrackingArea?
    private var hovering = false
    private var hoverButtons: [NSButton] = []
    init(note: StickyNote?) {
        self.note = note
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityLabel(note?.title ?? "New note")
        setAccessibilityRole(.button)
        if let note {
            setAccessibilityCustomActions([
                NSAccessibilityCustomAction(name: "Copy") {
                    NSPasteboard.general.clearContents(); NSPasteboard.general.setString(note.text, forType: .string); return true
                },
                NSAccessibilityCustomAction(name: note.hidden ? "Restore" : "Hide") {
                    NoteStore.shared.update(note.id) { $0.hidden.toggle() }; return true
                }
            ])
            let open = ActionButton(note.hidden ? "Restore" : "Open", symbol: note.hidden ? "arrow.uturn.backward" : "arrow.up.right") { AppDelegate.shared.reveal(note.id) }
            let copy = ActionButton("Copy note", symbol: "doc.on.doc") {
                NSPasteboard.general.clearContents(); NSPasteboard.general.setString(note.text, forType: .string)
            }
            let hide = ActionButton(note.hidden ? "Restore note" : "Hide note", symbol: note.hidden ? "arrow.uturn.backward" : "minus") {
                NoteStore.shared.update(note.id) { $0.hidden.toggle() }
            }
            for button in [copy, hide, open] {
                button.focusChanged = { [weak self] focused in
                    if focused { self?.updateControlVisibility(focused: true) }
                    else { DispatchQueue.main.async { [weak self] in self?.updateControlVisibility() } }
                }
            }
            for button in [copy, hide] {
                button.contentTintColor = note.theme.ink; button.isHidden = true; addSubview(button); hoverButtons.append(button)
            }
            open.contentTintColor = note.theme.ink.withAlphaComponent(0.9)
            open.imagePosition = .imageTrailing; open.font = .systemFont(ofSize: 10, weight: .medium)
            addSubview(open)
            open.frame = NSRect(x: 17, y: 14, width: 120, height: 22)
        }
    }
    required init?(coder: NSCoder) { fatalError() }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(rect: bounds, options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect], owner: self)
        addTrackingArea(tracking!)
    }
    override var acceptsFirstResponder: Bool { true }
    override func becomeFirstResponder() -> Bool { updateControlVisibility(focused: true); return true }
    override func resignFirstResponder() -> Bool {
        DispatchQueue.main.async { [weak self] in self?.updateControlVisibility() }
        return true
    }
    private func updateControlVisibility(focused: Bool? = nil) {
        let responder = window?.firstResponder as? NSView
        let containsFocus = responder === self || responder?.isDescendant(of: self) == true
        let visible = hovering || (focused ?? containsFocus)
        hoverButtons.forEach { $0.isHidden = !visible }; needsDisplay = true
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 49 { _ = accessibilityPerformPress(); return }
        super.keyDown(with: event)
    }
    override func mouseEntered(with event: NSEvent) { hovering = true; updateControlVisibility() }
    override func mouseExited(with event: NSEvent) { hovering = false; updateControlVisibility() }
    override func layout() {
        super.layout()
        for (index, button) in hoverButtons.enumerated() { button.frame = NSRect(x: bounds.width - 39 - CGFloat(index) * 29, y: bounds.height - 39, width: 25, height: 25) }
    }
    override func mouseDown(with event: NSEvent) {
        if let note { AppDelegate.shared.reveal(note.id) } else { AppDelegate.shared.createNote() }
    }
    override func accessibilityPerformPress() -> Bool { if let note { AppDelegate.shared.reveal(note.id) } else { AppDelegate.shared.createNote() }; return true }
    override func menu(for event: NSEvent) -> NSMenu? {
        guard let note else { return nil }
        let menu = NSMenu()
        menu.addItem(ClosureMenuItem("Open note") { AppDelegate.shared.reveal(note.id) })
        menu.addItem(ClosureMenuItem(note.hidden ? "Restore" : "Hide") { NoteStore.shared.update(note.id) { $0.hidden.toggle() } })
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem("Delete…") { AppDelegate.shared.confirmDelete(note.id) })
        return menu
    }
    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(roundedRect: rect, xRadius: 13, yRadius: 13)
        guard let note else {
            NSColor.hex(0xD8DFD2).setStroke(); path.setLineDash([5, 4], count: 2, phase: 0); path.lineWidth = 1; path.stroke()
            let plus = "+" as NSString
            plus.draw(at: NSPoint(x: bounds.midX - 10, y: bounds.midY + 12), withAttributes: [.font: NSFont.systemFont(ofSize: 31, weight: .ultraLight), .foregroundColor: accent])
            drawText("New note", in: NSRect(x: 20, y: bounds.midY - 23, width: bounds.width - 40, height: 20), font: .systemFont(ofSize: 12, weight: .medium), color: accent, center: true)
            return
        }
        note.theme.paper.setFill(); path.fill()
        if window?.firstResponder === self {
            accent.setStroke()
            let ring = NSBezierPath(roundedRect: bounds.insetBy(dx: 3, dy: 3), xRadius: 12, yRadius: 12)
            ring.lineWidth = 2; ring.stroke()
        }
        note.theme.ink.withAlphaComponent(hovering ? 0.25 : 0.08).setStroke(); path.lineWidth = 1; path.stroke()
        let title = note.text.isEmpty ? "Untitled note" : note.title
        drawText(title, in: NSRect(x: 18, y: bounds.height - 59, width: bounds.width - 92, height: 29), font: .systemFont(ofSize: 17, weight: .medium), color: note.theme.ink)
        let body = note.text.split(separator: "\n", omittingEmptySubsequences: false).dropFirst().joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        drawText(body, in: NSRect(x: 18, y: 53, width: bounds.width - 36, height: bounds.height - 113), font: .systemFont(ofSize: 12), color: note.theme.ink.withAlphaComponent(0.9), lines: true)
        if !note.attachments.isEmpty {
            drawText("⌁ \(note.attachments.count)", in: NSRect(x: bounds.width - 48, y: 18, width: 35, height: 16), font: .systemFont(ofSize: 11), color: note.theme.ink.withAlphaComponent(0.6))
        }
    }
    func drawText(_ text: String, in rect: NSRect, font: NSFont, color: NSColor, center: Bool = false, lines: Bool = false) {
        let style = NSMutableParagraphStyle(); style.lineBreakMode = lines ? .byWordWrapping : .byTruncatingTail; style.lineSpacing = 5; style.alignment = center ? .center : .left
        (text as NSString).draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: [.font: font, .foregroundColor: color, .paragraphStyle: style])
    }
}

final class PreferencesController: NSWindowController {
    let shortcutButton = ActionButton("", action: {})
    let status = label("", size: 11, color: secondaryInk)
    let percentage = label("100%", size: 12, weight: .medium)
    var monitor: Any?
    var swatches: [SwatchButton] = []
    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 470, height: 285), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        super.init(window: window)
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
        for view in [keyTitle, shortcutButton, status, colorTitle, colors, opacityTitle, slider, percentage] { view.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(view) }
        NSLayoutConstraint.activate([
            keyTitle.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 30), keyTitle.topAnchor.constraint(equalTo: root.topAnchor, constant: 32),
            shortcutButton.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -30), shortcutButton.centerYAnchor.constraint(equalTo: keyTitle.centerYAnchor), shortcutButton.widthAnchor.constraint(equalToConstant: 142),
            status.leadingAnchor.constraint(equalTo: keyTitle.leadingAnchor), status.topAnchor.constraint(equalTo: keyTitle.bottomAnchor, constant: 11), status.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -25),
            colorTitle.leadingAnchor.constraint(equalTo: keyTitle.leadingAnchor), colorTitle.topAnchor.constraint(equalTo: status.bottomAnchor, constant: 27),
            colors.leadingAnchor.constraint(equalTo: keyTitle.leadingAnchor), colors.topAnchor.constraint(equalTo: colorTitle.bottomAnchor, constant: 12),
            opacityTitle.leadingAnchor.constraint(equalTo: keyTitle.leadingAnchor), opacityTitle.topAnchor.constraint(equalTo: colors.bottomAnchor, constant: 27),
            percentage.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -30), percentage.centerYAnchor.constraint(equalTo: opacityTitle.centerYAnchor),
            slider.leadingAnchor.constraint(equalTo: keyTitle.leadingAnchor), slider.trailingAnchor.constraint(equalTo: percentage.trailingAnchor), slider.topAnchor.constraint(equalTo: opacityTitle.bottomAnchor, constant: 10)
        ])
        NotificationCenter.default.addObserver(self, selector: #selector(stopRecording), name: NSWindow.willCloseNotification, object: window)
        NotificationCenter.default.addObserver(self, selector: #selector(stopRecording), name: NSWindow.didResignKeyNotification, object: window)
    }
    required init?(coder: NSCoder) { fatalError() }
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
