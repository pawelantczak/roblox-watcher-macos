import Foundation
import AppKit
import WebKit
import Vision
import CoreGraphics
import ImageIO

// MARK: - Paths & Storage
func getStorageDirectory() -> URL {
    let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    let dir = appSupport.appendingPathComponent("RobloxWatcher")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

func getConfigFileURL() -> URL {
    let local = URL(fileURLWithPath: "config.json")
    if FileManager.default.fileExists(atPath: local.path) {
        return local
    }
    return getStorageDirectory().appendingPathComponent("config.json")
}

func getStatsFileURL() -> URL {
    let local = URL(fileURLWithPath: "stats.json")
    if FileManager.default.fileExists(atPath: local.path) {
        return local
    }
    return getStorageDirectory().appendingPathComponent("stats.json")
}

func getScreenshotFileURL() -> URL {
    return getStorageDirectory().appendingPathComponent("latest_capture.png")
}

func getAppVersion() -> String {
    if let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String, !v.isEmpty {
        return v
    }
    if let resURL = Bundle.main.url(forResource: "VERSION", withExtension: nil),
       let v = try? String(contentsOf: resURL, encoding: .utf8) {
        return v.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    if let local = try? String(contentsOfFile: "VERSION", encoding: .utf8) {
        return local.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    return "1.0.0"
}

// MARK: - Configuration & Stats
struct Config: Codable {
    var checkIntervalSeconds: Double = 5.0
    var reconnectCooldownSeconds: Double = 30.0
    var placeId: String? = "8737899170"
    var vipServerUrl: String? = nil
    var autoClickReconnect: Bool = true
    var autoRelaunchOnKick: Bool = true
    var autoTeleportToEvent: Bool = true
    var antiAfkEnabled: Bool = true
    var antiAfkIntervalSeconds: Double = 300.0 // 5 minutes
    var reconnectButtonText: String = "Reconnect"
    var disconnectKeywords: [String] = [
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
    var eventTargetKeywords: [String] = [
        "pumpkin",
        "tycoon"
    ]
    var ignorePhrases: [String] = [
        "voice chat",
        "voice"
    ]
    
    enum CodingKeys: String, CodingKey {
        case checkIntervalSeconds, reconnectCooldownSeconds, placeId, vipServerUrl
        case autoClickReconnect, autoRelaunchOnKick, autoTeleportToEvent
        case antiAfkEnabled, antiAfkIntervalSeconds
        case reconnectButtonText, disconnectKeywords, eventTargetKeywords, ignorePhrases
    }
    
    init() {}
    
    init(from decoder: Decoder) throws {
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

struct Stats: Codable {
    var totalGameRestarts: Int = 0
    var lastRestartTime: String? = nil
}

func loadConfig() -> Config {
    let file = getConfigFileURL()
    if let data = try? Data(contentsOf: file),
       let config = try? JSONDecoder().decode(Config.self, from: data) {
        return config
    }
    let defaultConfig = Config()
    let encoder = JSONEncoder()
    encoder.outputFormatting = .prettyPrinted
    if let encoded = try? encoder.encode(defaultConfig) {
        try? encoded.write(to: file)
    }
    return defaultConfig
}

func saveConfig(_ config: Config) {
    let file = getConfigFileURL()
    let encoder = JSONEncoder()
    encoder.outputFormatting = .prettyPrinted
    if let encoded = try? encoder.encode(config) {
        try? encoded.write(to: file)
    }
}

func loadStats() -> Stats {
    let file = getStatsFileURL()
    if let data = try? Data(contentsOf: file),
       let stats = try? JSONDecoder().decode(Stats.self, from: data) {
        return stats
    }
    return Stats()
}

func saveStats(_ stats: Stats) {
    let file = getStatsFileURL()
    let encoder = JSONEncoder()
    encoder.outputFormatting = .prettyPrinted
    if let encoded = try? encoder.encode(stats) {
        try? encoded.write(to: file)
    }
}

func logTimestamp() -> String {
    let df = DateFormatter()
    df.dateFormat = "HH:mm:ss"
    return "[\(df.string(from: Date()))]"
}

// MARK: - Process & Window Helpers
func findRobloxProcess() -> (pid: pid_t, placeId: String?)? {
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
            
            var foundPlaceId: String? = nil
            if let regex = try? NSRegularExpression(pattern: "placeId=(\\d+)", options: []) {
                let range = NSRange(location: 0, length: line.utf16.count)
                if let match = regex.firstMatch(in: line, options: [], range: range),
                   let r = Range(match.range(at: 1), in: line) {
                    foundPlaceId = String(line[r])
                }
            }
            return (pid: pid, placeId: foundPlaceId)
        }
    }
    return nil
}

func activateRoblox() {
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

// MARK: - Screen OCR & Capture
struct RobloxWindowInfo {
    let windowId: CGWindowID
    let bounds: CGRect
    let ownerPID: pid_t
}

func findRobloxWindow() -> RobloxWindowInfo? {
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

struct DetectedText {
    let text: String
    let boundingBox: CGRect
}

func captureRobloxWindow(savePath: String) -> (image: CGImage, bounds: CGRect)? {
    let task = Process()
    task.launchPath = "/usr/sbin/screencapture"
    
    var windowBounds = CGRect(x: 0, y: 0, width: 2560, height: 1440)
    if let win = findRobloxWindow() {
        // Target ONLY the Roblox window: ignores all floating/overlapping windows on top of it
        task.arguments = ["-x", "-o", "-l", "\(win.windowId)", savePath]
        windowBounds = win.bounds
    } else {
        // Fallback to main monitor if window is transitioning
        task.arguments = ["-x", "-m", savePath]
        if let screen = NSScreen.main {
            windowBounds = screen.frame
        }
    }
    
    try? task.run()
    task.waitUntilExit()
    
    guard task.terminationStatus == 0 else { return nil }
    let url = URL(fileURLWithPath: savePath) as CFURL
    guard let source = CGImageSourceCreateWithURL(url, nil),
          let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        return nil
    }
    return (cgImage, windowBounds)
}

func scanScreenForText(image: CGImage) -> (detected: [DetectedText], durationMs: Double) {
    let startTime = DispatchTime.now()
    var detected: [DetectedText] = []
    let request = VNRecognizeTextRequest { req, _ in
        guard let observations = req.results as? [VNRecognizedTextObservation] else { return }
        for obs in observations {
            if let topCandidate = obs.topCandidates(1).first {
                detected.append(DetectedText(text: topCandidate.string, boundingBox: obs.boundingBox))
            }
        }
    }
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = false
    
    let handler = VNImageRequestHandler(cgImage: image, options: [:])
    try? handler.perform([request])
    
    let endTime = DispatchTime.now()
    let elapsedNano = endTime.uptimeNanoseconds - startTime.uptimeNanoseconds
    let durationMs = Double(elapsedNano) / 1_000_000.0
    return (detected, durationMs)
}

func clickScreenAtPoint(point: CGPoint, label: String = "Target", logger: (String) -> Void) {
    logger("\(logTimestamp()) [Action] Focusing Roblox & clicking \(label) at (\(Int(point.x)), \(Int(point.y)))...")
    activateRoblox()
    
    // 1. Warp hardware cursor & hover
    CGWarpMouseCursorPosition(point)
    if let moveEvent = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left) {
        moveEvent.post(tap: .cghidEventTap)
    }
    usleep(200_000)
    
    // 2. Click 1: Activates the Roblox window
    if let down1 = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left),
       let up1 = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left) {
        down1.post(tap: .cghidEventTap)
        usleep(80_000)
        up1.post(tap: .cghidEventTap)
    }
    
    // 3. Pause for Roblox window activation to complete
    usleep(250_000)
    
    // 4. Click 2: Actually triggers the in-game action / movement
    if let down2 = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left),
       let up2 = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left) {
        down2.post(tap: .cghidEventTap)
        usleep(80_000)
        up2.post(tap: .cghidEventTap)
    }
    
    logger("\(logTimestamp()) [Success] Two-click sequence dispatched to \(label) (1st activate, 2nd action).")
}

