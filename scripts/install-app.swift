import Foundation
import Darwin

@main struct InstallApp {
    static func verify(_ app: URL) throws {
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["--verify", "--deep", "--strict", app.path]
        let errors = Pipe(); process.standardError = errors
        try process.run(); process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let detail = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "Invalid app signature"
            throw NSError(domain: "GoodStickyInstall", code: 1, userInfo: [NSLocalizedDescriptionKey: detail])
        }
    }
    static func swap(_ first: URL, _ second: URL) throws {
        let result = first.path.withCString { a in second.path.withCString { b in renameatx_np(AT_FDCWD, a, AT_FDCWD, b, UInt32(RENAME_SWAP)) } }
        guard result == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }
    static func main() {
        do { try install() }
        catch ResidentLock.Failure.alreadyRunning {
            fputs("Quit GoodSticky from its menu bar before installing an update.\n", stderr); exit(1)
        } catch { fputs("Installation failed: \(error.localizedDescription)\n", stderr); exit(1) }
    }
    static func install() throws {
        guard CommandLine.arguments.count == 3 else { fatalError("Usage: InstallApp source.app destination.app") }
        let source = URL(fileURLWithPath: CommandLine.arguments[1])
        let destination = URL(fileURLWithPath: CommandLine.arguments[2])
        // Hold the resident's writer lock throughout replacement to prevent launch/update races.
        let lock = try ResidentLock(directory: LibraryLocation.directory)
        try withExtendedLifetime(lock) {
            let manager = FileManager.default
            let parent = destination.deletingLastPathComponent()
            try manager.createDirectory(at: parent, withIntermediateDirectories: true)
            let stage = parent.appendingPathComponent(".GoodSticky-stage-\(UUID().uuidString).app")
            var keepStage = false
            defer { if !keepStage { try? manager.removeItem(at: stage) } }
            try manager.copyItem(at: source, to: stage)
            guard Bundle(url: stage)?.bundleIdentifier == "app.goodsticky.mac" else { throw CocoaError(.fileReadCorruptFile) }
            try verify(stage)
            if manager.fileExists(atPath: destination.path) {
                guard Bundle(url: destination)?.bundleIdentifier == "app.goodsticky.mac" else { throw CocoaError(.fileWriteFileExists) }
                try swap(stage, destination) // Atomic exchange on the destination volume; no missing-app interval.
                do { try verify(destination) }
                catch { try swap(stage, destination); throw error }
                let backup = parent.appendingPathComponent(".GoodSticky-previous.app")
                do {
                    if manager.fileExists(atPath: backup.path) { try manager.removeItem(at: backup) }
                    try manager.moveItem(at: stage, to: backup)
                } catch {
                    keepStage = true
                    fputs("Previous app retained at \(stage.path)\n", stderr)
                }
            } else { try manager.moveItem(at: stage, to: destination) }
        }
    }
}
