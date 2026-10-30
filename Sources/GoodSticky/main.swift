import AppKit

if CommandLine.arguments.contains("--smoke-test") {
    let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("GoodStickySmoke-" + UUID().uuidString)
    setenv("GOODSTICKY_DATA_DIR", temporary.path, 1)
}
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