func clickRobloxCenterInBackground(bounds: CGRect, pid: pid_t, logger: ((String) -> Void)? = nil) {
    let center = CGPoint(x: bounds.midX, y: bounds.midY)
    let frontmost = NSWorkspace.shared.frontmostApplication
    let isRobloxAlreadyFrontmost = frontmost?.bundleIdentifier == "com.roblox.RobloxPlayer"
    let savedCursor = CGEvent(source: nil)?.location ?? .zero
    
    // 1. Activate Roblox and wait until WindowServer confirms it is actively focused (up to 300ms)
    if !isRobloxAlreadyFrontmost {
        if let robloxApp = NSRunningApplication.runningApplications(withBundleIdentifier: "com.roblox.RobloxPlayer").first {
            robloxApp.activate()
            let start = Date()
            while !robloxApp.isActive && Date().timeIntervalSince(start) < 0.3 {
                usleep(15_000)
            }
        }
    }
    
    // 2. Warp hardware cursor to center
    CGWarpMouseCursorPosition(center)
    
    // 3. Click 1: Confirms active window focus in AppKit
    if let down1 = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: center, mouseButton: .left),
       let up1 = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: center, mouseButton: .left) {
        down1.post(tap: .cghidEventTap)
        usleep(40_000)
        up1.post(tap: .cghidEventTap)
    }
    
    // Dwell pause so Roblox frame updates
    usleep(100_000)
    
    // 4. Click 2: Guaranteed in-game input registered by Roblox UserInputService
    if let down2 = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: center, mouseButton: .left),
       let up2 = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: center, mouseButton: .left) {
        down2.post(tap: .cghidEventTap)
        usleep(40_000)
        up2.post(tap: .cghidEventTap)
    }
    
    // Allow game engine to process input before focus restore
    usleep(80_000)
    
    // 5. Restore previous application focus and hardware cursor position
    if !isRobloxAlreadyFrontmost {
        CGWarpMouseCursorPosition(savedCursor)
        frontmost?.activate()
    }
    
    logger?("\(logTimestamp()) [Anti-AFK] Keep-alive dual-click sent at (\(Int(center.x)), \(Int(center.y))) with verified focus & restore.")
}

