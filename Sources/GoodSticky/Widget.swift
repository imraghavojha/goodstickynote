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
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 16, yRadius: 16)
        theme.paper.withAlphaComponent(paperOpacity).setFill(); path.fill()
        theme.ink.withAlphaComponent(dropping ? 0.65 : 0.12).setStroke()
        path.lineWidth = dropping ? 3 : 1; path.stroke()
        // A subtle folded corner gives the widget a paper silhouette.
        let corner = NSBezierPath()
        corner.move(to: NSPoint(x: bounds.maxX - 24, y: 1))
        corner.line(to: NSPoint(x: bounds.maxX - 1, y: 24))
        corner.line(to: NSPoint(x: bounds.maxX - 1, y: 15))
        corner.curve(to: NSPoint(x: bounds.maxX - 15, y: 1), controlPoint1: NSPoint(x: bounds.maxX - 1, y: 5), controlPoint2: NSPoint(x: bounds.maxX - 5, y: 1))
        corner.close(); theme.ink.withAlphaComponent(0.045).setFill(); corner.fill()
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

final class WidgetController: NSWindowController, NSWindowDelegate, NSTextViewDelegate {
    let store = NoteStore.shared
    var ids: [UUID]
    var activeID: UUID { didSet { if oldValue != activeID { textView.undoManager?.removeAllActions() } } }
    let surface = WidgetSurface(frame: .zero)
    let textView = NoteTextView(frame: .zero)
    let scroll = NSScrollView()
    let handle = DragHandle()
    let caption = label("", size: 10, weight: .semibold)
    let controls = NSStackView()
    let attachments = NSStackView()
    let tabs = NSStackView()
    let footer = label("", size: 10, weight: .medium)
    private var attachmentIDs: [UUID] = []
    private var attachmentThemeID = ""
    private var allowsImagePreview = true
    private var attachmentHeight: NSLayoutConstraint!
    private var tabHeight: NSLayoutConstraint!
    private var configuring = false
    private var transientFront = false
    private var groupRaised = false
    private var lastRenderedNote: StickyNote?
    var note: StickyNote? { store.note(activeID) }

