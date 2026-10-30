import AppKit
import ImageIO
import UniformTypeIdentifiers

final class StickyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class WidgetSurface: NSView {
    var theme = NoteTheme.all[0] { didSet { needsDisplay = true } }
    var paperOpacity: CGFloat = 1 { didSet { needsDisplay = true } }
    var onHover: ((Bool) -> Void)?
    var onDrop: (([URL]) -> Void)?
    var onLayout: (() -> Void)?
    override func layout() { super.layout(); onLayout?() }
    private var tracking: NSTrackingArea?
    private var dropping = false
    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }
    required init?(coder: NSCoder) { fatalError() }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(rect: bounds, options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect], owner: self)
        addTrackingArea(tracking!)
    }
    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 7, yRadius: 7)
        theme.paper.withAlphaComponent(paperOpacity).setFill(); path.fill()
        theme.ink.withAlphaComponent(dropping ? 0.65 : 0.12).setStroke()
        path.lineWidth = dropping ? 3 : 1; path.stroke()

    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        dropping = true; needsDisplay = true; return .copy
    }
    override func draggingExited(_ sender: NSDraggingInfo?) { dropping = false; needsDisplay = true }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        dropping = false; needsDisplay = true
        let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        onDrop?(urls); return !urls.isEmpty
    }
}

final class DragHandle: NSView {
    var tint = NSColor.gray
    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
    override func draw(_ dirtyRect: NSRect) {
        tint.withAlphaComponent(0.35).setFill()
        for index in 0..<3 { NSBezierPath(ovalIn: NSRect(x: 10 + CGFloat(index) * 3, y: 12, width: 1.5, height: 1.5)).fill() }
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
}

final class NoteTextView: NSTextView {
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

final class ResizeGrip: NSView {
    var tint = NSColor.gray
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func accessibilityValue() -> Any? { guard let frame = window?.frame else { return nil }; return "\(Int(frame.width)) × \(Int(frame.height))" }
    override var acceptsFirstResponder: Bool { true }
    private var dragFrame: NSRect?
    private var dragStart = NSPoint.zero
    override init(frame: NSRect) {
        super.init(frame: frame); toolTip = "Resize note"
        setAccessibilityElement(true); setAccessibilityRole(.button); setAccessibilityLabel("Resize note")
        setAccessibilityHelp("Drag the corner, or use arrow keys when focused.")
        setAccessibilityCustomActions([
            NSAccessibilityCustomAction(name: "Smaller") { [weak self] in self?.resizeBy(dx: -8, dy: -8); return true },
            NSAccessibilityCustomAction(name: "Larger") { [weak self] in self?.resizeBy(dx: 8, dy: 8); return true }
        ])
    }
    required init?(coder: NSCoder) { fatalError() }
    override func resetCursorRects() {
        if #available(macOS 15, *) { addCursorRect(bounds, cursor: .frameResize(position: .bottomRight, directions: [.inward, .outward])) }
        else { addCursorRect(bounds, cursor: .crosshair) }
    }
    override func draw(_ dirtyRect: NSRect) {
        tint.withAlphaComponent(0.55).setStroke()
        for offset in [4.0, 8.0] {
            let line = NSBezierPath(); line.lineWidth = 1; line.lineCapStyle = .round
            line.move(to: NSPoint(x: bounds.width - offset - 2, y: 3))
            line.line(to: NSPoint(x: bounds.width - 3, y: offset + 2)); line.stroke()
        }
    }
    override func accessibilityPerformPress() -> Bool { window?.makeFirstResponder(self) ?? false }
    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        window.makeFirstResponder(self)
        dragFrame = window.frame; dragStart = window.convertPoint(toScreen: event.locationInWindow)
    }
    override func mouseDragged(with event: NSEvent) {
        guard let window, let initial = dragFrame else { return }
        let mouse = window.convertPoint(toScreen: event.locationInWindow)
        setSize(initial: initial, width: initial.width + mouse.x - dragStart.x, height: initial.height - mouse.y + dragStart.y)
    }
    override func mouseUp(with event: NSEvent) { dragFrame = nil }
    private func setSize(initial: NSRect, width: CGFloat, height: CGFloat) {
        guard let window else { return }
        let maximum = (window.screen ?? NSScreen.main)?.visibleFrame.size ?? NSSize(width: 1920, height: 1080)
        let size = NSSize(width: min(maximum.width, max(window.minSize.width, width)), height: min(maximum.height, max(window.minSize.height, height)))
        window.setFrame(NSRect(x: initial.minX, y: initial.maxY - size.height, width: size.width, height: size.height), display: true)
    }
    private func resizeBy(dx: CGFloat, dy: CGFloat) {
        guard let initial = window?.frame else { return }
        setSize(initial: initial, width: initial.width + dx, height: initial.height + dy)
    }
    override func keyDown(with event: NSEvent) {
        let step: CGFloat = event.modifierFlags.contains(.shift) ? 1 : 8
        switch event.keyCode {
        case 123: resizeBy(dx: -step, dy: 0)
        case 124: resizeBy(dx: step, dy: 0)
        case 125: resizeBy(dx: 0, dy: -step)
        case 126: resizeBy(dx: 0, dy: step)
        default: super.keyDown(with: event)
        }
    }

}

final class WidgetController: NSWindowController, NSWindowDelegate, NSTextViewDelegate, NSPopoverDelegate {
    let store = NoteStore.shared
    var ids: [UUID]
    var activeID: UUID { didSet { if oldValue != activeID { textView.undoManager?.removeAllActions() } } }
    let surface = WidgetSurface(frame: .zero)
    let textView = NoteTextView(frame: .zero)
    let scroll = NSScrollView()
    let handle = DragHandle()
    let caption = label("", size: 10, weight: .medium)
    let controls = NSStackView()
    let attachments = NSStackView()
    let tabs = NSStackView()
    let grip = ResizeGrip(frame: .zero)
    private var appearancePopover: NSPopover?
    private var attachmentKey = ""
    private var tabCapacity = 0
    private var configuring = false
    private var layingOut = false
    private var transientFront = false
    private var groupRaised = false
    private var lastRenderedNote: StickyNote?
    var note: StickyNote? { store.note(activeID) }

