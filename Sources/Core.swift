import Foundation
import CoreGraphics

// MARK: - Configuration & Stats Models

public struct Config: Codable, Equatable {
    public var checkIntervalSeconds: Double = 5.0
    public var reconnectCooldownSeconds: Double = 30.0
    public var placeId: String? = "8737899170"
    public var vipServerUrl: String? = nil
    public var autoClickReconnect: Bool = true
    public var autoRelaunchOnKick: Bool = true
    public var autoTeleportToEvent: Bool = true
    public var antiAfkEnabled: Bool = true
    public var antiAfkIntervalSeconds: Double = 300.0 // 5 minutes
    public var reconnectButtonText: String = "Reconnect"
    public var disconnectKeywords: [String] = [
        "disconnected",
        "lost connection",
        "error code: 277",
        "error code: 279",
        "error code: 267",
        "error code: 271",
        "error code: 268",
        "error code: 273",
        "server was shut down",
        "server has closed",
        "please reconnect",
        "connection lost",
        "connection closed"
    ]
    public var eventTargetKeywords: [String] = [
        "pumpkin",
        "tycoon"
    ]
    public var ignorePhrases: [String] = [
        "voice chat",
        "voice"
    ]
    
    public enum CodingKeys: String, CodingKey {
        case checkIntervalSeconds, reconnectCooldownSeconds, placeId, vipServerUrl
        case autoClickReconnect, autoRelaunchOnKick, autoTeleportToEvent
        case antiAfkEnabled, antiAfkIntervalSeconds
        case reconnectButtonText, disconnectKeywords, eventTargetKeywords, ignorePhrases
    }
    
    public init() {}
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        checkIntervalSeconds = try container.decodeIfPresent(Double.self, forKey: .checkIntervalSeconds) ?? 5.0
        reconnectCooldownSeconds = try container.decodeIfPresent(Double.self, forKey: .reconnectCooldownSeconds) ?? 30.0
        placeId = try container.decodeIfPresent(String.self, forKey: .placeId)
        vipServerUrl = try container.decodeIfPresent(String.self, forKey: .vipServerUrl)
        autoClickReconnect = try container.decodeIfPresent(Bool.self, forKey: .autoClickReconnect) ?? true
        autoRelaunchOnKick = try container.decodeIfPresent(Bool.self, forKey: .autoRelaunchOnKick) ?? true
        autoTeleportToEvent = try container.decodeIfPresent(Bool.self, forKey: .autoTeleportToEvent) ?? true
        antiAfkEnabled = try container.decodeIfPresent(Bool.self, forKey: .antiAfkEnabled) ?? true
        antiAfkIntervalSeconds = try container.decodeIfPresent(Double.self, forKey: .antiAfkIntervalSeconds) ?? 300.0
        reconnectButtonText = try container.decodeIfPresent(String.self, forKey: .reconnectButtonText) ?? "Reconnect"
        disconnectKeywords = try container.decodeIfPresent([String].self, forKey: .disconnectKeywords) ?? [
            "disconnected", "lost connection", "error code: 277", "error code: 279",
            "error code: 267", "error code: 271", "error code: 268", "error code: 273",
            "server was shut down", "server has closed", "please reconnect",
            "connection lost", "connection closed"
        ]
        eventTargetKeywords = try container.decodeIfPresent([String].self, forKey: .eventTargetKeywords) ?? ["pumpkin", "tycoon"]
        ignorePhrases = try container.decodeIfPresent([String].self, forKey: .ignorePhrases) ?? ["voice chat", "voice"]
    }
}

public struct Stats: Codable, Equatable {
    public var totalGameRestarts: Int = 0
    public var lastRestartTime: String? = nil
    
    public init(totalGameRestarts: Int = 0, lastRestartTime: String? = nil) {
        self.totalGameRestarts = totalGameRestarts
        self.lastRestartTime = lastRestartTime
    }
}

// MARK: - OCR Text & Detection Entities

public struct DetectedText: Equatable {
    public let text: String
    public let boundingBox: CGRect // Normalized (0...1) from bottom-left
    
    public init(text: String, boundingBox: CGRect) {
        self.text = text
        self.boundingBox = boundingBox
    }
}

public struct RobloxWindowInfo {
    public let windowId: CGWindowID
    public let bounds: CGRect
    public let ownerPID: pid_t
    
    public init(windowId: CGWindowID, bounds: CGRect, ownerPID: pid_t) {
        self.windowId = windowId
        self.bounds = bounds
        self.ownerPID = ownerPID
    }
}

// MARK: - Core Domain Logic & Filtering

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

// MARK: - Utilities & Formatters

public struct WatcherUtils {
    
    /// Extracts placeId numeric string from process command line string.
    public static func parsePlaceId(from commandLine: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: "placeId=(\\d+)", options: []) else { return nil }
        let range = NSRange(location: 0, length: commandLine.utf16.count)
        if let match = regex.firstMatch(in: commandLine, options: [], range: range),
           let r = Range(match.range(at: 1), in: commandLine) {
            return String(commandLine[r])
        }
        return nil
    }
    
    /// Formats remaining seconds into human-readable Anti-AFK countdown.
    public static func formatCountdown(seconds: Int) -> String {
        if seconds <= 0 { return "Clicking..." }
        let m = seconds / 60
        let s = seconds % 60
        return m > 0 ? "in \(m)m \(s < 10 ? "0" : "")\(s)s" : "in \(s)s"
    }
    
    /// Tries to acquire a POSIX advisory kernel lock (flock).
    /// Returns file descriptor if acquired; returns nil if already locked or error.
    public static func acquireKernelLock(lockFilePath: String) -> Int32? {
        let fd = open(lockFilePath, O_CREAT | O_RDWR, 0o600)
        guard fd >= 0 else { return nil }
        if flock(fd, LOCK_EX | LOCK_NB) != 0 {
            close(fd)
            return nil
        }
        return fd
    }
}
