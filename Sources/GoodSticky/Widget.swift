import AppKit
import ImageIO
import UniformTypeIdentifiers

final class StickyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// The paper is drawn entirely with layer properties, so a note owns no full-size bitmap.
/// Notes are flush and matte: no window shadow and no border. A ring appears only as
/// transient feedback while files or another note are dragged onto this one.
final class WidgetSurface: NSView {
    var theme = NoteTheme.all[0] { didSet { needsDisplay = true } }
    var paperOpacity: CGFloat = 1 { didSet { needsDisplay = true } }
    var stackTarget = false { didSet { if oldValue != stackTarget { needsDisplay = true } } }
    var onSwipe: ((Int) -> Void)?
    var onHover: ((Bool) -> Void)?
    var onDrop: (([URL]) -> Void)?
    var onLayout: (() -> Void)?
    override func layout() { super.layout(); onLayout?() }
    private var tracking: NSTrackingArea?
    private var dropping = false
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        registerForDraggedTypes([.fileURL])
    }
    required init?(coder: NSCoder) { fatalError() }
    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {
        guard let layer else { return }
        layer.cornerRadius = 8; layer.cornerCurve = .continuous
        layer.backgroundColor = theme.paper.withAlphaComponent(paperOpacity).cgColor
        let ring = dropping || stackTarget
        layer.borderColor = ring ? theme.ink.withAlphaComponent(0.55).cgColor : nil
        layer.borderWidth = ring ? 2 : 0
    }
    override func swipe(with event: NSEvent) {
        // Three-finger "swipe between pages" delivers discrete swipe events.
        if event.deltaX != 0 { onSwipe?(event.deltaX > 0 ? -1 : 1) } else { super.swipe(with: event) }
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(rect: bounds, options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect], owner: self)
        addTrackingArea(tracking!)
    }
    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }
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

/// Small vector marks rendered by the window server instead of per-view bitmaps.
class ShapeMarkView: NSView {
    let shape = CAShapeLayer()
    var tint = NSColor.gray { didSet { applyTint() } }
    var tintAlpha: CGFloat = 0.35 { didSet { applyTint() } }
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.addSublayer(shape)
        shape.lineCap = .round
        applyTint()
    }
    required init?(coder: NSCoder) { fatalError() }
    func applyTint() {
        shape.fillColor = filled ? tint.withAlphaComponent(tintAlpha).cgColor : nil
        shape.strokeColor = filled ? nil : tint.withAlphaComponent(tintAlpha).cgColor
    }
    var filled: Bool { true }
    func path(in bounds: CGRect) -> CGPath { CGMutablePath() }
    override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        shape.frame = bounds; shape.path = path(in: bounds)
        CATransaction.commit()
    }
    override func setFrameSize(_ newSize: NSSize) { super.setFrameSize(newSize); needsLayout = true }
}

final class DragHandle: ShapeMarkView {
    override func path(in bounds: CGRect) -> CGPath {
        let path = CGMutablePath()
        for index in 0..<3 { path.addEllipse(in: CGRect(x: 10 + CGFloat(index) * 3.5, y: 12, width: 2, height: 2)) }
        return path
    }
    /// Screen-space cursor location while moving, and when released.
    var onMove: ((NSPoint) -> Void)?
    var onRelease: ((NSPoint) -> Void)?
    private var start: NSPoint?
    private var origin = NSPoint.zero
    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        start = NSEvent.mouseLocation; origin = window.frame.origin
        NSCursor.closedHand.push()
    }
    override func mouseDragged(with event: NSEvent) {
        guard let window, let start else { return }
        let mouse = NSEvent.mouseLocation
        window.setFrameOrigin(NSPoint(x: (origin.x + mouse.x - start.x).rounded(), y: (origin.y + mouse.y - start.y).rounded()))
        onMove?(mouse)
    }
    override func mouseUp(with event: NSEvent) {
        guard start != nil else { return }
        start = nil; NSCursor.pop()
        onRelease?(NSEvent.mouseLocation)
    }
}

