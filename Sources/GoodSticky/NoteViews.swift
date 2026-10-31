import AppKit

final class StickyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func performKeyEquivalent(with event: NSEvent) -> Bool { super.performKeyEquivalent(with: event) || KeyCommands.perform(event) }
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

/// The sliver a side note leaves at the screen edge. Hovering or clicking it slides the note
/// out. It is a tiny layer-backed panel: no bitmap beyond its few points of paper.
final class DockTab: NSPanel {
    static let size = NSSize(width: 6, height: 54)
    let tabView = DockTabView(frame: NSRect(origin: .zero, size: DockTab.size))
    init() {
        super.init(contentRect: NSRect(origin: .zero, size: Self.size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isOpaque = false; backgroundColor = .clear; hasShadow = false
        hidesOnDeactivate = false; isReleasedWhenClosed = false; animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        level = .floating
        contentView = tabView
    }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class DockTabView: NSView {
    var paper = NSColor.yellow { didSet { needsDisplay = true } }
    var ink = NSColor.black { didSet { needsDisplay = true } }
    var edge = DockEdge.right { didSet { needsDisplay = true } }
    var onOpen: ((Bool) -> Void)?
    private var tracking: NSTrackingArea?
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true; layerContentsRedrawPolicy = .onSetNeedsDisplay
        setAccessibilityElement(true); setAccessibilityRole(.button)
    }
    required init?(coder: NSCoder) { fatalError() }
    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {
        guard let layer else { return }
        layer.backgroundColor = paper.cgColor
        layer.cornerRadius = 3; layer.cornerCurve = .continuous
        // Only the corners facing the screen are rounded; the other side meets the edge.
        layer.maskedCorners = edge == .right ? [.layerMinXMinYCorner, .layerMinXMaxYCorner] : [.layerMaxXMinYCorner, .layerMaxXMaxYCorner]
        layer.borderColor = ink.withAlphaComponent(0.22).cgColor; layer.borderWidth = 0.5
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(rect: bounds, options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect], owner: self)
        addTrackingArea(tracking!)
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseEntered(with event: NSEvent) { onOpen?(false) }
    override func mouseDown(with event: NSEvent) { onOpen?(true) }
    override func accessibilityPerformPress() -> Bool { onOpen?(true); return true }
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
    var onBegin: (() -> Void)?
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
        onBegin?()
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
final class SwipeTracker {
    enum Result { case swipe, undecided, other }
    var onSwipe: ((Int) -> Void)?
    private var horizontal: Bool?
    private var travel: CGFloat = 0
    private var fired = false
    private var lastDiscrete = Date.distantPast
    static let threshold: CGFloat = 56
    func handle(_ event: NSEvent) -> Result {
        // Physical finger direction, independent of the natural-scrolling setting.
        let dx = event.isDirectionInvertedFromDevice ? event.scrollingDeltaX : -event.scrollingDeltaX
        if !event.hasPreciseScrollingDeltas {
            guard abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY), event.scrollingDeltaX != 0 else { return .other }
            if Date().timeIntervalSince(lastDiscrete) > 0.4 { lastDiscrete = Date(); onSwipe?(dx > 0 ? -1 : 1) }
            return .swipe
        }
        if event.phase.contains(.began) || event.phase.contains(.mayBegin) { horizontal = nil; travel = 0; fired = false }
        let tracking = event.momentumPhase.isEmpty && !event.phase.isEmpty
        if tracking && horizontal == nil {
            let x = abs(event.scrollingDeltaX), y = abs(event.scrollingDeltaY)
            if x + y > 0.5 { horizontal = x > y * 1.3 }
        }
        guard let horizontal else { return tracking ? .undecided : .other }
        guard horizontal else { return .other }
        // Horizontal gestures, including their momentum tail, never reach the text.
        if event.momentumPhase.isEmpty {
            travel += dx
            if !fired && abs(travel) >= Self.threshold { fired = true; onSwipe?(travel > 0 ? -1 : 1) }
        }
        if event.momentumPhase.contains(.ended) || event.momentumPhase.contains(.cancelled) || (event.momentumPhase.isEmpty && event.phase.contains(.cancelled)) { self.horizontal = nil }
        return .swipe
    }
}

final class NoteScrollView: NSScrollView {
    var canSwipe: () -> Bool = { false }
    let swipe = SwipeTracker()
    var onSwipe: ((Int) -> Void)? { get { swipe.onSwipe } set { swipe.onSwipe = newValue } }
    override func scrollWheel(with event: NSEvent) {
        if canSwipe(), swipe.handle(event) == .swipe { return }
        super.scrollWheel(with: event)
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

