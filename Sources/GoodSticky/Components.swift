import AppKit

let canvas = NSColor.hex(0xF7F6F2)
let primaryInk = NSColor.hex(0x29342F)
let secondaryInk = NSColor.hex(0x5F685F)
let accent = NSColor.hex(0x44735D)

func label(_ text: String, size: CGFloat = 13, weight: NSFont.Weight = .regular, color: NSColor = primaryInk) -> NSTextField {
    let field = NSTextField(labelWithString: text)
    field.font = .systemFont(ofSize: size, weight: weight)
    field.textColor = color
    field.lineBreakMode = .byTruncatingTail
    return field
}

final class ActionButton: NSButton {
    var actionHandler: (() -> Void)?
    var focusChanged: ((Bool) -> Void)?
    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { focusChanged?(true) }
        return accepted
    }
    override func resignFirstResponder() -> Bool {
        let accepted = super.resignFirstResponder()
        if accepted { focusChanged?(false) }
        return accepted
    }
    init(_ title: String = "", symbol: String? = nil, action: @escaping () -> Void) {
        super.init(frame: .zero)
        self.title = title
        if let symbol { image = NSImage(systemSymbolName: symbol, accessibilityDescription: title) }
        self.actionHandler = action
        self.target = self
        self.action = #selector(invoke)
        isBordered = false
        bezelStyle = .regularSquare
        font = .systemFont(ofSize: 12, weight: .medium)
        contentTintColor = primaryInk
        toolTip = title
        setAccessibilityLabel(title)
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc func invoke() { actionHandler?() }
}

final class SurfaceView: NSView {
    var fill: NSColor { didSet { needsDisplay = true } }
    var radius: CGFloat
    var stroke: NSColor?
    init(fill: NSColor, radius: CGFloat = 12, stroke: NSColor? = nil) {
        self.fill = fill; self.radius = radius; self.stroke = stroke
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius)
        fill.setFill(); path.fill()
        if let stroke { stroke.setStroke(); path.lineWidth = 1; path.stroke() }
    }
}

func constrain(_ view: NSView, in parent: NSView, inset: CGFloat = 0) {
    view.translatesAutoresizingMaskIntoConstraints = false
    parent.addSubview(view)
    NSLayoutConstraint.activate([
        view.leadingAnchor.constraint(equalTo: parent.leadingAnchor, constant: inset),
        view.trailingAnchor.constraint(equalTo: parent.trailingAnchor, constant: -inset),
        view.topAnchor.constraint(equalTo: parent.topAnchor, constant: inset),
        view.bottomAnchor.constraint(equalTo: parent.bottomAnchor, constant: -inset)
    ])
}

final class FlippedView: NSView { override var isFlipped: Bool { true } }

final class SwatchButton: NSButton {
    let theme: NoteTheme
    var selected: Bool = false { didSet { state = selected ? .on : .off; setAccessibilityValue(selected ? 1 : 0); needsDisplay = true } }
    var handler: (() -> Void)?
    init(theme: NoteTheme, size: CGFloat = 26) {
        self.theme = theme
        super.init(frame: NSRect(x: 0, y: 0, width: size, height: size))
        isBordered = false
        title = ""
        target = self; action = #selector(choose)
        toolTip = theme.name
        setAccessibilityLabel(theme.name + " theme")
        setAccessibilityRole(.radioButton)
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: size).isActive = true
        heightAnchor.constraint(equalToConstant: size).isActive = true
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc private func choose() { handler?() }
    override func draw(_ dirtyRect: NSRect) {
        let circle = NSBezierPath(ovalIn: bounds.insetBy(dx: 3, dy: 3))
        theme.paper.setFill(); circle.fill()
        theme.ink.withAlphaComponent(0.12).setStroke(); circle.lineWidth = 1; circle.stroke()
        if selected {
            theme.ink.withAlphaComponent(0.75).setStroke()
            let ring = NSBezierPath(ovalIn: bounds.insetBy(dx: 0.8, dy: 0.8)); ring.lineWidth = 1.5; ring.stroke()
        }
    }
}

final class ImportWaitController: NSWindowController {
    private let progress = NSProgressIndicator(frame: NSRect(x: 18, y: 65, width: 18, height: 18))
    init(cancel: @escaping () -> Void) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 110), styleMask: [.titled], backing: .buffered, defer: false)
        super.init(window: window)
        window.title = "Importing files"; window.level = .floating; window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua); window.center()
        let root = SurfaceView(fill: canvas, radius: 0); window.contentView = root
        progress.style = .spinning; progress.controlSize = .small; progress.startAnimation(nil); root.addSubview(progress)
        let text = label("Quitting when imports finish.", size: 12)
        text.frame = NSRect(x: 47, y: 65, width: 240, height: 18); root.addSubview(text)
        let keep = ActionButton("Keep running", action: cancel)
        keep.isBordered = true; keep.bezelStyle = .rounded; keep.frame = NSRect(x: 164, y: 17, width: 118, height: 30)
        keep.keyEquivalent = "\u{1b}"; root.addSubview(keep)
    }
    override func close() { progress.stopAnimation(nil); super.close() }
    required init?(coder: NSCoder) { fatalError() }
}
