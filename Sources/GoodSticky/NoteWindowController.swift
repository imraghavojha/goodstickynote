import AppKit
import UniformTypeIdentifiers

final class WidgetController: NSWindowController, NSWindowDelegate, NSTextViewDelegate, NSPopoverDelegate {
    let store = NoteStore.shared
    var ids: [UUID]
    var activeID: UUID {
        willSet { if newValue != activeID { saveEditorSelection() } }
        didSet { if oldValue != activeID { textView?.history = store.history(for: activeID) } }
    }
    let surface = WidgetSurface(frame: .zero)
    let display = NoteTextDisplay(frame: .zero)
    /// The editor exists only while a note is being edited, scrolled or recently used.
    private(set) var textView: NoteTextView?
    private(set) var scroll: NoteScrollView?
    private var endEditingWork: DispatchWorkItem?
    /// Seconds an unfocused editor lingers before reverting to the display.
    static var editorLinger: TimeInterval = 20
    let handle = DragHandle()
    /// Hover controls are built on first hover/focus; most desktop notes never need them.
    private(set) var controls: FrameStack?
    private var copyButton: ActionButton?
    private var attachButton: ActionButton?
    private var importSpinner: NSProgressIndicator?
    private var hovering = false
    let attachments = FrameStack(.vertical, spacing: 4)
    let dots = PageDots(frame: .zero)
    let grip = ResizeGrip(frame: .zero)
    private var appearancePopover: NSPopover?
    private var attachmentKey = ""
    private var failedPreviewIDs = Set<UUID>()
    private var importsInProgress = 0
    private weak var stackTarget: WidgetController?
    private var moving = false
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
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false
        // Let the render server animate note fades without a per-frame app callback.
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.minSize = NSSize(width: 140, height: 96)
        panel.contentView = surface
        setup()
        if let note {
            let saved = NSRect(x: note.x, y: note.y, width: max(140, note.width), height: max(96, note.height))
            let visible = (NSScreen.screens.first { $0.visibleFrame.intersects(saved) } ?? NSScreen.main)?.visibleFrame ?? saved
            let width = min(saved.width, visible.width), height = min(saved.height, visible.height)
            panel.setFrame(NSRect(x: min(max(saved.minX, visible.minX), visible.maxX - width), y: min(max(saved.minY, visible.minY), visible.maxY - height), width: width, height: height), display: false)
        }
        configuring = false
        refresh()
    }
    required init?(coder: NSCoder) { fatalError() }
    func setup() {
        surface.addSubview(handle); handle.toolTip = "Drag to move · drop on another note to stack"
        handle.onMove = { [weak self] point in self?.moving = true; self?.trackStackTarget(at: point) }
        handle.onRelease = { [weak self] point in
            // A drag saves its final position once, not on every mouse event.
            self?.moving = false; self?.saveFrame(); self?.finishMove(at: point)
        }
        display.onActivate = { [weak self] event in self?.activate(with: event) }
        display.onScroll = { [weak self] events in self?.scrollIdle(events) }
        display.canSwipe = { [weak self] in (self?.ids.count ?? 0) > 1 }
        display.swipe.onSwipe = { [weak self] direction in self?.cycle(direction) }
        surface.onSwipe = { [weak self] direction in self?.cycle(direction) }
        dots.onSelect = { [weak self] index in
            guard let self, self.ids.indices.contains(index) else { return }
            self.select(self.ids[index])
        }
        surface.addSubview(display)
        surface.addSubview(attachments); surface.addSubview(dots); surface.addSubview(grip)
        surface.onHover = { [weak self] hovering in
            guard let self else { return }
            self.hovering = hovering; self.updateControlsVisibility(); self.scheduleEndEditing()
        }
        surface.onDrop = { [weak self] in self?.addFiles($0) }
        surface.onLayout = { [weak self] in self?.layoutNote() }
    }
    /// A click, scroll or focus on the idle display. Plain vertical scrolling of text that
    /// fits needs no editor, so it is ignored, exactly as an editor would ignore it.
    func activate(with event: NSEvent?) { beginEditing(event) }
    /// Vertical scrolling of an idle note: only text that overflows needs the editor.
    func scrollIdle(_ events: [NSEvent]) {
        guard display.overflows || display.offset > 0, let first = events.first else { return }
        beginEditing(first)
        for event in events.dropFirst() { scroll?.scrollWheel(with: event) }
    }
    /// Creates the editor over the display and forwards the triggering event to it, so the
    /// caret, selection drag or scroll happens exactly where the user acted.
    @discardableResult func beginEditing(_ event: NSEvent? = nil) -> NoteTextView {
        endEditingWork?.cancel(); endEditingWork = nil
        let textView: NoteTextView, scroll: NoteScrollView
        if let existing = self.textView, let existingScroll = self.scroll { textView = existing; scroll = existingScroll }
        else {
            scroll = NoteScrollView(frame: display.frame)
            scroll.drawsBackground = false; scroll.borderType = .noBorder
            scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
            textView = NoteTextView(frame: NSRect(origin: .zero, size: scroll.contentSize))
            textView.allowsUndo = false; textView.history = store.history(for: activeID); textView.isRichText = false; textView.drawsBackground = false
            textView.font = NoteText.font
            textView.textContainerInset = NSSize(width: 0, height: NoteText.inset)
            textView.isVerticallyResizable = true; textView.isHorizontallyResizable = false
            textView.autoresizingMask = [.width]; textView.textContainer?.widthTracksTextView = true
            textView.isAutomaticSpellingCorrectionEnabled = false
            textView.isContinuousSpellCheckingEnabled = false
            textView.onFiles = { [weak self] in self?.addFiles($0) }
            textView.onCycle = { [weak self] direction in self?.cycle(direction) }
            scroll.canSwipe = { [weak self] in (self?.ids.count ?? 0) > 1 }
            scroll.onSwipe = { [weak self] direction in self?.cycle(direction) }
            scroll.documentView = textView
            self.textView = textView; self.scroll = scroll
            loadEditor()
            textView.delegate = self
            surface.addSubview(scroll, positioned: .above, relativeTo: display)
            scroll.layoutSubtreeIfNeeded()
            if display.offset > 0 { scroll.contentView.scroll(to: NSPoint(x: 0, y: display.offset)); scroll.reflectScrolledClipView(scroll.contentView) }
            display.isHidden = true
            setEditingServices(window?.isKeyWindow == true)
        }
        switch event?.type {
        case .leftMouseDown?, .rightMouseDown?:
            window?.makeFirstResponder(textView); textView.mouseDown(with: event!)
        case .scrollWheel?:
            scroll.scrollWheel(with: event!); scheduleEndEditing()
        default:
            if window?.isKeyWindow == true { window?.makeFirstResponder(textView) }
        }
        return textView
    }
    private func saveEditorSelection() {
        guard let textView else { return }
        textView.history?.selection = textView.selectedRange()
        textView.history?.breakCoalescing()
    }
    /// Copies the active note into the editor with the shared style.
    private func loadEditor() {
        guard let textView, let note else { return }
        textView.textColor = note.theme.ink; textView.insertionPointColor = note.theme.ink
        textView.defaultParagraphStyle = NoteText.paragraph
        textView.typingAttributes = NoteText.attributes(note.theme.ink)
        if textView.string != note.text || textView.textStorage?.length == 0 {
            textView.textStorage?.setAttributedString(NSAttributedString(string: note.text, attributes: NoteText.attributes(note.theme.ink)))
            textView.restoreSelection()
        } else {
            textView.textStorage?.setAttributes(NoteText.attributes(note.theme.ink), range: NSRange(location: 0, length: textView.textStorage?.length ?? 0))
        }
    }
    /// Unfocused, unhovered editors return to the display after a short linger.
    func scheduleEndEditing() {
        endEditingWork?.cancel(); endEditingWork = nil
        guard textView != nil, window?.isKeyWindow != true, !hovering else { return }
        let work = DispatchWorkItem { [weak self] in self?.endEditing() }
        endEditingWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.editorLinger, execute: work)
    }
    func endEditing() {
        endEditingWork?.cancel(); endEditingWork = nil
        guard let textView, let scroll, window?.isKeyWindow != true, window?.attachedSheet == nil else { return }
        display.offset = max(0, scroll.contentView.bounds.origin.y)
        display.text = textView.string
        saveEditorSelection()
        if window?.firstResponder === textView { window?.makeFirstResponder(nil) }
        textView.delegate = nil
        scroll.removeFromSuperview()
        scroll.documentView = nil
        self.textView = nil; self.scroll = nil
        display.isHidden = false
    }
    @discardableResult func ensureControls() -> FrameStack {
        if let controls { return controls }
        let copy = ActionButton("Copy note", symbol: "doc.on.doc") { [weak self] in
            guard let self, let note = self.note else { return }
            NSPasteboard.general.clearContents(); NSPasteboard.general.setString(note.text, forType: .string)
            self.copyButton?.image = sharedSymbol("checkmark")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                self?.copyButton?.image = sharedSymbol("doc.on.doc")
            }
        }
        let hide = ActionButton("Hide note", symbol: "minus") { [weak self] in
            guard let self else { return }; self.store.update(self.activeID) { $0.hidden = true }
        }
        let attach = ActionButton("Attach files", symbol: "paperclip") { [weak self] in self?.showAttachments() }
        let appearance = ActionButton("Appearance", symbol: "paintpalette") { [weak self] in self?.showAppearance() }
        let menu = ActionButton("Note options", symbol: "ellipsis") { [weak self] in self?.showMenu() }
        let stack = FrameStack(.horizontal); stack.isHidden = true
        for button in [copy, hide, attach, appearance, menu] { stack.addArrangedSubview(button, length: 21) }
        copyButton = copy; attachButton = attach; controls = stack
        surface.addSubview(stack)
        styleControls(); layoutNote()
        return stack
    }
    func styleControls() {
        guard let controls, let note else { return }
        for case let button as NSButton in controls.arrangedSubviews { button.contentTintColor = note.theme.ink }
        if let attachButton, importsInProgress == 0 {
            attachButton.toolTip = note.attachments.isEmpty ? "Attach files" : "\(note.attachments.count) \(note.attachments.count == 1 ? "attachment" : "attachments")"
            attachButton.setAccessibilityLabel(attachButton.toolTip)
        }
    }
    func updateControlsVisibility() {
        let visible = hovering || window?.isKeyWindow == true || importsInProgress > 0
        if visible { ensureControls() }
        controls?.isHidden = !visible
    }
    func setEditingServices(_ editing: Bool) {
        // Idle desktop notes skip spelling markers, so the spell checker never loads until someone edits.
        guard let textView, textView.isContinuousSpellCheckingEnabled != editing else { return }
        textView.isContinuousSpellCheckingEnabled = editing
    }
    /// Switches the visible note in a stack, sliding in the direction of travel.
    func select(_ id: UUID, direction: Int? = nil) {
        guard id != activeID, let from = ids.firstIndex(of: activeID), let to = ids.firstIndex(of: id) else { return }
        let transition = CATransition()
        transition.type = .push; transition.duration = 0.18
        transition.subtype = (direction ?? (to > from ? 1 : -1)) > 0 ? .fromRight : .fromLeft
        transition.timingFunction = CAMediaTimingFunction(name: .easeOut)
        surface.layer?.add(transition, forKey: "switch")
        activeID = id; refresh()
    }
    func cycle(_ direction: Int) {
        guard ids.count > 1, let index = ids.firstIndex(of: activeID) else { return }
        select(ids[(index + direction + ids.count) % ids.count], direction: direction)
    }
    func refreshDots() {
        dots.count = ids.count
        dots.current = ids.firstIndex(of: activeID) ?? 0
        dots.titles = ids.map { store.note($0)?.title ?? "Untitled note" }
    }
    /// The note directly beneath the cursor (under the one being dragged), as WindowServer
    /// orders windows. A note covered by another app's window is never a target.
    func stackCandidate(at point: NSPoint) -> WidgetController? {
        guard let window else { return nil }
        var number = NSWindow.windowNumber(at: point, belowWindowWithWindowNumber: 0)
        if number == window.windowNumber { number = NSWindow.windowNumber(at: point, belowWindowWithWindowNumber: number) }
        return AppDelegate.shared.widgets.values.first { $0 !== self && $0.window?.windowNumber == number && $0.window?.isVisible == true }
    }
    private var lastProbe = (point: NSPoint(x: -1e6, y: -1e6), time: 0.0)
    func trackStackTarget(at point: NSPoint) {
        // Hit-testing asks WindowServer; during a drag, probe again only after a real move.
        let now = ProcessInfo.processInfo.systemUptime
        guard hypot(point.x - lastProbe.point.x, point.y - lastProbe.point.y) >= 6 || now - lastProbe.time >= 0.05 else { return }
        lastProbe = (point, now)
        let candidate = stackCandidate(at: point)
        guard candidate !== stackTarget else { return }
        stackTarget?.surface.stackTarget = false
        candidate?.surface.stackTarget = true
        stackTarget = candidate
    }
    func finishMove(at point: NSPoint) {
        let target = stackCandidate(at: point)
        stackTarget?.surface.stackTarget = false; stackTarget = nil
        guard let target else { return }
        AppDelegate.shared.stack(activeID, with: target.activeID)
    }
    func refresh(using supplied: StickyNote? = nil) {
        guard let note = supplied ?? self.note, note != lastRenderedNote else { return }
        lastRenderedNote = note; configuring = true
        window?.title = note.title
        surface.theme = note.theme; surface.paperOpacity = note.opacity
        if display.text != note.text { display.text = note.text; display.offset = 0 }
        display.color = note.theme.ink
        loadEditor()
        handle.tint = note.theme.ink
        grip.tint = note.theme.ink
        if dots.tint != note.theme.ink { dots.tint = note.theme.ink }
        styleControls()
        refreshDots()
        if note.pinned { window?.level = .floating }
        else if !transientFront && !groupRaised && window?.isKeyWindow != true && appearancePopover?.isShown != true && window?.attachedSheet == nil { setLevel() }
        failedPreviewIDs.formIntersection(Set(note.attachments.map(\.id)))
        configuring = false; layoutNote()
    }
    func layoutNote() {
        guard !layingOut, let note else { return }
        layingOut = true; defer { layingOut = false }
        let width = surface.bounds.width, height = surface.bounds.height
        guard width > 0, height > 0 else { return }
        handle.frame = NSRect(x: 0, y: height - 27, width: max(24, width - 112), height: 27)
        controls?.frame = NSRect(x: width - 111, y: height - 25, width: 105, height: 22)
        grip.frame = NSRect(x: width - 17, y: 0, width: 17, height: 17)
        let stacked = ids.count > 1
        var bottom: CGFloat = 9
        dots.isHidden = !stacked
        // Dots sit centered inside the paper's bottom edge, clear of the resize grip.
        dots.frame = NSRect(x: 22, y: 3, width: max(0, width - 44), height: 14)
        if stacked { bottom = 19 }
        let budget = max(0, height - 28 - bottom - 48)
        let hasPreview = note.attachments.contains { !failedPreviewIDs.contains($0.id) && UTType(filenameExtension: URL(fileURLWithPath: $0.name).pathExtension)?.conforms(to: .image) == true }
        let previewHeight: CGFloat = !hasPreview ? 0 : height >= 240 && budget >= 94 ? 64 : height >= 180 && budget >= 70 ? 40 : 0
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
        display.frame = NSRect(x: 10, y: bottom, width: max(0, width - 20), height: max(20, height - 28 - bottom))
        scroll?.frame = display.frame
    }
    override func close() { importSpinner?.stopAnimation(nil); appearancePopover?.close(); endEditingWork?.cancel(); super.close() }
    func updateMembers(_ members: [UUID]) {
        let sameEditor = members.contains(activeID)
        ids = members
        if !sameEditor { activeID = members[0]; lastRenderedNote = nil }
        refreshDots()
        if let note, let frame = window?.frame {
            let desired = NSRect(x: note.x, y: note.y, width: note.width, height: note.height)
            if frame != desired { configuring = true; window?.setFrame(desired, display: true); configuring = false }
        }
        refresh(); layoutNote()
    }
    func setLevel() {
        guard let note else { return }
        window?.level = note.pinned ? .floating : NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
    }
    func show(focus: Bool = false) {
        if window?.isVisible != true { fade(in: true) }
        if focus {
            transientFront = true; window?.level = .floating
            window?.makeKeyAndOrderFront(nil); window?.makeFirstResponder(beginEditing())
        } else { window?.orderFrontRegardless() }
    }
    static let fadeDuration: CFTimeInterval = 0.2
    /// Appear/disappear fade, committed once and interpolated by the render server: the app
    /// does no per-frame work, unlike AppKit's NSAnimation-driven window fade.
    private func fade(in appearing: Bool, completion: (() -> Void)? = nil) {
        guard let layer = surface.layer else { completion?(); return }
        CATransaction.begin()
        CATransaction.setCompletionBlock(completion)
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = appearing ? 0 : (layer.presentation()?.opacity ?? 1)
        animation.toValue = appearing ? 1 : 0
        animation.duration = appearing ? Self.fadeDuration : Self.fadeDuration * 0.75
        animation.timingFunction = CAMediaTimingFunction(name: appearing ? .easeOut : .easeIn)
        animation.isRemovedOnCompletion = appearing
        animation.fillMode = .forwards
        layer.add(animation, forKey: "visibility")
        CATransaction.commit()
    }
    /// Fades the note out, then closes it. Used when a note is hidden, deleted or merged.
    func dismiss() {
        guard window?.isVisible == true else { close(); return }
        endEditingWork?.cancel()
        fade(in: false) { [self] in
            close()
            surface.layer?.removeAnimation(forKey: "visibility")
        }
    }
    func bringForward() { groupRaised = true; transientFront = false; window?.level = .floating; window?.orderFrontRegardless() }
    func returnToDesktop() { groupRaised = false; transientFront = false; setLevel() }
    func windowDidResignKey(_ notification: Notification) {
        transientFront = false; if !groupRaised && appearancePopover?.isShown != true && window?.attachedSheet == nil { setLevel() }
        setEditingServices(false); updateControlsVisibility(); scheduleEndEditing()
        if AppDelegate.shared.library?.window?.isVisible == true { AppDelegate.shared.library?.refresh() }
    }
    func windowDidBecomeKey(_ notification: Notification) { endEditingWork?.cancel(); setEditingServices(true); updateControlsVisibility() }
    func windowDidMove(_ notification: Notification) { if !moving { saveFrame() } }
    func windowDidResize(_ notification: Notification) { layoutNote(); saveFrame() }
    func saveFrame() {
        guard !configuring, let frame = window?.frame, let note else { return }
        guard note.x != frame.minX || note.y != frame.minY || note.width != frame.width || note.height != frame.height else { return }
        store.updateMany(ids, notify: false) { $0.x = frame.minX; $0.y = frame.minY; $0.width = frame.width; $0.height = frame.height }
    }
    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? {
        store.undoManager(for: activeID)
    }
    @objc func undo(_ sender: Any?) { store.history(for: activeID).undo() }
    @objc func redo(_ sender: Any?) { store.history(for: activeID).redo() }
    func textDidChange(_ notification: Notification) {
        guard let textView else { return }
        store.update(activeID, notify: false) { $0.text = textView.string }
        let title = note?.title ?? "Untitled note"
        if window?.title != title { window?.title = title }
    }
    func addFiles(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        importsInProgress += 1; ensureControls(); updateControlsVisibility()
        if let button = attachButton {
            if importSpinner == nil {
                let spinner = NSProgressIndicator(frame: NSRect(x: 3, y: 4, width: 15, height: 15))
                spinner.style = .spinning; spinner.controlSize = .small; spinner.isDisplayedWhenStopped = false
                spinner.setAccessibilityLabel("Importing files"); button.addSubview(spinner); importSpinner = spinner
            }
            button.image = nil; button.isEnabled = false; button.toolTip = "Importing files"
        }
        importSpinner?.isHidden = false; importSpinner?.startAnimation(nil)
        store.attach(urls, to: activeID) { [weak self] in
            guard let self else { return }
            self.importsInProgress -= 1
            if self.importsInProgress == 0 {
                self.importSpinner?.stopAnimation(nil); self.importSpinner?.isHidden = true
                if let button = self.attachButton {
                    button.image = sharedSymbol("paperclip"); button.isEnabled = true
                }
                self.styleControls()
                self.hovering = self.surface.bounds.contains(self.surface.convert(self.window?.mouseLocationOutsideOfEventStream ?? .zero, from: nil))
                self.updateControlsVisibility()
            }
        }
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
        attachments.removeAllArrangedSubviews()
        guard let note else { return }
        if imageHeight > 0, let picture = note.attachments.first(where: { !failedPreviewIDs.contains($0.id) && UTType(filenameExtension: URL(fileURLWithPath: $0.name).pathExtension)?.conforms(to: .image) == true }) {
            let preview = ActionButton("Open " + picture.name) { [weak self] in guard let self else { return }; NSWorkspace.shared.open(self.store.attachmentURL(picture)) }
            preview.title = ""; preview.imageScaling = .scaleProportionallyUpOrDown
            attachments.addArrangedSubview(preview, length: imageHeight)
            let scale = window?.backingScaleFactor ?? 2
            let box = CGSize(width: max(1, surface.bounds.width - 24) * scale, height: imageHeight * scale)
            ThumbnailLoader.shared.load(store.attachmentURL(picture), fitting: box) { [weak self, weak preview] image in
                if let image { preview?.image = image }
                else {
                    self?.failedPreviewIDs.insert(picture.id)
                    self?.attachmentKey = ""
                    DispatchQueue.main.async { [weak self] in self?.layoutNote() }
                }
            }
        }
        for attachment in note.attachments.prefix(rows) {
            let row = FrameStack(.horizontal, spacing: 4)
            let file = ActionButton(attachment.name, symbol: "doc") { [weak self] in guard let self else { return }; NSWorkspace.shared.open(self.store.attachmentURL(attachment)) }
            file.imagePosition = .imageLeading; file.alignment = .left; file.lineBreakMode = .byTruncatingMiddle
            file.font = .systemFont(ofSize: 10); file.contentTintColor = note.theme.ink
            let remove = ActionButton("Remove attachment", symbol: "xmark") { [weak self] in guard let self else { return }; self.store.removeAttachment(attachment, from: self.activeID) }
            remove.contentTintColor = note.theme.ink
            row.addArrangedSubview(file); row.addArrangedSubview(remove, length: 18); attachments.addArrangedSubview(row, length: 22)
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
            let notesMenu = NSMenu()
            for id in ids {
                let choice = ClosureMenuItem(String((store.note(id)?.title ?? "Untitled note").prefix(40))) { [weak self] in self?.select(id) }
                choice.state = id == activeID ? .on : .off; notesMenu.addItem(choice)
            }
            let notesItem = NSMenuItem(title: "Notes in this stack", action: nil, keyEquivalent: ""); notesItem.submenu = notesMenu; menu.addItem(notesItem)
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
        item(note.isBlank ? "Delete note" : "Delete note…") { [weak self] in guard let self else { return }; AppDelegate.shared.confirmDelete(self.activeID) }
        menu.popUp(positioning: nil, at: NSPoint(x: surface.bounds.width - 30, y: surface.bounds.height - 40), in: surface)
    }
}

/// A constraint-free stack. Note windows use only frame layout, so AppKit never spins up
/// an Auto Layout engine per note. Each arranged view keeps its own fixed length; a length
/// of 0 stretches it to fill the remaining space.
