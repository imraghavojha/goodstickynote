import AppKit
import ServiceManagement

final class PreferencesWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool { super.performKeyEquivalent(with: event) || KeyCommands.perform(event) }
}

final class PreferencesController: NSWindowController, NSWindowDelegate {
    let shortcutButton = NSButton(title: "", target: nil, action: nil)
    let status = label("", size: 11, color: .systemRed)
    let percentage = label("100%", size: 12, color: secondaryInk)
    let login = NSSwitch()
    var monitor: Any?
    var swatches: [SwatchButton] = []
    private(set) var snoozeBoxes: [NSButton] = []
    init() {
        let window = PreferencesWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 380), styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        super.init(window: window)
        window.delegate = self; window.isReleasedWhenClosed = false; window.titlebarAppearsTransparent = true
        window.title = "GoodSticky Settings"; window.center()
        let root = NSVisualEffectView(); root.material = .windowBackground; root.blendingMode = .behindWindow; window.contentView = root

        shortcutButton.target = self; shortcutButton.action = #selector(recordShortcut)
        shortcutButton.bezelStyle = .rounded; shortcutButton.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        shortcutButton.title = HotKeyManager.display(NoteStore.shared.preferences)
        shortcutButton.widthAnchor.constraint(equalToConstant: 128).isActive = true
        shortcutButton.setAccessibilityLabel("New note shortcut")
        if !AppDelegate.shared.hotKey.isRegistered { status.stringValue = "The shortcut is in use by another app. Choose another combination." }
        login.target = self; login.action = #selector(toggleLogin(_:)); login.controlSize = .small
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        login.setAccessibilityLabel("Open at login")

        let colors = NSStackView(); colors.spacing = 6
        for theme in NoteTheme.all {
            let swatch = SwatchButton(theme: theme, size: 24)
            swatch.selected = NoteStore.shared.preferences.defaultTheme == theme.id
            swatch.handler = { [weak self] in
                NoteStore.shared.preferences.defaultTheme = theme.id; NoteStore.shared.save()
                self?.swatches.forEach { $0.selected = $0.theme.id == theme.id }
            }
            colors.addArrangedSubview(swatch); swatches.append(swatch)
        }
        let slider = NSSlider(value: NoteStore.shared.preferences.defaultOpacity, minValue: 0.35, maxValue: 1, target: self, action: #selector(opacityChanged(_:)))
        slider.isContinuous = true; slider.controlSize = .small; slider.widthAnchor.constraint(equalToConstant: 150).isActive = true
        percentage.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular); percentage.alignment = .right
        percentage.widthAnchor.constraint(equalToConstant: 38).isActive = true
        percentage.stringValue = "\(Int((slider.doubleValue * 100).rounded()))%"
        let opacity = NSStackView(views: [slider, percentage]); opacity.spacing = 8

