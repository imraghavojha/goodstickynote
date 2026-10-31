import Foundation
import Darwin

/// One writer per library, including direct executable and development launches.
final class ResidentLock {
    enum Failure: Error { case alreadyRunning(pid_t) }
    private let descriptor: Int32
    init(directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent(".resident.lock")
        let fd = open(file.path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            let failure = errno
            close(fd)
            if failure == EWOULDBLOCK {
                let owner = (try? String(contentsOf: file, encoding: .utf8)).flatMap { pid_t($0.trimmingCharacters(in: .whitespacesAndNewlines)) } ?? 0
                throw Failure.alreadyRunning(owner)
            }
            throw POSIXError(POSIXErrorCode(rawValue: failure) ?? .EIO)
        }
        descriptor = fd
        let owner = Data("\(getpid())\n".utf8)
        _ = ftruncate(fd, 0)
        owner.withUnsafeBytes { bytes in _ = write(fd, bytes.baseAddress, bytes.count) }
    }
    deinit { close(descriptor) }
}
