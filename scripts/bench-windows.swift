import Foundation
import CoreGraphics
import Darwin

// WindowServer surface visibility is a launch proxy, not proof of rendered pixels.
let pid = Int(CommandLine.arguments[1])!
let target = Int(CommandLine.arguments[2])!
let deadline = ProcessInfo.processInfo.systemUptime + 15
while ProcessInfo.processInfo.systemUptime < deadline {
    if kill(pid_t(pid), 0) != 0 { exit(2) }
    let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    let count = windows.filter {
        ($0[kCGWindowOwnerPID as String] as? Int) == pid &&
        ($0[kCGWindowLayer as String] as? Int ?? 0) < 0
    }.count
    if count >= target { print(count); exit(0) }
    usleep(5_000)
}
fputs("Timed out waiting for desktop note windows\n", stderr)
exit(1)
