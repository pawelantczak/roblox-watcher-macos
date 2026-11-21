import Foundation
import AppKit
import CoreGraphics

// MARK: - Watcher Controller Engine

public class WatcherManager {
    public static let shared = WatcherManager()
    
    public private(set) var isRunning: Bool = false
    private var workerThread: Thread?
    private var shouldStop: Bool = false
    
    public var logs: [String] = []
    private let logLock = NSLock()
    
    public var config: Config = StorageService.loadConfig()
    public var stats: Stats = StorageService.loadStats()
    public var sessionRestarts: Int = 0
    public var lastKnownPlaceId: String? = nil
    
    public var latestEventCropBase64: String? = nil
    public var latestEventNormalizedCoords: CGPoint? = nil
    public var latestEventMatchedText: String? = nil
    public var lastAntiAfkClickTimestamp: Date = Date()
    
    public init() {
        lastKnownPlaceId = config.placeId
    }
    
    public func appendLog(_ line: String, eventCropBase64: String? = nil) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        logLock.lock()
        logs.append(trimmed)
        if logs.count > 200 { logs.removeFirst() }
        logLock.unlock()
        StorageService.appendLogToFile(trimmed, eventCropBase64: eventCropBase64)
    }
    
    public func clearLogs() {
        logLock.lock()
        logs.removeAll()
        logLock.unlock()
    }
    
    public func getRecentLogs() -> [String] {
        logLock.lock()
        defer { logLock.unlock() }
        return Array(logs.suffix(200))
    }
    
    public func start() {
        guard !isRunning else { return }
        isRunning = true
        shouldStop = false
        sessionRestarts = 0
        lastAntiAfkClickTimestamp = Date()
        config = StorageService.loadConfig()
        stats = StorageService.loadStats()
        
        appendLog("\(WindowService.logTimestamp()) [System] Starting native watcher engine...")
        PowerService.shared.enableSleepPrevention(reason: "Roblox Watcher Monitoring & Keep-Alive")
        appendLog("\(WindowService.logTimestamp()) [Power] Display sleep & auto-lock prevention active.")
        
        workerThread = Thread { [weak self] in self?.runLoop() }
        workerThread?.start()
    }
    
    public func stop() {
        guard isRunning else { return }
        shouldStop = true
        isRunning = false
        PowerService.shared.disableSleepPrevention()
        appendLog("\(WindowService.logTimestamp()) [Power] Display sleep prevention released.")
        appendLog("\(WindowService.logTimestamp()) [System] Stopped watcher engine.")
    }
    
    public func triggerTestTeleport() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            self.appendLog("\(WindowService.logTimestamp()) [Action] Manual test teleport triggered...")
            GameService.executeManualEventClick(
                keywords: self.config.eventTargetKeywords,
                logger: { msg, crop in self.appendLog(msg, eventCropBase64: crop) },
                onFound: { self.latestEventNormalizedCoords = $0; self.latestEventMatchedText = $1 }
            )
        }
    }
    
    private func runLoop() {
        let screenshotPath = StorageService.getScreenshotFileURL().path
        var lastActionTimestamp = Date.distantPast
        self.lastAntiAfkClickTimestamp = Date()
        let logTime = WindowService.logTimestamp
        
        appendLog("\(logTime()) [Config] Check Interval: \(config.checkIntervalSeconds)s | Target: \(config.reconnectButtonText)")
        appendLog("\(logTime()) [Status] Watcher is actively monitoring screen.\n")
        
        while !shouldStop {
            autoreleasepool {
                let now = Date()
                
                // 1. Process Check
                if let currentRoblox = WindowService.findRobloxProcess() {
                    if let pid = currentRoblox.placeId {
                        if pid != lastKnownPlaceId {
                            lastKnownPlaceId = pid
                            appendLog("\(logTime()) [Process] Active Place ID updated: \(pid)")
                        }
                    }
                    appendLog("\(logTime()) [Process] Roblox running (PID: \(currentRoblox.pid), Place: \(lastKnownPlaceId ?? "--")) | Restarts: \(sessionRestarts)")
                } else {
                    appendLog("\(logTime()) [Process] RobloxPlayer is not running.")
                }
                
                // 2. Cooldown Evaluation
                let elapsed = now.timeIntervalSince(lastActionTimestamp)
                let inCooldown = elapsed < config.reconnectCooldownSeconds
                
                if inCooldown {
                    let remaining = Int(config.reconnectCooldownSeconds - elapsed)
                    appendLog("\(logTime()) [Cooldown] Reconnect cooldown active (\(remaining)s remaining).")
                } else {
                    // 3. Screen Capture & OCR (Roblox Window ONLY)
                    if let (screenImage, winBounds) = VisionService.captureRobloxWindow(savePath: screenshotPath) {
                        let (detectedItems, durationMs) = VisionService.scanScreenForText(image: screenImage)
                        appendLog("\(logTime()) [OCR] Scanned Roblox window (\(Int(winBounds.width))x\(Int(winBounds.height))) in \(String(format: "%.1f", durationMs))ms: \(detectedItems.count) text segments")
                        
                        // Crop Event Icon for Debug UI if enabled
                        if config.autoTeleportToEvent {
                            var target = WatcherClassifier.findEventTarget(in: detectedItems, keywords: config.eventTargetKeywords)
                            if target == nil {
                                let sidebarItems = VisionService.scanLeftSidebarForText(image: screenImage)
                                target = WatcherClassifier.findEventTarget(in: sidebarItems, keywords: config.eventTargetKeywords)
                            }
                            if let target = target {
                                if let base64 = VisionService.cropBase64(from: screenImage, boundingBox: target.wholeIconBox ?? target.boundingBox) {
                                    self.latestEventCropBase64 = base64
                                    self.latestEventNormalizedCoords = CGPoint(x: target.clickPoint.x, y: 1.0 - target.clickPoint.y)
                                    self.latestEventMatchedText = target.text
                                }
                            } else {
                                (self.latestEventCropBase64, self.latestEventNormalizedCoords, self.latestEventMatchedText) = (nil, nil, nil)
                            }
                        }
                        
                        var isDisconnected = false
                        var reconnectBox: CGRect? = nil
                        var matchedKeyword = ""
                        let targetButton = config.reconnectButtonText
                        
                        if let btn = WatcherClassifier.findReconnectButton(
                            in: detectedItems,
                            buttonText: targetButton,
                            ignorePhrases: config.ignorePhrases
                        ) {
                            reconnectBox = btn.boundingBox
                            isDisconnected = true
                            matchedKeyword = "\"\(targetButton)\" button"
                        }
                        
                        for item in detectedItems {
                            if WatcherClassifier.isFatalDisconnect(
                                text: item.text,
                                disconnectKeywords: config.disconnectKeywords,
                                ignorePhrases: config.ignorePhrases
                            ) {
                                isDisconnected = true
                                if matchedKeyword.isEmpty {
                                    matchedKeyword = item.text
                                }
                                break
                            }
                        }
                        
                        if isDisconnected {
                            stats.totalGameRestarts += 1
                            sessionRestarts += 1
                            stats.lastRestartTime = logTime()
                            StorageService.saveStats(stats)
                            
                            appendLog("\n\(logTime()) [ALERT] Disconnect detected on Roblox window! Matched: \(matchedKeyword)")
                            appendLog("\(logTime()) [Stats] Session Restarts: \(sessionRestarts) (All-time Total: \(stats.totalGameRestarts))")
                            lastActionTimestamp = now
                            
                            if let box = reconnectBox, config.autoClickReconnect {
                                appendLog("\(logTime()) [Decision] Identified \"\(targetButton)\" button. Dispatching click...")
                                let clickX = winBounds.origin.x + Double(box.midX) * winBounds.width
                                let clickY = winBounds.origin.y + (1.0 - Double(box.midY)) * winBounds.height
                                let pt = CGPoint(x: clickX, y: clickY)
                                InputService.clickScreenAtPoint(point: pt, label: "\(targetButton) Button") { msg in
                                    self.appendLog(msg)
                                }
                                if config.autoTeleportToEvent {
                                    GameService.teleportToEventArea(screenshotPath: screenshotPath, targetKeywords: config.eventTargetKeywords) { msg, crop in
                                        self.appendLog(msg, eventCropBase64: crop)
                                    }
                                }
                            } else if config.autoRelaunchOnKick {
                                appendLog("\(logTime()) [Decision] \"\(targetButton)\" button not found. Relaunching game...")
                                GameService.killAndRelaunchGame(placeId: lastKnownPlaceId, vipUrl: config.vipServerUrl) { msg in
                                    self.appendLog(msg)
                                }
                                if config.autoTeleportToEvent {
                                    GameService.teleportToEventArea(screenshotPath: screenshotPath, targetKeywords: config.eventTargetKeywords) { msg, crop in
                                        self.appendLog(msg, eventCropBase64: crop)
                                    }
                                }
                            }
                        } else {
                            if let sample = detectedItems.prefix(3).map({ "\"\($0.text)\"" }) as [String]?, !sample.isEmpty {
                                appendLog("\(logTime()) [Check] Game healthy. Screen samples: [\(sample.joined(separator: ", "))]")
                            } else {
                                appendLog("\(logTime()) [Check] Game healthy. No disconnect dialog present.")
                            }
                            
                            // Anti-AFK Keep-Alive Click (background focus-click)
                            if self.config.antiAfkEnabled && now.timeIntervalSince(self.lastAntiAfkClickTimestamp) >= self.config.antiAfkIntervalSeconds {
                                self.lastAntiAfkClickTimestamp = now
                                let liveWin = WindowService.findRobloxWindow()
                                let currentBounds = liveWin?.bounds ?? winBounds
                                let targetPid = liveWin?.ownerPID ?? (WindowService.findRobloxProcess()?.pid ?? 0)
                                if targetPid > 0 {
                                    InputService.clickRobloxCenterInBackground(bounds: currentBounds, pid: targetPid) { self.appendLog($0) }
                                }
                            }
                        }
                    } else {
                        appendLog("\(logTime()) [Warning] Screen capture failed. Verify Screen Recording permissions.")
                    }
                }
            }
            
            // Sleep check interval in chunks of 0.5s for fast cancellation
            let steps = Int(max(1.0, config.checkIntervalSeconds) * 2)
            for _ in 0..<steps {
                if shouldStop { break }
                Thread.sleep(forTimeInterval: 0.5)
            }
        }
    }
}