        let general = FormSection(rows: [
            FormSection.row("New note shortcut", caption: "Works from any app", accessory: shortcutButton),
            FormSection.row("Open at login", caption: "Keep your notes on the desktop after restarting", accessory: login)
        ])
        let defaults = FormSection(rows: [
            FormSection.row("Color", accessory: colors),
            FormSection.row("Paper opacity", accessory: opacity)
        ])
        // Snooze times offered by each note's snooze button.
        let grid = NSGridView(numberOfColumns: 2, rows: 0)
        grid.rowSpacing = 7; grid.columnSpacing = 18
        let chosen = Set(NoteStore.shared.preferences.snoozeOptions)
        for option in SnoozeOption.allCases {
            let box = NSButton(checkboxWithTitle: option.settingsTitle, target: self, action: #selector(snoozeChanged))
            box.identifier = NSUserInterfaceItemIdentifier(option.rawValue)
            box.state = chosen.contains(option) ? .on : .off; box.controlSize = .small; box.font = .systemFont(ofSize: 12)
            snoozeBoxes.append(box)
        }
        for pair in stride(from: 0, to: snoozeBoxes.count, by: 2) {
            grid.addRow(with: [snoozeBoxes[pair], pair + 1 < snoozeBoxes.count ? snoozeBoxes[pair + 1] : NSGridCell.emptyContentView])
        }
        let snoozeRow = NSView(); snoozeRow.translatesAutoresizingMaskIntoConstraints = false
        grid.translatesAutoresizingMaskIntoConstraints = false; snoozeRow.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.leadingAnchor.constraint(equalTo: snoozeRow.leadingAnchor, constant: 14), grid.trailingAnchor.constraint(lessThanOrEqualTo: snoozeRow.trailingAnchor, constant: -14),
            grid.topAnchor.constraint(equalTo: snoozeRow.topAnchor, constant: 11), grid.bottomAnchor.constraint(equalTo: snoozeRow.bottomAnchor, constant: -11)
        ])
        let snooze = FormSection(rows: [snoozeRow])
        let snoozeTitle = sectionHeader("SNOOZE TIMES")
        let generalTitle = sectionHeader("GENERAL"), defaultsTitle = sectionHeader("NEW NOTES")
        let reveal = NSButton(title: "Show Library in Finder", target: self, action: #selector(showLibraryFolder))
        reveal.bezelStyle = .inline; reveal.controlSize = .small
        let version = label("GoodSticky \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")", size: 11, color: tertiaryInk)
        status.lineBreakMode = .byWordWrapping; status.maximumNumberOfLines = 2
        for view in [generalTitle, general, status, defaultsTitle, defaults, snoozeTitle, snooze, version, reveal] as [NSView] { view.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(view) }
        NSLayoutConstraint.activate([
            generalTitle.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 30), generalTitle.topAnchor.constraint(equalTo: root.topAnchor, constant: 46),
            general.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20), general.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20), general.topAnchor.constraint(equalTo: generalTitle.bottomAnchor, constant: 6),
            status.leadingAnchor.constraint(equalTo: generalTitle.leadingAnchor), status.trailingAnchor.constraint(equalTo: general.trailingAnchor), status.topAnchor.constraint(equalTo: general.bottomAnchor, constant: 6),
            defaultsTitle.leadingAnchor.constraint(equalTo: generalTitle.leadingAnchor), defaultsTitle.topAnchor.constraint(equalTo: status.bottomAnchor, constant: 4),
            defaults.leadingAnchor.constraint(equalTo: general.leadingAnchor), defaults.trailingAnchor.constraint(equalTo: general.trailingAnchor), defaults.topAnchor.constraint(equalTo: defaultsTitle.bottomAnchor, constant: 6),
            snoozeTitle.leadingAnchor.constraint(equalTo: generalTitle.leadingAnchor), snoozeTitle.topAnchor.constraint(equalTo: defaults.bottomAnchor, constant: 18),
            snooze.leadingAnchor.constraint(equalTo: general.leadingAnchor), snooze.trailingAnchor.constraint(equalTo: general.trailingAnchor), snooze.topAnchor.constraint(equalTo: snoozeTitle.bottomAnchor, constant: 6),
            version.leadingAnchor.constraint(equalTo: generalTitle.leadingAnchor), version.topAnchor.constraint(equalTo: snooze.bottomAnchor, constant: 18),
            version.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -20),
            reveal.trailingAnchor.constraint(equalTo: general.trailingAnchor, constant: -6), reveal.centerYAnchor.constraint(equalTo: version.centerYAnchor)
        ])
        NotificationCenter.default.addObserver(self, selector: #selector(stopRecording), name: NSWindow.didResignKeyNotification, object: window)
        root.layoutSubtreeIfNeeded()
        window.setContentSize(NSSize(width: 460, height: root.fittingSize.height))
    }
    required init?(coder: NSCoder) { fatalError() }
    func windowWillClose(_ notification: Notification) {
        stopRecording()
        if AppDelegate.shared.preferences === self { AppDelegate.shared.preferences = nil }
    }
    deinit { NotificationCenter.default.removeObserver(self) }
    @objc func showLibraryFolder() { NSWorkspace.shared.activateFileViewerSelecting([NoteStore.shared.directory.appendingPathComponent("notes.json")]) }
    @objc func toggleLogin(_ sender: NSSwitch) {
        do {
            if sender.state == .on { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            if SMAppService.mainApp.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
            status.stringValue = ""
        } catch {
            sender.state = SMAppService.mainApp.status == .enabled ? .on : .off
            status.stringValue = "Login setting failed: \(error.localizedDescription)"
        }
    }
    @objc func opacityChanged(_ sender: NSSlider) {
        NoteStore.shared.preferences.defaultOpacity = sender.doubleValue
        percentage.stringValue = "\(Int((sender.doubleValue * 100).rounded()))%"; NoteStore.shared.save()
    }
    @objc func snoozeChanged() {
        NoteStore.shared.preferences.snoozeOptions = snoozeBoxes.filter { $0.state == .on }.compactMap { $0.identifier.flatMap { SnoozeOption(rawValue: $0.rawValue) } }
        NoteStore.shared.save()
    }
    @objc func recordShortcut() { record() }
    @objc func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor); _ = AppDelegate.shared.hotKey.register(NoteStore.shared.preferences) }
        monitor = nil; shortcutButton.title = HotKeyManager.display(NoteStore.shared.preferences)
        shortcutButton.contentTintColor = nil; shortcutButton.state = .off
    }
    func record() {
        stopRecording(); AppDelegate.shared.hotKey.suspend()
        shortcutButton.title = "Type shortcut…"; shortcutButton.contentTintColor = accent
        status.textColor = secondaryInk; status.stringValue = "Hold ⌃, ⌥ or ⌘ and press a key. Esc cancels."
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53 { self.stopRecording(); self.status.stringValue = ""; return nil }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard !flags.intersection([.control, .option, .command]).isEmpty else { NSSound.beep(); return nil }
            var prefs = NoteStore.shared.preferences
            prefs.keyCode = UInt32(event.keyCode); prefs.modifiers = HotKeyManager.carbonFlags(flags)
            if AppDelegate.shared.hotKey.register(prefs) {
                NoteStore.shared.preferences = prefs; NoteStore.shared.save()
                self.status.stringValue = ""
                AppDelegate.shared.library?.refresh()
            } else {
                _ = AppDelegate.shared.hotKey.register(NoteStore.shared.preferences)
                self.status.textColor = .systemRed
                self.status.stringValue = "That shortcut is unavailable. Try another combination."
            }
            self.stopRecording(); return nil
        }
    }
}