/// iPhone-style page dots for a stack, drawn inside the paper. One shape layer per state.
final class PageDots: NSView {
    var count = 0 { didSet { if oldValue != count { rebuild() } } }
    var current = 0 { didSet { if oldValue != current { rebuild() } } }
    var tint = NSColor.gray { didSet { rebuild() } }
    var titles: [String] = [] { didSet { rebuild() } }
    var onSelect: ((Int) -> Void)?
    private let inactive = CAShapeLayer(), active = CAShapeLayer()
    private(set) var range = 0..<0
    static let diameter: CGFloat = 6, pitch: CGFloat = 12
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true; layer?.addSublayer(inactive); layer?.addSublayer(active)
        setAccessibilityElement(true); setAccessibilityRole(.tabGroup)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func setFrameSize(_ newSize: NSSize) { super.setFrameSize(newSize); rebuild() }
    /// Index range that fits, centered on the current note when a stack is very large.
    private func visibleRange() -> Range<Int> {
        let capacity = max(1, Int(bounds.width / Self.pitch))
        guard count > capacity else { return 0..<count }
        let first = min(max(0, current - capacity / 2), count - capacity)
        return first..<(first + capacity)
    }
    private func originX(_ slot: Int) -> CGFloat {
        let used = CGFloat(range.count) * Self.pitch
        return (bounds.width - used) / 2 + CGFloat(slot) * Self.pitch
    }
    func rebuild() {
        range = visibleRange()
        let rest = CGMutablePath(), on = CGMutablePath()
        for (slot, index) in range.enumerated() {
            // Edge dots shrink when the stack continues beyond the visible window.
            let edge = (slot == 0 && range.lowerBound > 0) || (slot == range.count - 1 && range.upperBound < count)
            let d = edge ? Self.diameter - 2 : Self.diameter
            let rect = CGRect(x: originX(slot) + (Self.pitch - d) / 2, y: (bounds.height - d) / 2, width: d, height: d)
            (index == current ? on : rest).addEllipse(in: rect)
        }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        inactive.frame = bounds; active.frame = bounds
        inactive.path = rest; active.path = on
        inactive.fillColor = tint.withAlphaComponent(0.28).cgColor
        active.fillColor = tint.withAlphaComponent(0.8).cgColor
        CATransaction.commit()
        let title = titles.indices.contains(current) ? titles[current] : ""
        setAccessibilityLabel("Stacked notes"); setAccessibilityValue("Note \(current + 1) of \(count)\(title.isEmpty ? "" : ", " + title)")
        toolTip = count > 1 ? "Note \(current + 1) of \(count) · swipe or ⌃Tab to switch" : nil
    }
    func index(at point: NSPoint) -> Int? {
        let slot = Int(floor((point.x - originX(0)) / Self.pitch))
        guard slot >= 0, slot < range.count else { return nil }
        return range.lowerBound + slot
    }
    override func mouseDown(with event: NSEvent) {
        if let index = index(at: convert(event.locationInWindow, from: nil)) { onSelect?(index) }
    }
    override func accessibilityPerformIncrement() -> Bool { onSelect?((current + 1) % max(1, count)); return true }
    override func accessibilityPerformDecrement() -> Bool { onSelect?((current - 1 + count) % max(1, count)); return true }
}

/// Turns a horizontal two-finger trackpad swipe (or a horizontal wheel flick) into one
/// switch per gesture, like back/forward in a browser. Vertical scrolling is untouched.
final class NoteScrollView: NSScrollView {
    var canSwipe: () -> Bool = { false }
    var onSwipe: ((Int) -> Void)?
    private var horizontal: Bool?
    private var travel: CGFloat = 0
    private var fired = false
    private var lastDiscrete = Date.distantPast
    static let threshold: CGFloat = 56
    override func scrollWheel(with event: NSEvent) {
        guard canSwipe() else { super.scrollWheel(with: event); return }
        // Physical finger direction, independent of the natural-scrolling setting.
        let dx = event.isDirectionInvertedFromDevice ? event.scrollingDeltaX : -event.scrollingDeltaX
        if !event.hasPreciseScrollingDeltas {
            guard abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY), event.scrollingDeltaX != 0 else { super.scrollWheel(with: event); return }
            if Date().timeIntervalSince(lastDiscrete) > 0.4 { lastDiscrete = Date(); onSwipe?(dx > 0 ? -1 : 1) }
            return
        }
        if event.phase.contains(.began) || event.phase.contains(.mayBegin) { horizontal = nil; travel = 0; fired = false }
        if event.momentumPhase.isEmpty && !event.phase.isEmpty && horizontal == nil {
            let x = abs(event.scrollingDeltaX), y = abs(event.scrollingDeltaY)
            if x + y > 0.5 { horizontal = x > y * 1.3 }
        }
        guard horizontal == true else { super.scrollWheel(with: event); return }
        // Horizontal gestures, including their momentum tail, never reach the text view.
        if event.momentumPhase.isEmpty {
            travel += dx
            if !fired && abs(travel) >= Self.threshold { fired = true; onSwipe?(travel > 0 ? -1 : 1) }
        }
        if event.momentumPhase.contains(.ended) || event.momentumPhase.contains(.cancelled) || (event.momentumPhase.isEmpty && (event.phase.contains(.cancelled))) { horizontal = nil }
    }
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

