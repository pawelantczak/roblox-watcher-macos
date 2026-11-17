import Foundation
import CoreGraphics

// MARK: - Classification & Filtering

public struct WatcherClassifier {
    
    /// Returns true if the text matches any non-fatal phrase that must be ignored.
    public static func isIgnored(text: String, ignorePhrases: [String]) -> Bool {
        let lower = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !lower.isEmpty else { return false }
        return ignorePhrases.contains { phrase in
            let p = phrase.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return !p.isEmpty && lower.contains(p)
        }
    }
    
    /// Returns true if the text indicates a fatal disconnect requiring action.
    public static func isFatalDisconnect(text: String, disconnectKeywords: [String], ignorePhrases: [String]) -> Bool {
        if isIgnored(text: text, ignorePhrases: ignorePhrases) {
            return false
        }
        let lower = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !lower.isEmpty else { return false }
        return disconnectKeywords.contains { kw in
            let k = kw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return !k.isEmpty && lower.contains(k)
        }
    }
    
    /// Scans detected text items for the reconnect button, honoring ignore phrases.
    public static func findReconnectButton(
        in items: [DetectedText],
        buttonText: String,
        ignorePhrases: [String]
    ) -> DetectedText? {
        let target = buttonText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !target.isEmpty else { return nil }
        
        for item in items {
            if isIgnored(text: item.text, ignorePhrases: ignorePhrases) {
                continue
            }
            let trimmed = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.caseInsensitiveCompare(buttonText) == .orderedSame || trimmed.lowercased() == target {
                return item
            }
        }
        return nil
    }
    
    /// Identifies event icons on the left UI panel (origin.x < maxNormalizedX).
    public static func findEventTarget(
        in items: [DetectedText],
        keywords: [String],
        maxNormalizedX: CGFloat = 0.35
    ) -> DetectedText? {
        for item in items {
            let lower = item.text.lowercased()
            let matches = keywords.contains { kw in
                let k = kw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                return !k.isEmpty && lower.contains(k)
            }
            if matches && item.boundingBox.origin.x < maxNormalizedX {
                return item
            }
        }
        return nil
    }
}

// MARK: - Legacy / Convenience Utilities

public struct WatcherUtils {
    public static func parsePlaceId(from commandLine: String) -> String? {
        WindowService.parsePlaceId(from: commandLine)
    }
    
    public static func formatCountdown(seconds: Int) -> String {
        if seconds <= 0 { return "Clicking..." }
        let m = seconds / 60
        let s = seconds % 60
        return m > 0 ? "in \(m)m \(s < 10 ? "0" : "")\(s)s" : "in \(s)s"
    }
    
    public static func acquireKernelLock(lockFilePath: String) -> Int32? {
        LockManager.acquireLock(lockFilePath: lockFilePath)
    }
}

