import AppKit

final class NoteAppearanceController: NSViewController {
    let noteID: UUID
    var swatches: [SwatchButton] = []
    let percentage = label("", size: 11, color: secondaryInk)
    init(noteID: UUID) { self.noteID = noteID; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError() }
    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 252, height: 128))
        guard let note = NoteStore.shared.note(noteID) else { return }
        let paperTitle = sectionHeader("PAPER"); paperTitle.frame = NSRect(x: 16, y: 102, width: 120, height: 14); paperTitle.translatesAutoresizingMaskIntoConstraints = true; view.addSubview(paperTitle)
        for (index, theme) in NoteTheme.all.enumerated() {
            let swatch = SwatchButton(theme: theme, size: 26)
            swatch.translatesAutoresizingMaskIntoConstraints = true
            swatch.frame = NSRect(x: CGFloat(13 + index * 32), y: 68, width: 26, height: 26)
            swatch.selected = note.themeID == theme.id
            swatch.handler = { [weak self] in
                guard let self else { return }
                NoteStore.shared.update(self.noteID) { $0.themeID = theme.id }
                self.swatches.forEach { $0.selected = $0.theme.id == theme.id }
            }
            view.addSubview(swatch); swatches.append(swatch)
        }
        let title = label("Opacity", size: 12); title.frame = NSRect(x: 16, y: 40, width: 100, height: 16); view.addSubview(title)
        percentage.stringValue = "\(Int((note.opacity * 100).rounded()))%"; percentage.frame = NSRect(x: 180, y: 40, width: 56, height: 16); percentage.alignment = .right
        percentage.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular); view.addSubview(percentage)
        let slider = NSSlider(value: note.opacity, minValue: 0.35, maxValue: 1, target: self, action: #selector(changeOpacity(_:)))
        slider.frame = NSRect(x: 14, y: 12, width: 224, height: 24); slider.isContinuous = true; slider.controlSize = .small; view.addSubview(slider)
    }
    @objc func changeOpacity(_ slider: NSSlider) {
        NoteStore.shared.update(noteID) { $0.opacity = slider.doubleValue }
        percentage.stringValue = "\(Int((slider.doubleValue * 100).rounded()))%"
    }
}