func killAndRelaunchGame(placeId: String?, vipUrl: String?, logger: (String) -> Void) {
    logger("\(logTimestamp()) [Action] Force-closing stale RobloxPlayer...")
    
    let killTask = Process()
    killTask.launchPath = "/usr/bin/pkill"
    killTask.arguments = ["-9", "-f", "RobloxPlayer"]
    try? killTask.run()
    killTask.waitUntilExit()
    
    sleep(2)
    
    let launchUrl: String
    if let vip = vipUrl, !vip.isEmpty {
        launchUrl = vip
    } else if let pid = placeId, !pid.isEmpty {
        launchUrl = "roblox://experiences/start?placeId=\(pid)"
    } else {
        logger("\(logTimestamp()) [Error] No placeId or VIP link available to relaunch game.")
        return
    }
    
    logger("\(logTimestamp()) [Action] Launching: \(launchUrl)")
    let openTask = Process()
    openTask.launchPath = "/usr/bin/open"
    openTask.arguments = [launchUrl]
    try? openTask.run()
    openTask.waitUntilExit()
    logger("\(logTimestamp()) [Success] Rejoin request sent to macOS system.")
}

func teleportToEventArea(screenshotPath: String, targetKeywords: [String], maxWaitSeconds: Int = 50, logger: (String) -> Void) {
    let keywordsDisplay = targetKeywords.joined(separator: ", ")
    logger("\n\(logTimestamp()) [Event Nav] Waiting for game to load before teleporting (targets: [\(keywordsDisplay)])...")
    
    let startTime = Date()
    while Date().timeIntervalSince(startTime) < Double(maxWaitSeconds) {
        var foundAndClicked = false
        autoreleasepool {
            Thread.sleep(forTimeInterval: 2.5)
            
            guard let (screenImage, winBounds) = captureRobloxWindow(savePath: screenshotPath) else { return }
            let (detectedItems, _) = scanScreenForText(image: screenImage)
            
            for item in detectedItems {
                let lower = item.text.lowercased()
                let matches = targetKeywords.contains { kw in lower.contains(kw.lowercased()) }
                if matches && item.boundingBox.origin.x < 0.35 {
                    let liveWin = findRobloxWindow()
                    let currentBounds = liveWin?.bounds ?? winBounds
                    let localX = Double(item.boundingBox.midX) * currentBounds.width
                    let localY = (1.0 - Double(item.boundingBox.midY)) * currentBounds.height
                    
                    let textX = currentBounds.origin.x + localX
                    let textY = currentBounds.origin.y + localY
                    let iconPoint = CGPoint(x: textX, y: max(currentBounds.origin.y, textY - 45))
                    
                    logger("\(logTimestamp()) [Event Nav] Detected \"\(item.text)\" on Roblox window! Dispatching clicks...")
                    clickScreenAtPoint(point: iconPoint, label: "Event Icon Graphic", logger: logger)
                    logger("\(logTimestamp()) [Event Nav] Teleport dispatched successfully!\n")
                    foundAndClicked = true
                    return
                }
            }
        }
        if foundAndClicked { return }
        
        let elapsed = Int(Date().timeIntervalSince(startTime))
        logger("[Event Nav] Waiting for event icon [\(keywordsDisplay)] to appear (\(elapsed)/\(maxWaitSeconds)s)...")
    }
    
    logger("\n\(logTimestamp()) [Event Nav] Timeout: Event icon [\(keywordsDisplay)] not detected on Roblox window. Skipping click to prevent accidental inputs.\n")
}

// MARK: - Watcher Controller
class WatcherManager {
    static let shared = WatcherManager()
    
    private(set) var isRunning: Bool = false
    private var workerThread: Thread?
    private var shouldStop: Bool = false
    
    var logs: [String] = []
    let logLock = NSLock()
    
    var config: Config = loadConfig()
    var stats: Stats = loadStats()
    var sessionRestarts: Int = 0
    var lastKnownPlaceId: String? = nil
    
