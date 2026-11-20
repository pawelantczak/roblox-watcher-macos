import Foundation
import AppKit
import CoreGraphics

// MARK: - Roblox Process & Window Discovery

public struct WindowService {
    
    public static func logTimestamp() -> String {
        let df = DateFormatter()
        df.dateFormat = "HH:mm:ss"
        return "[\(df.string(from: Date()))]"
    }
    
    public static func isoTimestamp() -> String {
        let df = ISO8601DateFormatter()
        return df.string(from: Date())
    }
    
    public static func findRobloxProcess() -> (pid: pid_t, placeId: String?)? {
        let task = Process()
        task.launchPath = "/usr/bin/pgrep"
        task.arguments = ["-fl", "RobloxPlayer"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        try? task.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        
        guard let output = String(data: data, encoding: .utf8), !output.isEmpty else { return nil }
        
        for line in output.components(separatedBy: "\n") {
            if line.contains("RobloxPlayer") && !line.contains("CrashHandler") {
                let parts = line.trimmingCharacters(in: .whitespaces).components(separatedBy: " ")
                let pid = pid_t(parts.first ?? "0") ?? 0
                let foundPlaceId = parsePlaceId(from: line)
                return (pid: pid, placeId: foundPlaceId)
            }
        }
        return nil
    }
    
    public static func parsePlaceId(from line: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: "placeId=(\\d+)", options: []) else { return nil }
        let range = NSRange(location: 0, length: line.utf16.count)
        if let match = regex.firstMatch(in: line, options: [], range: range),
           let r = Range(match.range(at: 1), in: line) {
            return String(line[r])
        }
        return nil
    }
    
    public static func findRobloxWindow() -> RobloxWindowInfo? {
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        for win in windowList {
            let owner = win[kCGWindowOwnerName as String] as? String ?? ""
            let layer = win[kCGWindowLayer as String] as? Int ?? 0
            if owner == "Roblox" && layer == 0 {
                let id = win[kCGWindowNumber as String] as? Int ?? 0
                let pid = win[kCGWindowOwnerPID as String] as? pid_t ?? 0
                if let boundsDict = win[kCGWindowBounds as String] as? [String: Any],
                   let rect = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) {
                    if rect.width > 200 && rect.height > 200 {
                        return RobloxWindowInfo(windowId: CGWindowID(id), bounds: rect, ownerPID: pid)
                    }
                }
            }
        }
        return nil
    }
    
    public static func activateRoblox() {
        let script = "tell application \"RobloxPlayer\" to activate"
        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)
        
        for app in NSWorkspace.shared.runningApplications {
            if app.bundleIdentifier == "com.roblox.RobloxPlayer" || app.localizedName == "Roblox" {
                app.activate(options: [.activateAllWindows])
                break
            }
        }
        usleep(300_000)
    }
    
    public static func unminimizeRobloxIfNeeded() {
        guard findRobloxProcess() != nil else { return }
        let script = """
        tell application "System Events"
            if exists (process "RobloxPlayer") then
                tell process "RobloxPlayer"
                    set frontmost to true
                    try
                        set value of attribute "AXMinimized" of window 1 to false
                    end try
                end tell
            end if
        end tell
        """
        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)
        usleep(150_000)
    }

    public static func checkScreenRecordingPermission(logger: ((String) -> Void)? = nil) -> Bool {
        if CGPreflightScreenCaptureAccess() {
            return true
        }
        let msg = "\(logTimestamp()) [PERMISSION ERROR] macOS Screen Recording permission is NOT granted! Requesting access..."
        if let logger = logger {
            logger(msg)
        } else {
            print(msg)
        }
        _ = CGRequestScreenCaptureAccess()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
        return false
    }
}
