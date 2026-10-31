import AppKit

// Management UI follows the system appearance (light/dark) and accent color.
let canvas = NSColor.windowBackgroundColor
let primaryInk = NSColor.labelColor
let secondaryInk = NSColor.secondaryLabelColor
let tertiaryInk = NSColor.tertiaryLabelColor
let accent = NSColor.controlAccentColor

func label(_ text: String, size: CGFloat = 13, weight: NSFont.Weight = .regular, color: NSColor = primaryInk) -> NSTextField {
    let field = NSTextField(labelWithString: text)
    field.font = .systemFont(ofSize: size, weight: weight)
    field.textColor = color
    field.lineBreakMode = .byTruncatingTail
    return field
}

class ActionButton: NSButton {
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
        let circle = NSBezierPath(ovalIn: bounds.insetBy(dx: 3.5, dy: 3.5))
        theme.paper.setFill(); circle.fill()
        theme.ink.withAlphaComponent(0.12).setStroke(); circle.lineWidth = 1; circle.stroke()
        if selected {
            NSColor.controlAccentColor.setStroke()
            let ring = NSBezierPath(ovalIn: bounds.insetBy(dx: 1, dy: 1)); ring.lineWidth = 2; ring.stroke()
        }
    }
}

final class ImportWaitController: NSWindowController {
    private let progress = NSProgressIndicator(frame: NSRect(x: 18, y: 65, width: 18, height: 18))
    init(cancel: @escaping () -> Void) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 110), styleMask: [.titled], backing: .buffered, defer: false)
        super.init(window: window)
        window.title = "Importing files"; window.level = .floating; window.isReleasedWhenClosed = false
        window.center()
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

func symbol(_ name: String, size: CGFloat = 13, weight: NSFont.Weight = .medium, description: String? = nil) -> NSImage? {
    NSImage(systemSymbolName: name, accessibilityDescription: description)?.withSymbolConfiguration(.init(pointSize: size, weight: weight))
}

/// Borderless icon button with a soft rounded hover/press background, like toolbar buttons.
final class IconButton: ActionButton {
    private var tracking: NSTrackingArea?
    private var hovering = false { didSet { needsDisplay = true } }
    init(_ title: String, symbol name: String, size: CGFloat = 13, action: @escaping () -> Void) {
        super.init(title, action: action)
        self.title = ""
        image = symbol(name, size: size, description: title)
        imagePosition = .imageOnly
        contentTintColor = secondaryInk
    }
    required init?(coder: NSCoder) { fatalError() }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(rect: bounds, options: [.activeInKeyWindow, .mouseEnteredAndExited, .inVisibleRect], owner: self)
        addTrackingArea(tracking!)
    }
    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); hovering = false }
    override func draw(_ dirtyRect: NSRect) {
        if hovering || isHighlighted {
            NSColor.labelColor.withAlphaComponent(isHighlighted ? 0.16 : 0.08).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
        }
        super.draw(dirtyRect)
    }
}

/// A grouped settings box in the style of System Settings: rounded fill, rows separated by hairlines.
final class FormSection: NSView {
    private let stack = NSStackView()
    init(rows: [NSView]) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical; stack.spacing = 0; stack.alignment = .leading
        constrain(stack, in: self)
        for (index, row) in rows.enumerated() {
            if index > 0 {
                let line = SeparatorLine(); stack.addArrangedSubview(line)
                line.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14).isActive = true
                line.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14).isActive = true
            }
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
        }
    }
    required init?(coder: NSCoder) { fatalError() }
    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {
        wantsLayer = true
        layer?.cornerRadius = 10; layer?.cornerCurve = .continuous
        layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.045).cgColor
        layer?.borderColor = NSColor.labelColor.withAlphaComponent(0.07).cgColor; layer?.borderWidth = 1
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }

    /// A row: title (and optional caption) on the left, accessory on the right.
    static func row(_ title: String, caption: String? = nil, accessory: NSView, height: CGFloat = 44) -> NSView {
        let row = NSView(); row.translatesAutoresizingMaskIntoConstraints = false
        let text = NSStackView(); text.orientation = .vertical; text.alignment = .leading; text.spacing = 1
        text.addArrangedSubview(label(title, size: 13))
        if let caption { let detail = label(caption, size: 11, color: secondaryInk); text.addArrangedSubview(detail) }
        text.translatesAutoresizingMaskIntoConstraints = false; accessory.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(text); row.addSubview(accessory)
        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(greaterThanOrEqualToConstant: height),
            text.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 14), text.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            text.topAnchor.constraint(greaterThanOrEqualTo: row.topAnchor, constant: 8),
            accessory.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -14), accessory.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            accessory.leadingAnchor.constraint(greaterThanOrEqualTo: text.trailingAnchor, constant: 12)
        ])
        return row
    }
}

final class SeparatorLine: NSView {
    override init(frame: NSRect) { super.init(frame: frame); translatesAutoresizingMaskIntoConstraints = false; heightAnchor.constraint(equalToConstant: 1).isActive = true }
    required init?(coder: NSCoder) { fatalError() }
    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() { wantsLayer = true; layer?.backgroundColor = NSColor.separatorColor.cgColor }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
}

func sectionHeader(_ text: String) -> NSTextField {
    let field = label(text, size: 11, weight: .semibold, color: secondaryInk)
    field.translatesAutoresizingMaskIntoConstraints = false
    return field
}
