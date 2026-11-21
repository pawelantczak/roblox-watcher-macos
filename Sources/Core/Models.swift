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
        "turkey",
        "hunt",
        "pumpkin",
        "tycoon"
    ]
    public var ignorePhrases: [String] = [
        "voice chat",
        "voice"
    ]
    public var webServerEnabled: Bool = false
    public var webServerPort: Int = 8765
    public var webServerAuthToken: String? = nil
    
    public enum CodingKeys: String, CodingKey {
        case checkIntervalSeconds, reconnectCooldownSeconds, placeId, vipServerUrl
        case autoClickReconnect, autoRelaunchOnKick, autoTeleportToEvent
        case antiAfkEnabled, antiAfkIntervalSeconds
        case reconnectButtonText, disconnectKeywords, eventTargetKeywords, ignorePhrases
        case webServerEnabled, webServerPort, webServerAuthToken
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
        eventTargetKeywords = try container.decodeIfPresent([String].self, forKey: .eventTargetKeywords) ?? ["turkey", "hunt", "pumpkin", "tycoon"]
        ignorePhrases = try container.decodeIfPresent([String].self, forKey: .ignorePhrases) ?? ["voice chat", "voice"]
        webServerEnabled = try container.decodeIfPresent(Bool.self, forKey: .webServerEnabled) ?? false
        webServerPort = try container.decodeIfPresent(Int.self, forKey: .webServerPort) ?? 8765
        webServerAuthToken = try container.decodeIfPresent(String.self, forKey: .webServerAuthToken)
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

public struct DetectedWord: Equatable {
    public let word: String
    public let boundingBox: CGRect // Normalized (0...1) from bottom-left
    
    public init(word: String, boundingBox: CGRect) {
        self.word = word
        self.boundingBox = boundingBox
    }
}

public struct DetectedText: Equatable {
    public let text: String
    public let boundingBox: CGRect // Normalized (0...1) from bottom-left
    public let targetPoint: CGPoint? // Normalized (0...1) from bottom-left
    public let wholeIconBox: CGRect? // Normalized (0...1) from bottom-left
    public let wordBoxes: [DetectedWord]
    
    public init(text: String, boundingBox: CGRect, targetPoint: CGPoint? = nil, wholeIconBox: CGRect? = nil, wordBoxes: [DetectedWord] = []) {
        self.text = text
        self.boundingBox = boundingBox
        self.targetPoint = targetPoint
        self.wholeIconBox = wholeIconBox
        self.wordBoxes = wordBoxes
    }
    
    public var clickPoint: CGPoint {
        targetPoint ?? CGPoint(x: boundingBox.midX, y: boundingBox.midY)
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

// MARK: - JSONL Log Record Model

public struct LogRecord: Codable, Equatable {
    public var timestamp: String
    public var message: String
    public var eventCropBase64: String?
    
    public init(timestamp: String = WindowService.isoTimestamp(), message: String, eventCropBase64: String? = nil) {
        self.timestamp = timestamp
        self.message = message
        self.eventCropBase64 = eventCropBase64
    }
}
