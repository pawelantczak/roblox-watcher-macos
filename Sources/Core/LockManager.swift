import Foundation

// MARK: - POSIX Advisory File Locking

public struct LockManager {
    
    /// Tries to acquire a POSIX advisory kernel lock (flock).
    /// Returns file descriptor if acquired; returns nil if already locked or on error.
    public static func acquireLock(lockFilePath: String) -> Int32? {
        let fd = open(lockFilePath, O_CREAT | O_RDWR, 0o600)
        guard fd >= 0 else { return nil }
        if flock(fd, LOCK_EX | LOCK_NB) != 0 {
            close(fd)
            return nil
        }
        return fd
    }
    
    /// Releases and closes a held file lock.
    public static func releaseLock(fileDescriptor: Int32) {
        flock(fileDescriptor, LOCK_UN)
        close(fileDescriptor)
    }
}
