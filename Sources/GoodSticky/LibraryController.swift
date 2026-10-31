import AppKit

final class LibraryWindow: NSWindow {
    // Esc closes the list (the search field consumes Esc first while it has text).
    override func cancelOperation(_ sender: Any?) { performClose(sender) }
    override func performKeyEquivalent(with event: NSEvent) -> Bool { super.performKeyEquivalent(with: event) || KeyCommands.perform(event) }
}

final class LibraryController: NSWindowController, NSSearchFieldDelegate, NSWindowDelegate {
    let root = NSVisualEffectView()
    let grid = FlippedView()
    let scroll = NSScrollView()
    let search = NSSearchField()
    let heading = label("Notes", size: 20, weight: .bold)
    let count = label("", size: 11, color: secondaryInk)
    let filter = NSSegmentedControl(labels: ["On Desktop", "Hidden", "All"], trackingMode: .selectOne, target: nil, action: nil)
    let empty = EmptyStateView()
    let hint = label("", size: 11, color: tertiaryInk)
    private(set) var cards: [NoteCard] = []
    private static let cardHeight: CGFloat = 74, cardGap: CGFloat = 6

    init() {
        let window = LibraryWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 520), styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        super.init(window: window)
        window.title = "Notes"; window.titleVisibility = .hidden; window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false; window.minSize = NSSize(width: 330, height: 320); window.delegate = self
        root.material = .sidebar; root.blendingMode = .behindWindow; root.state = .followsWindowActiveState
        window.contentView = root; window.center()
        search.placeholderString = "Search notes and attachments"; search.delegate = self; search.sendsSearchStringImmediately = true
        search.controlSize = .large
        filter.selectedSegment = 0; filter.target = self; filter.action = #selector(filterChanged); filter.segmentDistribution = .fillEqually
        let new = NSButton(title: "New Note", image: symbol("square.and.pencil", size: 12, weight: .semibold) ?? NSImage(), target: self, action: #selector(newNote))
        new.imagePosition = .imageLeading; new.bezelStyle = .rounded; new.controlSize = .regular; new.keyEquivalent = "n"; new.keyEquivalentModifierMask = .command
        new.toolTip = "New note (⌘N)"
        let settings = IconButton("Preferences", symbol: "gearshape", size: 13) { AppDelegate.shared.showPreferences() }
        let separator = SeparatorLine()
        scroll.drawsBackground = false; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true; scroll.documentView = grid
        scroll.automaticallyAdjustsContentInsets = false; scroll.contentInsets = NSEdgeInsets(top: 4, left: 0, bottom: 8, right: 0)
        for view in [heading, count, new, search, filter, scroll, empty, separator, hint, settings] as [NSView] { view.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(view) }
        NSLayoutConstraint.activate([
            heading.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 18), heading.topAnchor.constraint(equalTo: root.topAnchor, constant: 38),
            count.leadingAnchor.constraint(equalTo: heading.leadingAnchor), count.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 1),
            new.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16), new.centerYAnchor.constraint(equalTo: heading.bottomAnchor, constant: -2),
            search.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16), search.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16), search.topAnchor.constraint(equalTo: count.bottomAnchor, constant: 14),
            filter.leadingAnchor.constraint(equalTo: search.leadingAnchor), filter.trailingAnchor.constraint(equalTo: search.trailingAnchor), filter.topAnchor.constraint(equalTo: search.bottomAnchor, constant: 10),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor), scroll.topAnchor.constraint(equalTo: filter.bottomAnchor, constant: 8), scroll.bottomAnchor.constraint(equalTo: separator.topAnchor),
            empty.centerXAnchor.constraint(equalTo: scroll.centerXAnchor), empty.centerYAnchor.constraint(equalTo: scroll.centerYAnchor, constant: -10),
            empty.leadingAnchor.constraint(greaterThanOrEqualTo: root.leadingAnchor, constant: 30),
            separator.leadingAnchor.constraint(equalTo: root.leadingAnchor), separator.trailingAnchor.constraint(equalTo: root.trailingAnchor), separator.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -40),
            hint.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 18), hint.centerYAnchor.constraint(equalTo: root.bottomAnchor, constant: -20),
            hint.trailingAnchor.constraint(lessThanOrEqualTo: settings.leadingAnchor, constant: -8),
            settings.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12), settings.centerYAnchor.constraint(equalTo: hint.centerYAnchor), settings.widthAnchor.constraint(equalToConstant: 28), settings.heightAnchor.constraint(equalToConstant: 26)
        ])
        root.layoutSubtreeIfNeeded(); refresh()
        NotificationCenter.default.addObserver(self, selector: #selector(layoutRows), name: NSWindow.didResizeNotification, object: window)
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc func newNote() { AppDelegate.shared.createNote() }
    @objc func filterChanged() { refresh() }
    func refresh() {
        let store = NoteStore.shared
        let existing = Dictionary(uniqueKeysWithValues: cards.compactMap { card in card.note.map { ($0.id, card) } })
        let query = search.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let notes = store.notes.filter {
            (filter.selectedSegment == 2 || (filter.selectedSegment == 1 ? $0.hidden : !$0.hidden)) &&
            (query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.text.localizedCaseInsensitiveContains(query) || $0.attachments.contains { $0.name.localizedCaseInsensitiveContains(query) })
        }.sorted { $0.modified > $1.modified }
        let focusedID = (window?.firstResponder as? NoteCard)?.note?.id
        let previous = cards
        cards = notes.map { note in existing[note.id].flatMap { $0.note == note ? $0 : nil } ?? NoteCard(note: note) }
        let retained = Set(cards.map(ObjectIdentifier.init))
        previous.filter { !retained.contains(ObjectIdentifier($0)) }.forEach { $0.removeFromSuperview() }
        for card in cards where card.superview == nil { grid.addSubview(card) }
        if let focusedID, let card = cards.first(where: { $0.note?.id == focusedID }), window?.firstResponder !== card { window?.makeFirstResponder(card) }
        let visible = store.notes.filter { !$0.hidden }.count, hidden = store.notes.count - visible
        filter.setLabel("On Desktop  \(visible)", forSegment: 0); filter.setLabel("Hidden  \(hidden)", forSegment: 1); filter.setLabel("All  \(store.notes.count)", forSegment: 2)
        count.stringValue = store.notes.isEmpty ? "No notes yet" : "\(visible) on desktop · \(hidden) hidden"
        hint.stringValue = "\(HotKeyManager.display(store.preferences)) creates a note from anywhere"
        if !query.isEmpty { empty.configure(symbol: "magnifyingglass", title: "No matches", detail: "Nothing matches “\(query)”.") }
        else if filter.selectedSegment == 1 { empty.configure(symbol: "eye.slash", title: "No hidden notes", detail: "Notes you hide are kept here. Empty notes are deleted when hidden.") }
        else { empty.configure(symbol: "note.text", title: "Your desktop is clear", detail: "Click New Note or press \(HotKeyManager.display(store.preferences)).") }
        empty.isHidden = !cards.isEmpty
        layoutRows()
    }
    @objc func layoutRows() {
        let width = max(280, scroll.contentSize.width)
        for (index, card) in cards.enumerated() {
            card.frame = NSRect(x: 12, y: CGFloat(index) * (Self.cardHeight + Self.cardGap), width: width - 24, height: Self.cardHeight)
        }
        grid.frame = NSRect(x: 0, y: 0, width: width, height: max(scroll.contentSize.height - 12, CGFloat(cards.count) * (Self.cardHeight + Self.cardGap)))
    }
    func moveFocus(from card: NoteCard, by offset: Int) {
        guard let index = cards.firstIndex(where: { $0 === card }) else { return }
        let target = cards[max(0, min(cards.count - 1, index + offset))]
        window?.makeFirstResponder(target); target.scrollToVisible(target.bounds.insetBy(dx: 0, dy: -8))
    }
    func controlTextDidChange(_ obj: Notification) { refresh() }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        // ↓ from the search field moves into the list; Return opens the first result.
        if selector == #selector(NSResponder.moveDown(_:)), let first = cards.first { window?.makeFirstResponder(first); return true }
        if selector == #selector(NSResponder.insertNewline(_:)), let first = cards.first, !search.stringValue.isEmpty { _ = first.accessibilityPerformPress(); return true }
        return false
    }
    func present() {
        refresh(); window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        window?.makeFirstResponder(search)
    }
    func windowWillClose(_ notification: Notification) {
        if AppDelegate.shared.library === self { AppDelegate.shared.library = nil }
    }
    deinit { NotificationCenter.default.removeObserver(self) }
}