    init(ids: [UUID]) {
        self.ids = ids; activeID = ids[0]
        let panel = StickyPanel(contentRect: .zero, styleMask: [.borderless, .resizable, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init(window: panel)
        panel.delegate = self
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.minSize = NSSize(width: 260, height: 230)
        panel.contentView = surface
        setup()
        if let note {
            let saved = NSRect(x: note.x, y: note.y, width: note.width, height: note.height)
            let screen = NSScreen.screens.first(where: { $0.visibleFrame.intersects(saved) }) ?? NSScreen.main
            let visible = screen?.visibleFrame ?? saved
            let frame = NSRect(x: min(max(saved.minX, visible.minX), visible.maxX - min(saved.width, visible.width)),
                               y: min(max(saved.minY, visible.minY), visible.maxY - min(saved.height, visible.height)),
                               width: min(saved.width, visible.width), height: min(saved.height, visible.height))
            panel.setFrame(frame, display: true)
        }
        refresh()
    }
    required init?(coder: NSCoder) { fatalError() }
    func setup() {
        handle.translatesAutoresizingMaskIntoConstraints = false; surface.addSubview(handle)
        caption.translatesAutoresizingMaskIntoConstraints = false; handle.addSubview(caption)
        let copy = ActionButton("Copy note", symbol: "doc.on.doc") { [weak self] in
            guard let self, let note = self.note else { return }
            NSPasteboard.general.clearContents(); NSPasteboard.general.setString(note.text, forType: .string)
            self.caption.stringValue = "Copied"
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.refreshCaption() }
        }
        let hide = ActionButton("Hide note", symbol: "minus") { [weak self] in
            guard let self else { return }
            self.store.update(self.activeID) { $0.hidden = true }
        }
        let menu = ActionButton("Note options", symbol: "ellipsis") { [weak self] in self?.showMenu() }
        controls.orientation = .horizontal; controls.spacing = 5
        for button in [copy, hide, menu] {
            button.translatesAutoresizingMaskIntoConstraints = false
            button.widthAnchor.constraint(equalToConstant: 27).isActive = true
            button.heightAnchor.constraint(equalToConstant: 26).isActive = true
            controls.addArrangedSubview(button)
        }
        controls.alphaValue = 0
        controls.translatesAutoresizingMaskIntoConstraints = false; surface.addSubview(controls)
        scroll.drawsBackground = false; scroll.borderType = .noBorder; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        textView.allowsUndo = true; textView.isRichText = false; textView.drawsBackground = false
        textView.font = .systemFont(ofSize: 16)
        textView.textContainerInset = NSSize(width: 0, height: 5)
        textView.isVerticallyResizable = true; textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.isAutomaticQuoteSubstitutionEnabled = true
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.delegate = self
        textView.onFiles = { [weak self] in self?.addFiles($0) }
        textView.onCycle = { [weak self] direction in
            guard let self, let index = self.ids.firstIndex(of: self.activeID), self.ids.count > 1 else { return }
            self.activeID = self.ids[(index + direction + self.ids.count) % self.ids.count]
            self.refresh()
        }
        scroll.documentView = textView
        scroll.translatesAutoresizingMaskIntoConstraints = false; surface.addSubview(scroll)
        attachments.orientation = .vertical; attachments.alignment = .leading; attachments.spacing = 6
        attachments.translatesAutoresizingMaskIntoConstraints = false; surface.addSubview(attachments)
        tabs.orientation = .horizontal; tabs.spacing = 5
        tabs.translatesAutoresizingMaskIntoConstraints = false; surface.addSubview(tabs)
        footer.translatesAutoresizingMaskIntoConstraints = false; surface.addSubview(footer)
        attachmentHeight = attachments.heightAnchor.constraint(equalToConstant: 0)
        tabHeight = tabs.heightAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            handle.leadingAnchor.constraint(equalTo: surface.leadingAnchor), handle.trailingAnchor.constraint(equalTo: surface.trailingAnchor),
            handle.topAnchor.constraint(equalTo: surface.topAnchor), handle.heightAnchor.constraint(equalToConstant: 42),
            caption.leadingAnchor.constraint(equalTo: handle.leadingAnchor, constant: 20), caption.centerYAnchor.constraint(equalTo: handle.centerYAnchor),
            caption.trailingAnchor.constraint(lessThanOrEqualTo: controls.leadingAnchor, constant: -4),
            controls.trailingAnchor.constraint(equalTo: surface.trailingAnchor, constant: -11), controls.centerYAnchor.constraint(equalTo: handle.centerYAnchor),
            scroll.leadingAnchor.constraint(equalTo: surface.leadingAnchor, constant: 20), scroll.trailingAnchor.constraint(equalTo: surface.trailingAnchor, constant: -16),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 40),
            scroll.topAnchor.constraint(equalTo: handle.bottomAnchor), scroll.bottomAnchor.constraint(equalTo: attachments.topAnchor, constant: -8),
            attachments.leadingAnchor.constraint(equalTo: scroll.leadingAnchor), attachments.trailingAnchor.constraint(equalTo: scroll.trailingAnchor), attachmentHeight,
            attachments.bottomAnchor.constraint(equalTo: tabs.topAnchor, constant: -8),
            tabs.leadingAnchor.constraint(equalTo: scroll.leadingAnchor), tabs.trailingAnchor.constraint(lessThanOrEqualTo: surface.trailingAnchor, constant: -20), tabHeight,
            tabs.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -8),
            footer.leadingAnchor.constraint(equalTo: scroll.leadingAnchor), footer.bottomAnchor.constraint(equalTo: surface.bottomAnchor, constant: -16)
        ])
        surface.onHover = { [weak self] hovering in
            guard let self else { return }
            self.controls.alphaValue = hovering || self.window?.isKeyWindow == true ? 1 : 0
        }
        surface.onDrop = { [weak self] in self?.addFiles($0) }
    }
    func refreshCaption() { caption.stringValue = ids.count > 1 ? "\(ids.count) notes" : "" }
    func refresh() {
        guard let note, note != lastRenderedNote else { return }
        lastRenderedNote = note
        configuring = true
        defer { configuring = false }
        window?.title = note.title
        surface.theme = note.theme; surface.paperOpacity = note.opacity
        textView.textColor = note.theme.ink; textView.insertionPointColor = note.theme.ink
        if textView.string != note.text { textView.string = note.text }
        let paragraph = NSMutableParagraphStyle(); paragraph.lineSpacing = 5
        textView.defaultParagraphStyle = paragraph
        textView.typingAttributes = [.font: NSFont.systemFont(ofSize: 16), .foregroundColor: note.theme.ink, .paragraphStyle: paragraph]
        caption.textColor = note.theme.ink.withAlphaComponent(0.9)
        footer.textColor = note.theme.ink.withAlphaComponent(0.9)
        footer.stringValue = note.attachments.count > 2 ? "\(note.attachments.count) attachments" : ""
        for case let button as NSButton in controls.arrangedSubviews { button.contentTintColor = note.theme.ink }
        refreshCaption()
        if !transientFront && !groupRaised { setLevel() }
        if attachmentIDs != note.attachments.map(\.id) || attachmentThemeID != note.themeID { rebuildAttachments() }
        rebuildTabs()
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
    func bringForward() {
        groupRaised = true; transientFront = false
        window?.level = .floating
        window?.orderFrontRegardless()
    }
    func returnToDesktop() {
        groupRaised = false; transientFront = false
        setLevel()
    }
    func windowDidResignKey(_ notification: Notification) {
        transientFront = false
        if !groupRaised { setLevel() }
        controls.alphaValue = 0
        if AppDelegate.shared.library?.window?.isVisible == true { AppDelegate.shared.library?.refresh() }
    }
    func windowDidBecomeKey(_ notification: Notification) { controls.alphaValue = 1 }
    func windowDidMove(_ notification: Notification) { saveFrame() }
    func windowDidResize(_ notification: Notification) { saveFrame() }
    func saveFrame() {
        guard !configuring, let frame = window?.frame else { return }
        store.updateMany(ids, notify: false) { $0.x = frame.minX; $0.y = frame.minY; $0.width = frame.width; $0.height = frame.height }
        if allowsImagePreview != (frame.height >= 300) { rebuildAttachments() }
    }
    func textDidChange(_ notification: Notification) {
        guard !configuring else { return }
        store.update(activeID, notify: false) { $0.text = textView.string }
        window?.title = note?.title ?? "Untitled note"
    }
    func addFiles(_ urls: [URL]) {
        caption.stringValue = "Adding files…"
        store.attach(urls, to: activeID) { [weak self] in self?.refreshCaption() }
    }
    func chooseFiles() {
        let picker = NSOpenPanel(); picker.allowsMultipleSelection = true; picker.canChooseDirectories = false
        picker.prompt = "Attach"; picker.message = "Files are copied into your local GoodSticky library."
        guard let window else { return }
        picker.beginSheetModal(for: window) { [weak self] response in
            if response == .OK { self?.addFiles(picker.urls) }
        }
    }
    func rebuildAttachments() {
        attachments.arrangedSubviews.forEach { attachments.removeArrangedSubview($0); $0.removeFromSuperview() }
        guard let note else { return }
        attachmentIDs = note.attachments.map(\.id)
        attachmentThemeID = note.themeID
        allowsImagePreview = (window?.frame.height ?? 320) >= 300
        let imageAttachment = allowsImagePreview ? note.attachments.first { UTType(filenameExtension: URL(fileURLWithPath: $0.name).pathExtension)?.conforms(to: .image) == true } : nil
        if let imageAttachment {
            let imageButton = ActionButton("Open " + imageAttachment.name) { [weak self] in
                guard let self else { return }; NSWorkspace.shared.open(self.store.attachmentURL(imageAttachment))
            }
            imageButton.imageScaling = .scaleProportionallyUpOrDown
            imageButton.title = ""
            attachments.addArrangedSubview(imageButton)
            imageButton.translatesAutoresizingMaskIntoConstraints = false
            imageButton.widthAnchor.constraint(equalTo: attachments.widthAnchor).isActive = true
            imageButton.heightAnchor.constraint(equalToConstant: 82).isActive = true
            ThumbnailLoader.shared.load(store.attachmentURL(imageAttachment), pixels: 600) { [weak imageButton] image in
                imageButton?.image = image
                if image == nil { imageButton?.title = "Open image ↗" }
            }
        }
        let shown = Array(note.attachments.prefix(2))
        attachmentHeight.constant = CGFloat(shown.count) * 30 + (imageAttachment != nil ? 88 : 0)
        for attachment in shown {
            let row = NSStackView(); row.orientation = .horizontal; row.spacing = 6
            let button = ActionButton(attachment.name, symbol: "doc") { [weak self] in
                guard let self else { return }; NSWorkspace.shared.open(self.store.attachmentURL(attachment))
            }
            button.imagePosition = .imageLeading; button.contentTintColor = note.theme.ink
            button.lineBreakMode = .byTruncatingMiddle
            button.alignment = .left
            let remove = ActionButton("Remove attachment", symbol: "xmark.circle.fill") { [weak self] in
                guard let self else { return }; self.store.removeAttachment(attachment, from: self.activeID)
            }
            remove.contentTintColor = note.theme.ink.withAlphaComponent(0.8)
            row.addArrangedSubview(button); row.addArrangedSubview(remove)
            attachments.addArrangedSubview(row)
            row.translatesAutoresizingMaskIntoConstraints = false
            row.widthAnchor.constraint(equalTo: attachments.widthAnchor).isActive = true
            row.heightAnchor.constraint(equalToConstant: 24).isActive = true
            remove.widthAnchor.constraint(equalToConstant: 20).isActive = true
            ThumbnailLoader.shared.load(store.attachmentURL(attachment), pixels: 80) { [weak button] image in
                if let image, let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) { button?.image = NSImage(cgImage: cg, size: NSSize(width: 24, height: 24)) }
            }
        }

    }
    func rebuildTabs() {
        tabs.arrangedSubviews.forEach { tabs.removeArrangedSubview($0); $0.removeFromSuperview() }
        tabHeight.constant = ids.count > 1 ? 26 : 0
        guard ids.count > 1 else { return }
        var displayed = Array(ids.prefix(3))
        if !displayed.contains(activeID) { displayed[displayed.count - 1] = activeID }
        for id in displayed {
            let title = store.note(id)?.title ?? "Untitled note"
            let button = ActionButton(title) { [weak self] in self?.activeID = id; self?.attachmentIDs = []; self?.refresh() }
            button.toolTip = title + " · ⌃Tab"
            button.font = .systemFont(ofSize: 10, weight: .medium)
            button.lineBreakMode = .byTruncatingTail
            button.setAccessibilityRole(.radioButton)
            button.setAccessibilityValue(id == activeID ? 1 : 0)
            button.state = id == activeID ? .on : .off
            button.wantsLayer = true
            button.layer?.cornerRadius = 7
            button.layer?.backgroundColor = id == activeID ? note?.theme.ink.withAlphaComponent(0.12).cgColor : NSColor.clear.cgColor
            button.contentTintColor = note?.theme.ink
            tabs.addArrangedSubview(button)
            button.widthAnchor.constraint(equalToConstant: 52).isActive = true
        }
        if ids.count > 3 {
            let more = ActionButton("More notes in stack", symbol: "ellipsis") { [weak self] in
                guard let self else { return }
                let menu = NSMenu()
                for id in self.ids {
                    let item = ClosureMenuItem(self.store.note(id)?.title ?? "Untitled note") { [weak self] in
                        self?.activeID = id; self?.attachmentIDs = []; self?.refresh()
                    }
                    item.state = id == self.activeID ? .on : .off
                    menu.addItem(item)
                }
                menu.popUp(positioning: nil, at: NSPoint(x: 20, y: 48), in: self.surface)
            }
            more.contentTintColor = note?.theme.ink; tabs.addArrangedSubview(more)
            more.widthAnchor.constraint(equalToConstant: 26).isActive = true
        }
    }
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
    init() { cache.countLimit = 60; cache.totalCostLimit = 20 * 1024 * 1024 }
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