    init(ids: [UUID]) {
        self.ids = ids; activeID = ids[0]
        let panel = StickyPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init(window: panel)
        configuring = true
        panel.delegate = self
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.minSize = NSSize(width: 140, height: 96)
        panel.contentView = surface
        setup()
        if let note {
            let saved = NSRect(x: note.x, y: note.y, width: max(140, note.width), height: max(96, note.height))
            let visible = (NSScreen.screens.first { $0.visibleFrame.intersects(saved) } ?? NSScreen.main)?.visibleFrame ?? saved
            let width = min(saved.width, visible.width), height = min(saved.height, visible.height)
            panel.setFrame(NSRect(x: min(max(saved.minX, visible.minX), visible.maxX - width), y: min(max(saved.minY, visible.minY), visible.maxY - height), width: width, height: height), display: true)
        }
        configuring = false
        refresh(); layoutNote()
    }
    required init?(coder: NSCoder) { fatalError() }
    func setup() {
        surface.addSubview(handle); handle.toolTip = "Drag to move"
        surface.addSubview(caption)
        let copy = ActionButton("Copy note", symbol: "doc.on.doc") { [weak self] in
            guard let self, let note = self.note else { return }
            NSPasteboard.general.clearContents(); NSPasteboard.general.setString(note.text, forType: .string)
            (self.controls.arrangedSubviews.first as? NSButton)?.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: "Copied")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                (self?.controls.arrangedSubviews.first as? NSButton)?.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: "Copy note")
            }
        }
        let hide = ActionButton("Hide note", symbol: "minus") { [weak self] in
            guard let self else { return }; self.store.update(self.activeID) { $0.hidden = true }
        }
        let attach = ActionButton("Attach files", symbol: "paperclip") { [weak self] in self?.showAttachments() }
        let appearance = ActionButton("Color and opacity", symbol: "paintpalette") { [weak self] in self?.showAppearance() }
        let menu = ActionButton("Note options", symbol: "ellipsis") { [weak self] in self?.showMenu() }
        controls.orientation = .horizontal; controls.spacing = 0; controls.isHidden = true
        for button in [copy, hide, attach, appearance, menu] {
            controls.addArrangedSubview(button)
            button.translatesAutoresizingMaskIntoConstraints = false
            button.widthAnchor.constraint(equalToConstant: 21).isActive = true
            button.heightAnchor.constraint(equalToConstant: 22).isActive = true
        }
        surface.addSubview(controls)
        scroll.drawsBackground = false; scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        textView.allowsUndo = true; textView.isRichText = false; textView.drawsBackground = false
        textView.font = .systemFont(ofSize: 13)
        textView.textContainerInset = NSSize(width: 0, height: 1)
        textView.isVerticallyResizable = true; textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]; textView.textContainer?.widthTracksTextView = true
        textView.isAutomaticSpellingCorrectionEnabled = false; textView.delegate = self
        textView.onFiles = { [weak self] in self?.addFiles($0) }
        textView.onCycle = { [weak self] direction in
            guard let self, let index = self.ids.firstIndex(of: self.activeID), self.ids.count > 1 else { return }
            self.activeID = self.ids[(index + direction + self.ids.count) % self.ids.count]; self.refresh()
        }
        scroll.documentView = textView; surface.addSubview(scroll)
        attachments.orientation = .vertical; attachments.alignment = .leading; attachments.spacing = 4
        tabs.orientation = .horizontal; tabs.spacing = 4
        surface.addSubview(attachments); surface.addSubview(tabs); surface.addSubview(grip)
        surface.onHover = { [weak self] hovering in
            guard let self else { return }
            self.controls.isHidden = !hovering && self.window?.isKeyWindow != true
        }
        surface.onDrop = { [weak self] in self?.addFiles($0) }
        surface.onLayout = { [weak self] in self?.layoutNote() }
    }
    func refreshCaption() { caption.stringValue = ids.count > 1 ? "\(ids.count) notes" : "" }
    func refresh() {
        guard let note, note != lastRenderedNote else { return }
        lastRenderedNote = note; configuring = true
        window?.title = note.title
        surface.theme = note.theme; surface.paperOpacity = note.opacity
        textView.textColor = note.theme.ink; textView.insertionPointColor = note.theme.ink
        if textView.string != note.text { textView.string = note.text }
        let paragraph = NSMutableParagraphStyle(); paragraph.lineSpacing = 2
        textView.defaultParagraphStyle = paragraph
        textView.typingAttributes = [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: note.theme.ink, .paragraphStyle: paragraph]
        caption.textColor = note.theme.ink.withAlphaComponent(0.85)
        handle.tint = note.theme.ink; handle.needsDisplay = true
        grip.tint = note.theme.ink; grip.needsDisplay = true
        for case let button as NSButton in controls.arrangedSubviews { button.contentTintColor = note.theme.ink }
        if let attachmentButton = controls.arrangedSubviews.dropFirst(2).first as? NSButton {
            attachmentButton.toolTip = note.attachments.isEmpty ? "Attach files" : "\(note.attachments.count) \(note.attachments.count == 1 ? "attachment" : "attachments")"
            attachmentButton.setAccessibilityLabel(attachmentButton.toolTip)
        }
        refreshCaption()
        if !transientFront && !groupRaised { setLevel() }
        attachmentKey = ""; tabCapacity = 0
        configuring = false; layoutNote()
    }
    func layoutNote() {
        guard !layingOut, let note else { return }
        layingOut = true; defer { layingOut = false }
        let width = surface.bounds.width, height = surface.bounds.height
        guard width > 0, height > 0 else { return }
        handle.frame = NSRect(x: 0, y: height - 27, width: max(24, width - 112), height: 27)
        controls.frame = NSRect(x: width - 111, y: height - 25, width: 105, height: 22)
        caption.isHidden = width < 245
        caption.frame = NSRect(x: 12, y: height - 22, width: max(0, width - 130), height: 15)
        grip.frame = NSRect(x: width - 17, y: 0, width: 17, height: 17)
        let capacity = max(1, min(4, Int((width - 55) / 56)))
        if capacity != tabCapacity { tabCapacity = capacity; rebuildTabs() }
        let tabHeight: CGFloat = ids.count > 1 ? 22 : 0
        var bottom: CGFloat = 9
        tabs.isHidden = tabHeight == 0
        tabs.frame = NSRect(x: 12, y: bottom, width: max(0, width - 32), height: tabHeight)
        if tabHeight > 0 { bottom += tabHeight + 5 }
        let budget = max(0, height - 28 - bottom - 48)
        let previewHeight: CGFloat = height >= 240 && budget >= 94 ? 64 : height >= 180 && budget >= 70 ? 40 : 0
        let showImage = previewHeight > 0
        let rowCount = height >= 270 ? min(2, note.attachments.count) : height >= 145 ? min(1, note.attachments.count) : 0
        let key = "\(activeID)-\(note.themeID)-\(note.attachments.map(\.id))-\(rowCount)-\(previewHeight)"
        if key != attachmentKey {
            attachmentKey = key; rebuildAttachments(rows: rowCount, imageHeight: previewHeight)
        }
        let imageHeight: CGFloat = showImage && note.attachments.contains(where: { UTType(filenameExtension: URL(fileURLWithPath: $0.name).pathExtension)?.conforms(to: .image) == true }) ? previewHeight + 4 : 0
        let attachmentHeight = CGFloat(rowCount) * 22 + CGFloat(max(0, rowCount - 1)) * 4 + imageHeight
        attachments.isHidden = attachmentHeight == 0
        attachments.frame = NSRect(x: 12, y: bottom, width: max(0, width - 24), height: attachmentHeight)
        if attachmentHeight > 0 { bottom += attachmentHeight + 6 }
        scroll.frame = NSRect(x: 10, y: bottom, width: max(0, width - 20), height: max(20, height - 28 - bottom))
    }
    func setLevel() {
        guard let note else { return }
        window?.level = note.pinned ? .floating : NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
    }
    func show(focus: Bool = false) {
        if focus {
            transientFront = true; window?.level = .floating
            window?.makeKeyAndOrderFront(nil); window?.makeFirstResponder(textView)
        } else { window?.orderFrontRegardless() }
    }
    func bringForward() { groupRaised = true; transientFront = false; window?.level = .floating; window?.orderFrontRegardless() }
    func returnToDesktop() { groupRaised = false; transientFront = false; setLevel() }
    func windowDidResignKey(_ notification: Notification) {
        transientFront = false; if !groupRaised && appearancePopover?.isShown != true && window?.attachedSheet == nil { setLevel() }; controls.isHidden = true
        if AppDelegate.shared.library?.window?.isVisible == true { AppDelegate.shared.library?.refresh() }
    }
    func windowDidBecomeKey(_ notification: Notification) { controls.isHidden = false }
    func windowDidMove(_ notification: Notification) { saveFrame() }
    func windowDidResize(_ notification: Notification) { layoutNote(); saveFrame() }
    func saveFrame() {
        guard !configuring, let frame = window?.frame, let note else { return }
        guard note.x != frame.minX || note.y != frame.minY || note.width != frame.width || note.height != frame.height else { return }
        store.updateMany(ids, notify: false) { $0.x = frame.minX; $0.y = frame.minY; $0.width = frame.width; $0.height = frame.height }
    }
    func textDidChange(_ notification: Notification) {
        store.update(activeID, notify: false) { $0.text = textView.string }
        window?.title = note?.title ?? "Untitled note"
    }
    func addFiles(_ urls: [URL]) {
        caption.stringValue = "Adding files…"
        store.attach(urls, to: activeID) { [weak self] in self?.refreshCaption() }
    }
    func showAttachments() {
        guard let note, !note.attachments.isEmpty else { chooseFiles(); return }
        let menu = NSMenu()
        for attachment in note.attachments {
            let file = NSMenuItem(title: attachment.name, action: nil, keyEquivalent: "")
            let actions = NSMenu()
            actions.addItem(ClosureMenuItem("Open") { [weak self] in guard let self else { return }; NSWorkspace.shared.open(self.store.attachmentURL(attachment)) })
            actions.addItem(ClosureMenuItem("Remove") { [weak self] in guard let self else { return }; self.store.removeAttachment(attachment, from: self.activeID) })
            file.submenu = actions; menu.addItem(file)
        }
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem("Add files…") { [weak self] in self?.chooseFiles() })
        menu.popUp(positioning: nil, at: NSPoint(x: surface.bounds.width - 60, y: surface.bounds.height - 24), in: surface)
    }
    func chooseFiles() {
        let picker = NSOpenPanel(); picker.allowsMultipleSelection = true; picker.canChooseDirectories = false; picker.prompt = "Attach"
        guard let window else { return }
        picker.beginSheetModal(for: window) { [weak self] response in if response == .OK { self?.addFiles(picker.urls) } }
    }
    func rebuildAttachments(rows: Int, imageHeight: CGFloat) {
        attachments.arrangedSubviews.forEach { attachments.removeArrangedSubview($0); $0.removeFromSuperview() }
        guard let note else { return }
        if imageHeight > 0, let picture = note.attachments.first(where: { UTType(filenameExtension: URL(fileURLWithPath: $0.name).pathExtension)?.conforms(to: .image) == true }) {
            let preview = ActionButton("Open " + picture.name) { [weak self] in guard let self else { return }; NSWorkspace.shared.open(self.store.attachmentURL(picture)) }
            preview.title = ""; preview.imageScaling = .scaleProportionallyUpOrDown
            attachments.addArrangedSubview(preview); preview.translatesAutoresizingMaskIntoConstraints = false
            preview.widthAnchor.constraint(equalTo: attachments.widthAnchor).isActive = true
            preview.heightAnchor.constraint(equalToConstant: imageHeight).isActive = true
            ThumbnailLoader.shared.load(store.attachmentURL(picture), pixels: 440) { [weak preview] image in preview?.image = image }
        }
        for attachment in note.attachments.prefix(rows) {
            let row = NSStackView(); row.spacing = 4
            let file = ActionButton(attachment.name, symbol: "doc") { [weak self] in guard let self else { return }; NSWorkspace.shared.open(self.store.attachmentURL(attachment)) }
            file.imagePosition = .imageLeading; file.alignment = .left; file.lineBreakMode = .byTruncatingMiddle
            file.font = .systemFont(ofSize: 10); file.contentTintColor = note.theme.ink
            let remove = ActionButton("Remove attachment", symbol: "xmark") { [weak self] in guard let self else { return }; self.store.removeAttachment(attachment, from: self.activeID) }
            remove.contentTintColor = note.theme.ink
            row.addArrangedSubview(file); row.addArrangedSubview(remove); attachments.addArrangedSubview(row)
            row.translatesAutoresizingMaskIntoConstraints = false
            row.widthAnchor.constraint(equalTo: attachments.widthAnchor).isActive = true
            row.heightAnchor.constraint(equalToConstant: 22).isActive = true
            remove.widthAnchor.constraint(equalToConstant: 18).isActive = true
        }
    }
    func rebuildTabs() {
        tabs.arrangedSubviews.forEach { tabs.removeArrangedSubview($0); $0.removeFromSuperview() }
        guard ids.count > 1 else { return }
        var displayed = Array(ids.prefix(tabCapacity))
        if !displayed.contains(activeID) { displayed[displayed.count - 1] = activeID }
        for id in displayed {
            let title = store.note(id)?.title ?? "Untitled note"
            let button = ActionButton(title) { [weak self] in self?.activeID = id; self?.refresh() }
            button.toolTip = title + " · ⌃Tab"; button.font = .systemFont(ofSize: 10)
            button.lineBreakMode = .byTruncatingTail; button.contentTintColor = note?.theme.ink
            button.setAccessibilityRole(.radioButton); button.setAccessibilityValue(id == activeID ? 1 : 0)
            button.wantsLayer = true; button.layer?.cornerRadius = 4
            button.layer?.backgroundColor = id == activeID ? note?.theme.ink.withAlphaComponent(0.14).cgColor : NSColor.clear.cgColor
            tabs.addArrangedSubview(button); button.translatesAutoresizingMaskIntoConstraints = false
            button.widthAnchor.constraint(equalToConstant: 52).isActive = true
        }
        if ids.count > displayed.count {
            let more = ActionButton("More notes", symbol: "ellipsis") { [weak self] in
                guard let self else { return }
                let menu = NSMenu()
                for id in self.ids {
                    let item = ClosureMenuItem(self.store.note(id)?.title ?? "Untitled note") { [weak self] in self?.activeID = id; self?.refresh() }
                    item.state = id == self.activeID ? .on : .off; menu.addItem(item)
                }
                menu.popUp(positioning: nil, at: NSPoint(x: 12, y: 28), in: self.surface)
            }
            more.contentTintColor = note?.theme.ink; tabs.addArrangedSubview(more); more.translatesAutoresizingMaskIntoConstraints = false
            more.widthAnchor.constraint(equalToConstant: 22).isActive = true
        }
    }
    func showAppearance() {
        let controller = NoteAppearanceController(noteID: activeID)
        let popover = NSPopover(); popover.delegate = self; popover.behavior = .transient; popover.contentViewController = controller
        appearancePopover = popover
        popover.show(relativeTo: NSRect(x: surface.bounds.width - 48, y: surface.bounds.height - 26, width: 20, height: 20), of: surface, preferredEdge: .maxY)
    }
    func popoverDidClose(_ notification: Notification) { if window?.isKeyWindow != true && !groupRaised { setLevel() }; appearancePopover = nil }
    func showMenu() {
        guard let note else { return }
        let menu = NSMenu()
        @discardableResult func item(_ title: String, _ action: @escaping () -> Void) -> NSMenuItem {
            let item = ClosureMenuItem(title, action: action); menu.addItem(item); return item
        }
        item("Attach files…") { [weak self] in self?.chooseFiles() }
        let themes = NSMenu()
        for theme in NoteTheme.all {
            let choice = ClosureMenuItem(theme.name) { [weak self] in guard let self else { return }; self.store.update(self.activeID) { $0.themeID = theme.id } }
            choice.state = theme.id == note.themeID ? .on : .off; themes.addItem(choice)
        }
        let themeItem = NSMenuItem(title: "Paper color", action: nil, keyEquivalent: ""); themeItem.submenu = themes; menu.addItem(themeItem)
        let opacityMenu = NSMenu()
        for value in [1.0, 0.9, 0.8, 0.65, 0.5, 0.35] {
            let choice = ClosureMenuItem("\(Int(value * 100))%") { [weak self] in guard let self else { return }; self.store.update(self.activeID) { $0.opacity = value } }
            choice.state = abs(value - note.opacity) < 0.01 ? .on : .off; opacityMenu.addItem(choice)
        }
        let opacityItem = NSMenuItem(title: "Paper opacity", action: nil, keyEquivalent: ""); opacityItem.submenu = opacityMenu; menu.addItem(opacityItem)
        item(note.pinned ? "Keep on desktop" : "Keep above other apps") { [weak self] in guard let self else { return }; AppDelegate.shared.setPinned(self.activeID, pinned: !note.pinned) }
        menu.addItem(.separator())
        if ids.count > 1 {
            item("Remove this note from stack") { [weak self] in guard let self else { return }; AppDelegate.shared.unstack(self.activeID) }
        }
        let stackMenu = NSMenu()
        for candidate in store.notes where !ids.contains(candidate.id) && !candidate.hidden {
            let choice = ClosureMenuItem(String(candidate.title.prefix(40))) { [weak self] in
                guard let self else { return }
                AppDelegate.shared.stack(self.activeID, with: candidate.id)
            }
            stackMenu.addItem(choice)
        }
        if stackMenu.items.count > 0 {
            let stackItem = NSMenuItem(title: "Stack with…", action: nil, keyEquivalent: ""); stackItem.submenu = stackMenu; menu.addItem(stackItem)
        }
        if !note.attachments.isEmpty {
            let files = NSMenu()
            for attachment in note.attachments { files.addItem(ClosureMenuItem(attachment.name) { NSWorkspace.shared.open(self.store.attachmentURL(attachment)) }) }
            let filesItem = NSMenuItem(title: "All attachments (\(note.attachments.count))", action: nil, keyEquivalent: ""); filesItem.submenu = files; menu.addItem(filesItem)
        }
        item("All notes…") { AppDelegate.shared.showLibrary() }
        menu.addItem(.separator())
        item("Delete note…") { [weak self] in guard let self else { return }; AppDelegate.shared.confirmDelete(self.activeID) }
        menu.popUp(positioning: nil, at: NSPoint(x: surface.bounds.width - 30, y: surface.bounds.height - 40), in: surface)
    }
}

final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void
    init(_ title: String, action: @escaping () -> Void) {
        handler = action
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }
    required init(coder: NSCoder) { fatalError() }
    @objc private func run() { handler() }
}

final class ThumbnailLoader {
    static let shared = ThumbnailLoader()
    private let cache = NSCache<NSString, NSImage>()
    private let queue = DispatchQueue(label: "app.goodsticky.thumbnails", qos: .utility)
    init() { cache.countLimit = 24; cache.totalCostLimit = 4 * 1024 * 1024 }
    func load(_ url: URL, pixels: Int, completion: @escaping (NSImage?) -> Void) {
        let key = (url.path + "-" + String(pixels)) as NSString
        if let image = cache.object(forKey: key) { completion(image); return }
        queue.async { [weak self] in
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: pixels, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else { DispatchQueue.main.async { completion(nil) }; return }
            let image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
            self?.cache.setObject(image, forKey: key, cost: cg.bytesPerRow * cg.height)
            DispatchQueue.main.async { completion(image) }
        }
    }
}