    var latestEventCropBase64: String? = nil
    var latestEventNormalizedCoords: CGPoint? = nil
    var latestEventMatchedText: String? = nil
    var lastAntiAfkClickTimestamp: Date = Date()
    
    init() {
        lastKnownPlaceId = config.placeId
    }
    
    func appendLog(_ line: String) {
        logLock.lock()
        defer { logLock.unlock() }
        logs.append(line.trimmingCharacters(in: .whitespacesAndNewlines))
        if logs.count > 50 {
            logs.removeFirst()
        }
    }
    
    func getRecentLogs() -> [String] {
        logLock.lock()
        defer { logLock.unlock() }
        return Array(logs.suffix(25))
    }
    
    func start() {
        guard !isRunning else { return }
        isRunning = true
        shouldStop = false
        sessionRestarts = 0
        lastAntiAfkClickTimestamp = Date()
        config = loadConfig()
        stats = loadStats()
        
        appendLog("\(logTimestamp()) [System] Starting native watcher engine...")
        
        workerThread = Thread { [weak self] in
            self?.runLoop()
        }
        workerThread?.start()
    }
    
    func stop() {
        guard isRunning else { return }
        shouldStop = true
        isRunning = false
        appendLog("\(logTimestamp()) [System] Stopped watcher engine.")
    }
    
    func triggerTestTeleport() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            self.appendLog("\(logTimestamp()) [Action] Manual test teleport triggered...")
            
