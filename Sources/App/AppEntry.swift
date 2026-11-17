import Foundation
import AppKit

// MARK: - Application Entrypoint & Single-Instance Enforcement

func enforceSingleInstance() {
    let lockPath = NSTemporaryDirectory() + "roblox_watcher_gui.lock"
    guard let lockFd = LockManager.acquireLock(lockFilePath: lockPath) else {
        // App is already running: activate existing window and terminate
        let myPid = ProcessInfo.processInfo.processIdentifier
        let otherApps = NSWorkspace.shared.runningApplications.filter {
            $0.processIdentifier != myPid && (
                $0.bundleIdentifier == "xyz.ps99clan.robloxwatcher" ||
                $0.localizedName == "Roblox Watcher" ||
                $0.executableURL?.lastPathComponent == "RobloxWatcher"
            )
        }
        otherApps.first?.activate()
        exit(0)
    }
    
    ftruncate(lockFd, 0)
    let pidString = "\(ProcessInfo.processInfo.processIdentifier)\n"
    pidString.withCString { ptr in
        _ = write(lockFd, ptr, strlen(ptr))
    }
}

@main
struct AppEntry {
    static func main() {
        enforceSingleInstance()
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
