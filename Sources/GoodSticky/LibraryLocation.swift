import Foundation

enum LibraryLocation {
    static var directory: URL {
        (ProcessInfo.processInfo.environment["GOODSTICKY_DATA_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) } ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("GoodSticky", isDirectory: true)).standardizedFileURL.resolvingSymlinksInPath()
    }
}