            // 1. Accessibility permission verification
            if !AXIsProcessTrusted() {
                self.appendLog("\(logTimestamp()) [ALERT] macOS Accessibility permission is missing for Roblox Watcher!")
                self.appendLog("\(logTimestamp()) [Action] Opening System Settings > Accessibility. Please enable Roblox Watcher.")
                let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
                _ = AXIsProcessTrustedWithOptions(options)
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                    NSWorkspace.shared.open(url)
                }
                return
            }
            
            // 2. Re-fetch LIVE Roblox window position
            guard let liveWin = findRobloxWindow() else {
                self.appendLog("\(logTimestamp()) [Error] Roblox window not found on screen. Bring Roblox into view.")
                return
            }
            
            // 3. If event icon coordinates are already tracked, compute live point and click immediately
            if let norm = self.latestEventNormalizedCoords {
                let liveX = liveWin.bounds.origin.x + (norm.x * liveWin.bounds.width)
                let liveY = liveWin.bounds.origin.y + (norm.y * liveWin.bounds.height)
                let pt = CGPoint(x: liveX, y: liveY)
                self.appendLog("\(logTimestamp()) [Action] Dispatching two-click sequence to live icon at (\(Int(liveX)), \(Int(liveY)))...")
                clickScreenAtPoint(point: pt, label: "Event Icon Graphic", logger: { msg in self.appendLog(msg) })
                return
            }
            
            // 4. Perform an instant one-shot OCR scan on the current screen
            let screenshotPath = getScreenshotFileURL().path
            if let (screenImage, winBounds) = captureRobloxWindow(savePath: screenshotPath) {
                let (detectedItems, _) = scanScreenForText(image: screenImage)
                for item in detectedItems {
                    let lower = item.text.lowercased()
                    let matches = self.config.eventTargetKeywords.contains { kw in lower.contains(kw.lowercased()) }
                    if matches && item.boundingBox.origin.x < 0.35 {
                        let localX = Double(item.boundingBox.midX) * winBounds.width
                        let localY = (1.0 - Double(item.boundingBox.midY)) * winBounds.height
                        let iconCenterY = max(0, localY - 45)
                        
                        let currentWin = findRobloxWindow() ?? liveWin
                        let targetX = currentWin.bounds.origin.x + localX
                        let targetY = currentWin.bounds.origin.y + iconCenterY
                        let pt = CGPoint(x: targetX, y: targetY)
                        
                        self.latestEventNormalizedCoords = CGPoint(x: localX / winBounds.width, y: iconCenterY / winBounds.height)
                        self.latestEventMatchedText = item.text
                        
                        self.appendLog("\(logTimestamp()) [Action] Found \"\(item.text)\" on UI! Clicking at (\(Int(targetX)), \(Int(targetY)))...")
                        clickScreenAtPoint(point: pt, label: "Detected Event Icon", logger: { msg in self.appendLog(msg) })
                        return
                    }
                }
            }
            
            // 5. Not found: Log safely and do not click blindly
            let kwList = self.config.eventTargetKeywords.joined(separator: ", ")
            self.appendLog("\(logTimestamp()) [Warning] Event icon matching [\(kwList)] not detected on screen. No click dispatched.")
        }
    }
    
    private func runLoop() {
        let screenshotPath = getScreenshotFileURL().path
        var lastActionTimestamp = Date.distantPast
        self.lastAntiAfkClickTimestamp = Date()
        
        appendLog("\(logTimestamp()) [Config] Check Interval: \(config.checkIntervalSeconds)s | Target: \(config.reconnectButtonText)")
        appendLog("\(logTimestamp()) [Status] Watcher is actively monitoring screen.\n")
        
        while !shouldStop {
            autoreleasepool {
                let now = Date()
                
                // 1. Process Check
                if let currentRoblox = findRobloxProcess() {
                    if let pid = currentRoblox.placeId {
                        if pid != lastKnownPlaceId {
                            lastKnownPlaceId = pid
                            appendLog("\(logTimestamp()) [Process] Active Place ID updated: \(pid)")
                        }
                    }
                    appendLog("\(logTimestamp()) [Process] Roblox running (PID: \(currentRoblox.pid), Place: \(lastKnownPlaceId ?? "--")) | Restarts: \(sessionRestarts)")
                } else {
                    appendLog("\(logTimestamp()) [Process] RobloxPlayer is not running.")
                }
                
                // 2. Cooldown Evaluation
                let elapsed = now.timeIntervalSince(lastActionTimestamp)
                let inCooldown = elapsed < config.reconnectCooldownSeconds
                
                if inCooldown {
                    let remaining = Int(config.reconnectCooldownSeconds - elapsed)
                    appendLog("\(logTimestamp()) [Cooldown] Reconnect cooldown active (\(remaining)s remaining).")
                } else {
                    // 3. Screen Capture & OCR (Roblox Window ONLY)
                    if let (screenImage, winBounds) = captureRobloxWindow(savePath: screenshotPath) {
                        let (detectedItems, durationMs) = scanScreenForText(image: screenImage)
                        appendLog("\(logTimestamp()) [OCR] Scanned Roblox window (\(Int(winBounds.width))x\(Int(winBounds.height))) in \(String(format: "%.1f", durationMs))ms: \(detectedItems.count) text segments")
                        
                        // Crop Event Icon for Debug UI if enabled
                        if config.autoTeleportToEvent {
                            for item in detectedItems {
                                let lower = item.text.lowercased()
                                let matches = config.eventTargetKeywords.contains { kw in lower.contains(kw.lowercased()) }
                                if matches && item.boundingBox.origin.x < 0.35 {
                                    let localX = Double(item.boundingBox.midX) * winBounds.width
                                    let localY = (1.0 - Double(item.boundingBox.midY)) * winBounds.height
                                    let iconCenterY = max(0, localY - 45)
                                    let cropRect = CGRect(x: max(0, localX - 60), y: max(0, iconCenterY - 60), width: 120, height: 120)
                                    if let cropped = screenImage.cropping(to: cropRect) {
                                        let rep = NSBitmapImageRep(cgImage: cropped)
                                        if let png = rep.representation(using: .png, properties: [:]) {
                                            self.latestEventCropBase64 = png.base64EncodedString()
                                            self.latestEventNormalizedCoords = CGPoint(x: localX / winBounds.width, y: iconCenterY / winBounds.height)
                                            self.latestEventMatchedText = item.text
                                        }
                                    }
                                    break
                                }
                            }
                        }
                        
                        var isDisconnected = false
                        var reconnectBox: CGRect? = nil
                        var matchedKeyword = ""
                        let targetButton = config.reconnectButtonText.trimmingCharacters(in: .whitespacesAndNewlines)
                        
                        for item in detectedItems {
                            let trimmed = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
                            let lower = trimmed.lowercased()
                            
                            // Ignore non-fatal notification toasts (e.g. "You've disconnected from Voice Chat")
                            if config.ignorePhrases.contains(where: { lower.contains($0.lowercased()) }) {
                                continue
                            }
                            
                            if trimmed.caseInsensitiveCompare(targetButton) == .orderedSame || lower == targetButton.lowercased() {
                                reconnectBox = item.boundingBox
                                isDisconnected = true
                                matchedKeyword = "\"\(targetButton)\" button"
                            }
                            
                            for keyword in config.disconnectKeywords {
                                if lower.contains(keyword.lowercased()) {
                                    isDisconnected = true
                                    if matchedKeyword.isEmpty {
                                        matchedKeyword = item.text
                                    }
                                    break
                                }
                            }
                        }
                        
                        if isDisconnected {
                            stats.totalGameRestarts += 1
                            sessionRestarts += 1
                            stats.lastRestartTime = logTimestamp()
                            saveStats(stats)
                            
                            appendLog("\n\(logTimestamp()) [ALERT] Disconnect detected on Roblox window! Matched: \(matchedKeyword)")
                            appendLog("\(logTimestamp()) [Stats] Session Restarts: \(sessionRestarts) (All-time Total: \(stats.totalGameRestarts))")
                            lastActionTimestamp = now
                            
                            if let box = reconnectBox, config.autoClickReconnect {
                                appendLog("\(logTimestamp()) [Decision] Identified \"\(targetButton)\" button. Dispatching click...")
                                let clickX = winBounds.origin.x + Double(box.midX) * winBounds.width
                                let clickY = winBounds.origin.y + (1.0 - Double(box.midY)) * winBounds.height
                                let pt = CGPoint(x: clickX, y: clickY)
                                clickScreenAtPoint(point: pt, label: "\(targetButton) Button") { msg in
                                    self.appendLog(msg)
                                }
                                if config.autoTeleportToEvent {
                                    teleportToEventArea(screenshotPath: screenshotPath, targetKeywords: config.eventTargetKeywords) { msg in
                                        self.appendLog(msg)
                                    }
                                }
                            } else if config.autoRelaunchOnKick {
                                appendLog("\(logTimestamp()) [Decision] \"\(targetButton)\" button not found. Relaunching game...")
                                killAndRelaunchGame(placeId: lastKnownPlaceId, vipUrl: config.vipServerUrl) { msg in
                                    self.appendLog(msg)
                                }
                                if config.autoTeleportToEvent {
                                    teleportToEventArea(screenshotPath: screenshotPath, targetKeywords: config.eventTargetKeywords) { msg in
                                        self.appendLog(msg)
                                    }
                                }
                            }
                        } else {
                            if let sample = detectedItems.prefix(3).map({ "\"\($0.text)\"" }) as [String]?, !sample.isEmpty {
                                appendLog("\(logTimestamp()) [Check] Game healthy. Screen samples: [\(sample.joined(separator: ", "))]")
                            } else {
                                appendLog("\(logTimestamp()) [Check] Game healthy. No disconnect dialog present.")
                            }
                            
                            // Anti-AFK Keep-Alive Click (every 5 minutes in background)
                            if config.antiAfkEnabled && now.timeIntervalSince(self.lastAntiAfkClickTimestamp) >= config.antiAfkIntervalSeconds {
                                self.lastAntiAfkClickTimestamp = now
                                let liveWin = findRobloxWindow()
                                let currentBounds = liveWin?.bounds ?? winBounds
                                let targetPid = liveWin?.ownerPID ?? (findRobloxProcess()?.pid ?? 0)
                                if targetPid > 0 {
                                    clickRobloxCenterInBackground(bounds: currentBounds, pid: targetPid) { msg in
                                        self.appendLog(msg)
                                    }
                                }
                            }
                        }
                    } else {
                        appendLog("\(logTimestamp()) [Warning] Screen capture failed. Verify Screen Recording permissions.")
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

func createThumbnailBase64(from imageURL: URL, maxDimension: CGFloat = 960) -> String? {
    guard FileManager.default.fileExists(atPath: imageURL.path),
          let source = CGImageSourceCreateWithURL(imageURL as CFURL, nil) else { return nil }
    let options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceShouldCacheImmediately: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: maxDimension
    ]
    guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
    let rep = NSBitmapImageRep(cgImage: thumbnail)
    guard let jpegData = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.65]) else { return nil }
    return jpegData.base64EncodedString()
}

// MARK: - Native App Window & Bridge
class NativeBridgeHandler: NSObject, WKScriptMessageHandler {
    weak var webView: WKWebView?
    
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let action = body["action"] as? String else { return }
        
        switch action {
        case "start":
            WatcherManager.shared.start()
        case "stop":
            WatcherManager.shared.stop()
        case "testTeleport":
            WatcherManager.shared.triggerTestTeleport()
        case "refreshScreenshot":
            _ = captureRobloxWindow(savePath: getScreenshotFileURL().path)
        case "openExternal":
            if let urlString = body["url"] as? String, let url = URL(string: urlString) {
                NSWorkspace.shared.open(url)
            }
        case "getConfig":
            let cfg = WatcherManager.shared.config
            if let data = try? JSONEncoder().encode(cfg),
               let jsonString = String(data: data, encoding: .utf8) {
                DispatchQueue.main.async {
                    self.webView?.evaluateJavaScript("window.populateConfig(\(jsonString));", completionHandler: nil)
                }
            }
        case "saveConfig":
            if let cfgDict = body["config"] as? [String: Any],
               let data = try? JSONSerialization.data(withJSONObject: cfgDict, options: []),
               let newCfg = try? JSONDecoder().decode(Config.self, from: data) {
                WatcherManager.shared.config = newCfg
                saveConfig(newCfg)
                WatcherManager.shared.appendLog("\(logTimestamp()) [Config] Settings updated via UI.")
            }
        case "resetStats":
            WatcherManager.shared.sessionRestarts = 0
            WatcherManager.shared.stats = Stats(totalGameRestarts: 0, lastRestartTime: nil)
            saveStats(WatcherManager.shared.stats)
            WatcherManager.shared.appendLog("\(logTimestamp()) [Stats] Restarts counter reset to 0.")
        default:
            break
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var window: NSWindow!
    var webView: WKWebView!
    var bridgeHandler: NativeBridgeHandler!
    var updateTimer: Timer?
    
    // Status Bar & Menu
    var statusItem: NSStatusItem!
    var statusMenuItem: NSMenuItem!
    var toggleWatcherMenuItem: NSMenuItem!
    var showWindowMenuItem: NSMenuItem!
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Build Fixed Non-Resizable Window
        let windowWidth: CGFloat = 1040
        let windowHeight: CGFloat = 720
        let rect = NSRect(x: 100, y: 100, width: windowWidth, height: windowHeight)
        
        window = NSWindow(
            contentRect: rect,
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Roblox Watcher"
        window.center()
        window.delegate = self
        
        // Strictly prevent resizing
        window.minSize = NSSize(width: windowWidth, height: windowHeight)
        window.maxSize = NSSize(width: windowWidth, height: windowHeight)
        window.collectionBehavior = [.fullScreenNone]
        
        // Setup macOS Menu Bar Status Item
        setupStatusBar()
        
        // Request Screen Capture & Accessibility permissions if needed
        if !CGPreflightScreenCaptureAccess() {
            CGRequestScreenCaptureAccess()
        }
        
        // Set macOS App Icon dynamically
        if let iconURL = Bundle.main.url(forResource: "app_icon", withExtension: "png"),
           let iconImg = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = iconImg
        } else if let localIcon = NSImage(contentsOfFile: "Resources/app_icon.png") {
            NSApp.applicationIconImage = localIcon
        }
        
        // Dark titlebar
        window.titlebarAppearsTransparent = true
        window.backgroundColor = NSColor(red: 11/255.0, green: 15/255.0, blue: 23/255.0, alpha: 1.0)
        
        // Configure WKWebView
        let config = WKWebViewConfiguration()
        bridgeHandler = NativeBridgeHandler()
        config.userContentController.add(bridgeHandler, name: "nativeApp")
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        
        webView = WKWebView(frame: window.contentView!.bounds, configuration: config)
        webView.autoresizingMask = [.width, .height]
        bridgeHandler.webView = webView
        
        window.contentView?.addSubview(webView)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        // Load index.html
        loadHTML()
        
        // Prompt for system permissions if missing
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            if !AXIsProcessTrusted() {
                let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
                _ = AXIsProcessTrustedWithOptions(options)
            }
            if !CGPreflightScreenCaptureAccess() {
                CGRequestScreenCaptureAccess()
            }
        }
        
        // Start Periodic UI sync timer
        updateTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.syncUIState()
        }
        
        if ProcessInfo.processInfo.arguments.contains("--start") {
            WatcherManager.shared.start()
        }
    }
    
    func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        let menu = NSMenu()
        
        statusMenuItem = NSMenuItem(title: "Status: Stopped", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)
        
        menu.addItem(NSMenuItem.separator())
        
        toggleWatcherMenuItem = NSMenuItem(title: "Start Watcher", action: #selector(toggleWatcherFromMenu), keyEquivalent: "s")
        toggleWatcherMenuItem.target = self
        menu.addItem(toggleWatcherMenuItem)
        
        showWindowMenuItem = NSMenuItem(title: "Show Window", action: #selector(showWindowFromMenu), keyEquivalent: "w")
        showWindowMenuItem.target = self
        menu.addItem(showWindowMenuItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitAppFromMenu), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        statusItem.menu = menu
        updateStatusBarIcon(isActive: false)
    }
    
    func updateStatusBarIcon(isActive: Bool) {
        let name = isActive ? "menubar_active" : "menubar_inactive"
        var imgURL = Bundle.main.url(forResource: name, withExtension: "png")
        if imgURL == nil {
            let local = URL(fileURLWithPath: "Resources/\(name).png")
            if FileManager.default.fileExists(atPath: local.path) {
                imgURL = local
            }
        }
        
        if let url = imgURL, let image = NSImage(contentsOf: url) {
            image.size = NSSize(width: 18, height: 18)
            image.isTemplate = false // White when inactive, blue when active
            statusItem.button?.image = image
            statusItem.button?.imagePosition = .imageOnly
        }
    }
    
    @objc func toggleWatcherFromMenu() {
        if WatcherManager.shared.isRunning {
            WatcherManager.shared.stop()
        } else {
            WatcherManager.shared.start()
        }
        syncUIState()
    }
    
    @objc func showWindowFromMenu() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @objc func quitAppFromMenu() {
        WatcherManager.shared.stop()
        NSApp.terminate(nil)
    }
    
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        window.orderOut(nil)
        return false
    }
    
    func loadHTML() {
        var htmlURL: URL? = nil
        if let resURL = Bundle.main.url(forResource: "index", withExtension: "html") {
            htmlURL = resURL
        } else {
            let localURL = URL(fileURLWithPath: "Resources/index.html")
            if FileManager.default.fileExists(atPath: localURL.path) {
                htmlURL = localURL
            }
        }
        
        if let url = htmlURL {
            let baseDir = url.deletingLastPathComponent()
            webView.loadFileURL(url, allowingReadAccessTo: baseDir.path.hasPrefix("/Users") ? URL(fileURLWithPath: "/") : baseDir)
        }
    }
    
    func syncUIState() {
        let mgr = WatcherManager.shared
        let robloxInfo = findRobloxProcess()
        let screenshotURL = getScreenshotFileURL()
        
        // Use lightweight JPEG thumbnail to keep evaluateJavaScript fast & responsive
        let base64Img = createThumbnailBase64(from: screenshotURL, maxDimension: 960)
        
        var liveCoords: [String: Int]? = nil
        if let norm = mgr.latestEventNormalizedCoords, let win = findRobloxWindow() {
            let liveX = Int(win.bounds.origin.x + (norm.x * win.bounds.width))
            let liveY = Int(win.bounds.origin.y + (norm.y * win.bounds.height))
            liveCoords = ["x": liveX, "y": liveY]
        }
        
        var antiAfkSecondsRemaining: Int = 0
        if mgr.isRunning && mgr.config.antiAfkEnabled {
            let elapsed = Date().timeIntervalSince(mgr.lastAntiAfkClickTimestamp)
            antiAfkSecondsRemaining = max(0, Int(mgr.config.antiAfkIntervalSeconds - elapsed))
        }
        
        let state: [String: Any] = [
            "running": mgr.isRunning,
            "robloxPid": robloxInfo?.pid as Any,
            "placeId": (robloxInfo?.placeId ?? mgr.config.placeId) as Any,
            "restarts": mgr.sessionRestarts,
            "totalRestarts": mgr.stats.totalGameRestarts,
            "logs": mgr.getRecentLogs(),
            "screenshotBase64": base64Img as Any,
            "autoTeleportToEvent": mgr.config.autoTeleportToEvent,
            "antiAfkEnabled": mgr.config.antiAfkEnabled,
            "antiAfkCountdown": antiAfkSecondsRemaining,
            "eventKeywords": mgr.config.eventTargetKeywords,
            "eventIconBase64": mgr.latestEventCropBase64 as Any,
            "eventCoords": liveCoords as Any,
            "eventMatchedText": mgr.latestEventMatchedText as Any,
            "appVersion": getAppVersion()
        ]
        
        if let jsonData = try? JSONSerialization.data(withJSONObject: state, options: []),
           let jsonStr = String(data: jsonData, encoding: .utf8) {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.updateStatusBarIcon(isActive: mgr.isRunning)
                self.statusMenuItem.title = mgr.isRunning ? "Status: Active (PID \(robloxInfo?.pid ?? 0))" : "Status: Stopped"
                self.toggleWatcherMenuItem.title = mgr.isRunning ? "Stop Watcher" : "Start Watcher"
                self.webView.evaluateJavaScript("window.updateUIState(\(jsonStr));", completionHandler: nil)
            }
        }
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false // Keeps running in the menu bar
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        return true
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        WatcherManager.shared.stop()
    }
}

// MARK: - Single Instance Enforcement
func enforceSingleInstance() {
    let lockPath = NSTemporaryDirectory() + "roblox_watcher_gui.lock"
    let lockFd = open(lockPath, O_CREAT | O_RDWR, 0o666)
    if lockFd >= 0 {
        if flock(lockFd, LOCK_EX | LOCK_NB) != 0 {
            let myPid = ProcessInfo.processInfo.processIdentifier
            let otherApps = NSWorkspace.shared.runningApplications.filter {
                $0.processIdentifier != myPid && (
                    $0.bundleIdentifier == "xyz.ps99clan.robloxwatcher" ||
                    $0.localizedName == "Roblox Watcher" ||
                    $0.executableURL?.lastPathComponent == "RobloxWatcher"
                )
            }
            if let existing = otherApps.first {
                existing.activate()
            }
            exit(0)
        }
        
        ftruncate(lockFd, 0)
        let pidString = "\(ProcessInfo.processInfo.processIdentifier)\n"
        pidString.withCString { ptr in
            _ = write(lockFd, ptr, strlen(ptr))
        }
    }
}

// MARK: - App Entrypoint
enforceSingleInstance()
let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
