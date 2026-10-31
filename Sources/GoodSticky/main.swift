import AppKit
import Darwin

#if GOODSTICKY_TESTING
if CommandLine.arguments.contains("--smoke-test") {
    let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("GoodStickySmoke-" + UUID().uuidString)
    setenv("GOODSTICKY_DATA_DIR", temporary.path, 1)
}
#endif
let app = NSApplication.shared
let residentLock: ResidentLock
do { residentLock = try ResidentLock(directory: LibraryLocation.directory) }
catch ResidentLock.Failure.alreadyRunning(let owner) {
    if owner > 0 { NSRunningApplication(processIdentifier: owner)?.activate(options: []) }
    DistributedNotificationCenter.default().postNotificationName(Notification.Name("app.goodsticky.showNotes"), object: LibraryLocation.directory.path, userInfo: nil, deliverImmediately: true)
    exit(0)
} catch {
    let alert = NSAlert(); alert.messageText = "Couldn’t open the note library"
    alert.informativeText = error.localizedDescription; alert.runModal(); exit(1)
}
let delegate = AppDelegate()
app.delegate = delegate
app.run()
