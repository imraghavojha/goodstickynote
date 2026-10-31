import AppKit
/// One text style shared by the idle display and the editor, so swapping them never shifts text.
enum NoteText {
    static let font = NSFont.systemFont(ofSize: 13)
    static let paragraph: NSParagraphStyle = { let style = NSMutableParagraphStyle(); style.lineSpacing = 2; return style }()
    /// NSTextView defaults: 5 pt line-fragment padding; GoodSticky uses a 1 pt top inset.
    static let padding: CGFloat = 5, inset: CGFloat = 1
    static func attributes(_ ink: NSColor) -> [NSAttributedString.Key: Any] { [.font: font, .foregroundColor: ink, .paragraphStyle: paragraph] }
}

/// What an idle note shows instead of a text view: one layer whose bitmap covers only the
/// lines of text, and no text-system objects at all. Clicking, scrolling or focusing it
/// creates the real editor in place (see `WidgetController.beginEditing`).
final class NoteTextDisplay: NSView, CALayerDelegate {
    var text = "" { didSet { if oldValue != text { measured = nil; setAccessibilityValue(text); needsLayout = true; ink.setNeedsDisplay() } } }
    var color = NSColor.black { didSet { if oldValue != color { ink.setNeedsDisplay() } } }
    /// Scroll position carried over from the editor, so ending an edit never jumps.
    var offset: CGFloat = 0 { didSet { if oldValue != offset { needsLayout = true; ink.setNeedsDisplay() } } }
    var onActivate: ((NSEvent?) -> Void)?
    /// Vertical scroll events for the editor, oldest first (a held gesture start included).
    var onScroll: (([NSEvent]) -> Void)?
    var canSwipe: () -> Bool = { false }
    let swipe = SwipeTracker()
    private var heldBegan: NSEvent?
    private let ink = CALayer()
    private var measured: (width: CGFloat, height: CGFloat)?
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        ink.delegate = self; ink.anchorPoint = .zero; ink.needsDisplayOnBoundsChange = true
        ink.actions = ["bounds": NSNull(), "position": NSNull(), "contents": NSNull()]
        layer?.addSublayer(ink)
        setAccessibilityElement(true); setAccessibilityRole(.textArea); setAccessibilityLabel("Note text")
    }
    required init?(coder: NSCoder) { fatalError() }
    private func height(at width: CGFloat) -> CGFloat {
        text.isEmpty ? 0 : ceil(NSAttributedString(string: text, attributes: NoteText.attributes(color)).boundingRect(with: NSSize(width: max(1, width - NoteText.padding * 2), height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin]).height) + NoteText.inset + 2
    }
    /// Width the editor would give the text: with "always show scroll bars", an overflowing
    /// note loses the scroller's width, so the display wraps exactly as the editor will.
    private(set) var textWidth: CGFloat = 0
    /// Height of the laid-out text, cached per text and width.
    var textHeight: CGFloat {
        if let measured, measured.width == bounds.width { return measured.height }
        var width = bounds.width, height = height(at: width)
        if height > bounds.height + 0.5, NSScroller.preferredScrollerStyle == .legacy {
            width -= NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy); height = self.height(at: width)
        }
        textWidth = width; measured = (bounds.width, height); return height
    }
    var overflows: Bool { textHeight > bounds.height + 0.5 }
    override func layout() {
        super.layout()
        // The bitmap is only as tall as the visible text, not the whole note.
        let height = min(bounds.height, max(0, textHeight - offset))
        CATransaction.begin(); CATransaction.setDisableActions(true)
        ink.frame = CGRect(x: 0, y: bounds.height - height, width: bounds.width, height: height)
        ink.contentsScale = window?.backingScaleFactor ?? 2
        CATransaction.commit()
    }
    override func setFrameSize(_ newSize: NSSize) { super.setFrameSize(newSize); needsLayout = true }
    override func viewDidChangeBackingProperties() { super.viewDidChangeBackingProperties(); needsLayout = true; ink.setNeedsDisplay() }
    func draw(_ layer: CALayer, in context: CGContext) {
        guard !text.isEmpty else { return }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        context.translateBy(x: 0, y: layer.bounds.height); context.scaleBy(x: 1, y: -1)
        NSAttributedString(string: text, attributes: NoteText.attributes(color)).draw(
            with: NSRect(x: NoteText.padding, y: NoteText.inset - offset, width: max(1, (textHeight > 0 ? textWidth : bounds.width) - NoteText.padding * 2), height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin])
        NSGraphicsContext.restoreGraphicsState()
    }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .iBeam) }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var needsPanelToBecomeKey: Bool { true }
    // Not a first responder: AppKit would otherwise pick it as every window's initial
    // responder and build an editor for each note at launch.
    override var acceptsFirstResponder: Bool { false }
    override func mouseDown(with event: NSEvent) { onActivate?(event) }
    /// Stack swipes are recognized here, so an idle note never builds an editor to swipe.
    override func scrollWheel(with event: NSEvent) {
        if canSwipe() {
            switch swipe.handle(event) {
            case .swipe: heldBegan = nil; return
            case .undecided: if heldBegan == nil { heldBegan = event }; return
            case .other: break
            }
        }
        let events = heldBegan.map { [$0, event] } ?? [event]
        heldBegan = nil
        onScroll?(events)
    }
    override func accessibilityPerformPress() -> Bool { onActivate?(nil); return true }
}