final class ResizeGrip: ShapeMarkView {
    override var filled: Bool { false }
    override func path(in bounds: CGRect) -> CGPath {
        let path = CGMutablePath()
        for offset in [4.0, 8.0] {
            path.move(to: CGPoint(x: bounds.width - offset - 2, y: 3))
            path.addLine(to: CGPoint(x: bounds.width - 3, y: offset + 2))
        }
        return path
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func accessibilityValue() -> Any? { guard let frame = window?.frame else { return nil }; return "\(Int(frame.width)) × \(Int(frame.height))" }
    override var acceptsFirstResponder: Bool { true }
    private var dragFrame: NSRect?
    private var dragStart = NSPoint.zero
    override init(frame: NSRect) {
        super.init(frame: frame); toolTip = "Resize note"; tintAlpha = 0.55; shape.lineWidth = 1
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
    let scroll = NoteScrollView()
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
        handle.onMove = { [weak self] point in self?.trackStackTarget(at: point) }
        handle.onRelease = { [weak self] point in self?.finishMove(at: point) }
        scroll.drawsBackground = false; scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        textView.allowsUndo = true; textView.isRichText = false; textView.drawsBackground = false
        textView.font = .systemFont(ofSize: 13)
        textView.textContainerInset = NSSize(width: 0, height: 1)
        textView.isVerticallyResizable = true; textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]; textView.textContainer?.widthTracksTextView = true
        textView.isAutomaticSpellingCorrectionEnabled = false; textView.delegate = self
        // Text checking services load lazily, only while a note is being edited.
        setEditingServices(false)
        textView.onFiles = { [weak self] in self?.addFiles($0) }
        textView.onCycle = { [weak self] direction in self?.cycle(direction) }
        scroll.canSwipe = { [weak self] in (self?.ids.count ?? 0) > 1 }
        scroll.onSwipe = { [weak self] direction in self?.cycle(direction) }
        surface.onSwipe = { [weak self] direction in self?.cycle(direction) }
        dots.onSelect = { [weak self] index in
            guard let self, self.ids.indices.contains(index) else { return }
            self.select(self.ids[index])
        }
        scroll.documentView = textView; surface.addSubview(scroll)
        surface.addSubview(attachments); surface.addSubview(dots); surface.addSubview(grip)
        surface.onHover = { [weak self] hovering in
            guard let self else { return }
            self.hovering = hovering; self.updateControlsVisibility()
        }
        surface.onDrop = { [weak self] in self?.addFiles($0) }
        surface.onLayout = { [weak self] in self?.layoutNote() }
    }
    @discardableResult func ensureControls() -> FrameStack {
        if let controls { return controls }
        let copy = ActionButton("Copy note", symbol: "doc.on.doc") { [weak self] in
            guard let self, let note = self.note else { return }
            NSPasteboard.general.clearContents(); NSPasteboard.general.setString(note.text, forType: .string)
            self.copyButton?.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: "Copied")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                self?.copyButton?.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: "Copy note")
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
        guard textView.isContinuousSpellCheckingEnabled != editing else { return }
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
    func trackStackTarget(at point: NSPoint) {
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
        textView.textColor = note.theme.ink; textView.insertionPointColor = note.theme.ink
        if textView.string != note.text { textView.string = note.text }
        let paragraph = NSMutableParagraphStyle(); paragraph.lineSpacing = 2
        textView.defaultParagraphStyle = paragraph
        textView.typingAttributes = [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: note.theme.ink, .paragraphStyle: paragraph]
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
        scroll.frame = NSRect(x: 10, y: bottom, width: max(0, width - 20), height: max(20, height - 28 - bottom))
    }
    override func close() { importSpinner?.stopAnimation(nil); appearancePopover?.close(); super.close() }
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
        if focus {
            transientFront = true; window?.level = .floating
            window?.makeKeyAndOrderFront(nil); window?.makeFirstResponder(textView)
        } else { window?.orderFrontRegardless() }
    }
    func bringForward() { groupRaised = true; transientFront = false; window?.level = .floating; window?.orderFrontRegardless() }
    func returnToDesktop() { groupRaised = false; transientFront = false; setLevel() }
    func windowDidResignKey(_ notification: Notification) {
        transientFront = false; if !groupRaised && appearancePopover?.isShown != true && window?.attachedSheet == nil { setLevel() }
        setEditingServices(false); updateControlsVisibility()
        if AppDelegate.shared.library?.window?.isVisible == true { AppDelegate.shared.library?.refresh() }
    }
    func windowDidBecomeKey(_ notification: Notification) { setEditingServices(true); updateControlsVisibility() }
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
                    button.image = NSImage(systemSymbolName: "paperclip", accessibilityDescription: "Attachments"); button.isEnabled = true
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
            ThumbnailLoader.shared.load(store.attachmentURL(picture), pixels: 440) { [weak self, weak preview] image in
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
final class FrameStack: NSView {
    enum Axis { case horizontal, vertical }
    var axis: Axis = .horizontal
    var spacing: CGFloat = 0
    private var lengths: [ObjectIdentifier: CGFloat] = [:]
    var arrangedSubviews: [NSView] { subviews }
    convenience init(_ axis: Axis, spacing: CGFloat = 0) { self.init(frame: .zero); self.axis = axis; self.spacing = spacing }
    override var isFlipped: Bool { true }
    func addArrangedSubview(_ view: NSView, length: CGFloat = 0) {
        lengths[ObjectIdentifier(view)] = length; addSubview(view); needsLayout = true
    }
    func removeAllArrangedSubviews() { subviews.forEach { $0.removeFromSuperview() }; lengths.removeAll() }
    override func layout() {
        super.layout()
        let total = axis == .horizontal ? bounds.width : bounds.height
        let fixed = subviews.reduce(0) { $0 + (lengths[ObjectIdentifier($1)] ?? 0) } + spacing * CGFloat(max(0, subviews.count - 1))
        let flexibleCount = subviews.filter { (lengths[ObjectIdentifier($0)] ?? 0) == 0 }.count
        let flexible = flexibleCount > 0 ? max(0, total - fixed) / CGFloat(flexibleCount) : 0
        var cursor: CGFloat = 0
        for view in subviews {
            let fixedLength = lengths[ObjectIdentifier(view)] ?? 0
            let length = fixedLength > 0 ? fixedLength : flexible
            view.frame = axis == .horizontal ? NSRect(x: cursor, y: 0, width: length, height: bounds.height) : NSRect(x: 0, y: cursor, width: bounds.width, height: length)
            cursor += length + spacing
        }
    }
    override func setFrameSize(_ newSize: NSSize) { super.setFrameSize(newSize); needsLayout = true }
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
    private let failures = NSCache<NSString, NSNumber>()
    private let queue = DispatchQueue(label: "app.goodsticky.thumbnails", qos: .utility)
    private let lock = NSLock()
    private var pending: [NSString: [(NSImage?) -> Void]] = [:]
    init() { cache.countLimit = 24; cache.totalCostLimit = 4 * 1024 * 1024; failures.countLimit = 24 }
    func load(_ url: URL, pixels: Int, completion: @escaping (NSImage?) -> Void) {
        let key = (url.path + "-" + String(pixels)) as NSString
        lock.lock()
        if let image = cache.object(forKey: key) {
            lock.unlock(); DispatchQueue.main.async { completion(image) }; return
        }
        if failures.object(forKey: key) != nil { lock.unlock(); DispatchQueue.main.async { completion(nil) }; return }
        if pending[key] != nil { pending[key]?.append(completion); lock.unlock(); return }
        pending[key] = [completion]; lock.unlock()
        queue.async { [weak self] in
            guard let self else { return }
            var result: NSImage?
            if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
               let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: pixels, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) {
                result = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
                self.cache.setObject(result!, forKey: key, cost: cg.bytesPerRow * cg.height)
            } else { self.failures.setObject(true, forKey: key) }
            self.lock.lock(); let callbacks = self.pending.removeValue(forKey: key) ?? []; self.lock.unlock()
            DispatchQueue.main.async { for callback in callbacks { callback(result) } }
        }
    }
}