final class EmptyStateView: NSStackView {
    private let icon = NSImageView()
    private let title = label("", size: 14, weight: .semibold, color: secondaryInk)
    private let detail = label("", size: 12, color: tertiaryInk)
    init() {
        super.init(frame: .zero)
        orientation = .vertical; alignment = .centerX; spacing = 6
        icon.contentTintColor = tertiaryInk
        detail.alignment = .center; detail.lineBreakMode = .byWordWrapping; detail.maximumNumberOfLines = 2
        addArrangedSubview(icon); setCustomSpacing(10, after: icon); addArrangedSubview(title); addArrangedSubview(detail)
    }
    required init?(coder: NSCoder) { fatalError() }
    func configure(symbol name: String, title: String, detail: String) {
        icon.image = symbol(name, size: 28, weight: .light); self.title.stringValue = title; self.detail.stringValue = detail
    }
}

final class NoteCard: NSView {
    let note: StickyNote?
    private var tracking: NSTrackingArea?
    private var hovering = false
    private var buttons: [IconButton] = []
    /// Hidden notes keep a one-click delete visible at all times; no confirmation.
    private(set) var deleteButton: IconButton?
    private static let snoozeFormatter: DateFormatter = { let f = DateFormatter(); f.setLocalizedDateFormatFromTemplate("EEEjmm"); return f }()
    private static let relative: RelativeDateTimeFormatter = { let f = RelativeDateTimeFormatter(); f.unitsStyle = .short; return f }()
    init(note: StickyNote?) {
        self.note = note; super.init(frame: .zero)
        setAccessibilityElement(true); setAccessibilityRole(.button); setAccessibilityLabel(note?.title ?? "New note")
        guard let note else { return }
        setAccessibilityHelp(note.hidden ? "Hidden note. Press to show it on the desktop." : "Press to bring this note forward for editing.")
        setAccessibilityCustomActions([
            NSAccessibilityCustomAction(name: "Copy") { [weak self] in self?.copyText(); return true },
            NSAccessibilityCustomAction(name: note.hidden ? "Show" : "Hide") { NoteStore.shared.update(note.id) { $0.hidden.toggle() }; return true },
            NSAccessibilityCustomAction(name: "Delete") { AppDelegate.shared.confirmDelete(note.id); return true }
        ])
        if note.hidden {
            let trash = IconButton("Delete now", symbol: "trash", size: 13) { NoteStore.shared.delete(note.id) }
            trash.contentTintColor = .systemRed
            trash.setAccessibilityHelp("Permanently deletes this hidden note without asking.")
            deleteButton = trash; install(trash)
        }
    }
    private func copyText() {
        guard let note else { return }
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(note.text, forType: .string)
        buttons.first { $0.toolTip == "Copy note" }?.image = symbol("checkmark", size: 13, weight: .semibold)
    }
    private func install(_ button: IconButton) {
        addSubview(button); buttons.append(button)
        button.focusChanged = { [weak self] focused in
            if focused { self?.showControls(true) }
            else { DispatchQueue.main.async { [weak self] in self?.updateControls() } }
        }
        needsLayout = true
    }
    /// Hover buttons are built the first time a card is hovered or focused, not for every
    /// card each time the list opens.
    private func ensureButtons() {
        guard let note, buttons.count < (deleteButton == nil ? 3 : 4) else { return }
        install(IconButton("More actions", symbol: "ellipsis.circle", size: 14) { [weak self] in self?.showMenu() })
        install(IconButton("Copy note", symbol: "doc.on.doc", size: 13) { [weak self] in self?.copyText() })
        install(IconButton(note.hidden ? "Show note" : "Hide note", symbol: note.hidden ? "eye" : "eye.slash", size: 13) {
            NoteStore.shared.update(note.id) { $0.hidden.toggle() }
        })
    }
    required init?(coder: NSCoder) { fatalError() }
    override var acceptsFirstResponder: Bool { true }
    override var focusRingMaskBounds: NSRect { bounds }
    override func drawFocusRingMask() { NSBezierPath(roundedRect: bounds, xRadius: 10, yRadius: 10).fill() }
    override func becomeFirstResponder() -> Bool { showControls(true); return true }
    override func resignFirstResponder() -> Bool { DispatchQueue.main.async { [weak self] in self?.updateControls() }; return true }
    func showControls(_ show: Bool) {
        if show { ensureButtons() }
        buttons.forEach { $0.isHidden = !show && $0 !== deleteButton }; needsDisplay = true
    }
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
        for (index, button) in buttons.enumerated() { button.frame = NSRect(x: bounds.width - 36 - CGFloat(index) * 30, y: (bounds.height - 26) / 2, width: 28, height: 26) }
    }
    override func accessibilityPerformPress() -> Bool {
        if let note { AppDelegate.shared.library?.close(); AppDelegate.shared.reveal(note.id) }; return true
    }
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        if event.clickCount >= 1 { _ = accessibilityPerformPress() }
    }
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 49, 76: _ = accessibilityPerformPress()
        case 125: AppDelegate.shared.library?.moveFocus(from: self, by: 1)
        case 126:
            if AppDelegate.shared.library?.cards.first === self { window?.makeFirstResponder(AppDelegate.shared.library?.search) }
            else { AppDelegate.shared.library?.moveFocus(from: self, by: -1) }
        case 51, 117: if let note { AppDelegate.shared.confirmDelete(note.id) }
        default: super.keyDown(with: event)
        }
    }
    func showMenu() {
        guard let menu = menu(for: NSApp.currentEvent ?? NSEvent()) else { return }
        menu.popUp(positioning: nil, at: NSPoint(x: bounds.width - 36, y: bounds.minY + 8), in: self)
    }
    override func menu(for event: NSEvent) -> NSMenu? {
        guard let note else { return nil }
        let menu = NSMenu()
        let open = ClosureMenuItem(note.hidden ? "Show on Desktop" : "Open") { AppDelegate.shared.library?.close(); AppDelegate.shared.reveal(note.id) }
        open.image = symbol(note.hidden ? "eye" : "arrow.up.forward.app", size: 12); menu.addItem(open)
        let copy = ClosureMenuItem("Copy Text") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(note.text, forType: .string) }
        copy.image = symbol("doc.on.doc", size: 12); menu.addItem(copy)
        if !note.hidden {
            let hide = ClosureMenuItem("Hide") { NoteStore.shared.update(note.id) { $0.hidden = true } }
            hide.image = symbol("eye.slash", size: 12); menu.addItem(hide)
        }
        menu.addItem(.separator())
        let delete = ClosureMenuItem(note.hidden || note.isBlank ? "Delete" : "Delete…") { AppDelegate.shared.confirmDelete(note.id) }
        delete.image = symbol("trash", size: 12); menu.addItem(delete)
        return menu
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
    override func draw(_ dirtyRect: NSRect) {
        guard let note else { return }
        let focused = window?.firstResponder === self
        let card = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 10, yRadius: 10)
        NSColor.labelColor.withAlphaComponent(hovering || focused ? 0.085 : 0.04).setFill(); card.fill()
        NSColor.labelColor.withAlphaComponent(0.06).setStroke(); card.lineWidth = 1; card.stroke()

        // A miniature of the note itself: paper color, folded corner, a few ink lines.
        let chip = NSRect(x: 12, y: (bounds.height - 40) / 2, width: 34, height: 40)
        let fold: CGFloat = 8
        let paper = NSBezierPath()
        paper.move(to: NSPoint(x: chip.minX + 4, y: chip.minY)); paper.line(to: NSPoint(x: chip.maxX - 4, y: chip.minY))
        paper.curve(to: NSPoint(x: chip.maxX, y: chip.minY + 4), controlPoint1: NSPoint(x: chip.maxX - 2, y: chip.minY), controlPoint2: NSPoint(x: chip.maxX, y: chip.minY + 2))
        paper.line(to: NSPoint(x: chip.maxX, y: chip.maxY - fold)); paper.line(to: NSPoint(x: chip.maxX - fold, y: chip.maxY))
        paper.line(to: NSPoint(x: chip.minX + 4, y: chip.maxY))
        paper.curve(to: NSPoint(x: chip.minX, y: chip.maxY - 4), controlPoint1: NSPoint(x: chip.minX + 2, y: chip.maxY), controlPoint2: NSPoint(x: chip.minX, y: chip.maxY - 2))
        paper.line(to: NSPoint(x: chip.minX, y: chip.minY + 4))
        paper.curve(to: NSPoint(x: chip.minX + 4, y: chip.minY), controlPoint1: NSPoint(x: chip.minX, y: chip.minY + 2), controlPoint2: NSPoint(x: chip.minX + 2, y: chip.minY))
        paper.close()
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.18); shadow.shadowBlurRadius = 2; shadow.shadowOffset = NSSize(width: 0, height: -1); shadow.set()
        note.theme.paper.withAlphaComponent(note.hidden ? 0.55 : 1).setFill(); paper.fill()
        NSGraphicsContext.restoreGraphicsState()
        note.theme.ink.withAlphaComponent(0.18).setStroke(); paper.lineWidth = 0.5; paper.stroke()
        let corner = NSBezierPath(); corner.move(to: NSPoint(x: chip.maxX, y: chip.maxY - fold)); corner.line(to: NSPoint(x: chip.maxX - fold, y: chip.maxY - fold)); corner.line(to: NSPoint(x: chip.maxX - fold, y: chip.maxY)); corner.close()
        note.theme.ink.withAlphaComponent(0.16).setFill(); corner.fill()
        note.theme.ink.withAlphaComponent(0.32).setFill()
        for (index, width) in [16.0, 20, 12].enumerated() { NSBezierPath(roundedRect: NSRect(x: chip.minX + 6, y: chip.maxY - 14 - CGFloat(index) * 6, width: width, height: 2), xRadius: 1, yRadius: 1).fill() }
        if note.hidden, let slash = symbol(note.snoozedUntil == nil ? "eye.slash.fill" : "moon.zzz.fill", size: 10, weight: .semibold) {
            let tinted = slash.copy() as! NSImage; tinted.isTemplate = true
            NSGraphicsContext.saveGraphicsState(); note.theme.ink.withAlphaComponent(0.7).set()
            let rect = NSRect(x: chip.midX - 6, y: chip.minY + 4, width: 13, height: 10)
            tinted.draw(in: rect); rect.fill(using: .sourceIn)
            NSGraphicsContext.restoreGraphicsState()
        }

        let textX: CGFloat = 58
        // Semantic secondary colors use vibrancy in native controls. Custom-drawn
        // text needs opaque colors or it can turn nearly black on a dark sidebar.
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let secondaryInk = NSColor(calibratedWhite: dark ? 0.82 : 0.35, alpha: 1)
        let tertiaryInk = NSColor(calibratedWhite: dark ? 0.73 : 0.43, alpha: 1)
        let shown = buttons.filter { !$0.isHidden }.count
        let available = bounds.width - textX - (shown > 0 ? CGFloat(shown) * 30 + 14 : 12)
        let style = NSMutableParagraphStyle(); style.lineBreakMode = .byTruncatingTail
        let title = note.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Empty note" : note.title
        (title as NSString).draw(in: NSRect(x: textX, y: bounds.height - 29, width: available, height: 18), withAttributes: [.font: NSFont.systemFont(ofSize: 13, weight: .semibold), .foregroundColor: note.text.isEmpty ? secondaryInk : primaryInk, .paragraphStyle: style])
        let body = note.text.split(whereSeparator: \.isNewline).dropFirst().map { $0.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty } ?? ""
        let preview = body.isEmpty ? (note.attachments.isEmpty ? "No additional text" : note.attachments.map(\.name).joined(separator: ", ")) : body
        (preview as NSString).draw(in: NSRect(x: textX, y: bounds.height - 47, width: available, height: 16), withAttributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: secondaryInk, .paragraphStyle: style])
        var meta = [Date().timeIntervalSince(note.modified) < 60 ? "Edited just now" : "Edited " + Self.relative.localizedString(for: note.modified, relativeTo: Date())]
        if !note.attachments.isEmpty { meta.append("\(note.attachments.count) \(note.attachments.count == 1 ? "file" : "files")") }
        if note.stackID != nil { meta.append("Stacked") }
        if note.pinned { meta.append("Above apps") }
        if note.dockEdge != nil { meta.append("Side note") }
        if note.hidden, let wake = note.snoozedUntil { meta.insert("Snoozed until " + Self.snoozeFormatter.string(from: wake), at: 0) }
        (meta.joined(separator: " · ") as NSString).draw(in: NSRect(x: textX, y: 10, width: available, height: 15), withAttributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: tertiaryInk, .paragraphStyle: style])
    }
}

