import Foundation
import CoreGraphics

// MARK: - Configuration Model

public struct Config: Codable, Equatable {
    public var checkIntervalSeconds: Double = 5.0
    public var reconnectCooldownSeconds: Double = 30.0
    public var placeId: String? = "8737899170"
    public var vipServerUrl: String? = nil
    public var autoClickReconnect: Bool = true
    public var autoRelaunchOnKick: Bool = true
    public var autoTeleportToEvent: Bool = true
    public var antiAfkEnabled: Bool = true
    public var antiAfkIntervalSeconds: Double = 600.0 // 10 minutes
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
        antiAfkIntervalSeconds = try container.decodeIfPresent(Double.self, forKey: .antiAfkIntervalSeconds) ?? 600.0
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

// MARK: - Stats Model

public struct Stats: Codable, Equatable {
    public var totalGameRestarts: Int = 0
    public var lastRestartTime: String? = nil
    
    public init(totalGameRestarts: Int = 0, lastRestartTime: String? = nil) {
        self.totalGameRestarts = totalGameRestarts
        self.lastRestartTime = lastRestartTime
    }
}

// MARK: - Vision OCR & Window Entities

public struct DetectedText: Equatable {
    public let text: String
    public let boundingBox: CGRect // Normalized (0...1) from bottom-left
    
    public init(text: String, boundingBox: CGRect) {
        self.text = text
        self.boundingBox = boundingBox
    }
}

public struct RobloxWindowInfo: Equatable {
    public let windowId: CGWindowID
    public let bounds: CGRect
    public let ownerPID: pid_t
    
    public init(windowId: CGWindowID, bounds: CGRect, ownerPID: pid_t) {
        self.windowId = windowId
        self.bounds = bounds
        self.ownerPID = ownerPID
    }
}
