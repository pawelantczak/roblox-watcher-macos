import Foundation
import Vision
import AppKit
import CoreGraphics
import ImageIO

// MARK: - Configuration
struct Config: Codable {
    var checkIntervalSeconds: Double = 5.0
    var reconnectCooldownSeconds: Double = 30.0
    var placeId: String? = nil
    var vipServerUrl: String? = nil
    var autoClickReconnect: Bool = true
    var autoRelaunchOnKick: Bool = true
    var autoTeleportToEvent: Bool = true
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
}

struct Stats: Codable {
    var totalGameRestarts: Int = 0
    var lastRestartTime: String? = nil
}

func loadStats() -> Stats {
    let statsPath = "stats.json"
    if let data = try? Data(contentsOf: URL(fileURLWithPath: statsPath)),
       let stats = try? JSONDecoder().decode(Stats.self, from: data) {
        return stats
    }
    return Stats()
}

func saveStats(_ stats: Stats) {
    let statsPath = "stats.json"
    let encoder = JSONEncoder()
    encoder.outputFormatting = .prettyPrinted
    if let data = try? encoder.encode(stats) {
        try? data.write(to: URL(fileURLWithPath: statsPath))
    }
}

func loadConfig() -> Config {
    let configPath = "config.json"
    let fileManager = FileManager.default
    if fileManager.fileExists(atPath: configPath),
       let data = try? Data(contentsOf: URL(fileURLWithPath: configPath)),
       let config = try? JSONDecoder().decode(Config.self, from: data) {
        return config
    }
    let defaultConfig = Config()
    if let encoded = try? JSONEncoder().encode(defaultConfig) {
        try? encoded.write(to: URL(fileURLWithPath: configPath))
    }
    return defaultConfig
}

func getScreenshotPath() -> String {
    if let execURL = Bundle.main.executableURL {
        let dir = execURL.deletingLastPathComponent()
        return dir.appendingPathComponent("latest_capture.png").path
    }
    return (FileManager.default.currentDirectoryPath as NSString).appendingPathComponent("latest_capture.png")
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
            
            // Extract placeId=123456
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
    usleep(250_000)
}

// MARK: - Permissions Helper
func checkScreenRecordingPermission() -> Bool {
    if CGPreflightScreenCaptureAccess() {
        return true
    }
    print("\n------------------------------------------------------------")
    print("\(logTimestamp()) [PERMISSION ERROR] macOS Screen Recording permission is NOT granted!")
    print("\(logTimestamp()) macOS security censors all application windows to black pixels.")
    print("\(logTimestamp()) Requesting permission and opening System Settings...")
    print("------------------------------------------------------------\n")
    _ = CGRequestScreenCaptureAccess()
    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
        NSWorkspace.shared.open(url)
    }
    return false
}

// MARK: - Screen OCR & Detection
struct RobloxWindowInfo {
    let windowId: CGWindowID
    let bounds: CGRect
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
            if let boundsDict = win[kCGWindowBounds as String] as? [String: Any],
               let rect = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) {
                if rect.width > 200 && rect.height > 200 {
                    return RobloxWindowInfo(windowId: CGWindowID(id), bounds: rect)
                }
            }
        }
    }
    return nil
}

struct DetectedText {
    let text: String
    let boundingBox: CGRect // Normalized (0...1) from bottom-left
}

func captureRobloxWindow(savePath: String) -> (image: CGImage, bounds: CGRect)? {
    let task = Process()
    task.launchPath = "/usr/sbin/screencapture"
    
    var windowBounds = CGRect(x: 0, y: 0, width: 2560, height: 1440)
    if let win = findRobloxWindow() {
        task.arguments = ["-x", "-o", "-l", "\(win.windowId)", savePath]
        windowBounds = win.bounds
    } else {
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

// MARK: - Reconnection Actions
func clickScreen(normalizedBox: CGRect, label: String = "Target") {
    guard let mainScreen = NSScreen.main else { return }
    let screenWidth = Double(mainScreen.frame.width)
    let screenHeight = Double(mainScreen.frame.height)
    
    let clickX = Double(normalizedBox.midX) * screenWidth
    let clickY = (1.0 - Double(normalizedBox.midY)) * screenHeight
    clickScreenAtPoint(point: CGPoint(x: clickX, y: clickY), label: label)
}

func clickScreenAtPoint(point: CGPoint, label: String = "Target") {
    print("\(logTimestamp()) [Action] Focusing Roblox & clicking \(label) at screen coordinates (\(Int(point.x)), \(Int(point.y)))...")
    activateRoblox()
    
    // 1. Move hardware cursor & notify Roblox of mouse hover state
    CGWarpMouseCursorPosition(point)
    if let moveEvent = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left) {
        moveEvent.post(tap: .cghidEventTap)
    }
    usleep(200_000) // 200ms hover time
    
    // 2. Click 1: Activates the Roblox window (eats background focus)
    if let down1 = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left),
       let up1 = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left) {
        down1.post(tap: .cghidEventTap)
        usleep(80_000)
        up1.post(tap: .cghidEventTap)
    }
    
    // 3. Pause for Roblox window activation to complete
    usleep(250_000) // 250ms
    
    // 4. Click 2: Actually triggers the in-game action / movement
    if let down2 = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left),
       let up2 = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left) {
        down2.post(tap: .cghidEventTap)
        usleep(80_000)
        up2.post(tap: .cghidEventTap)
    }
    
    print("\(logTimestamp()) [Success] Two-click sequence dispatched to \(label) (1st activate, 2nd action).")
}

func killAndRelaunchGame(placeId: String?, vipUrl: String?) {
    print("\(logTimestamp()) [Action] Force-closing stale RobloxPlayer...")
    
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
        print("\(logTimestamp()) [Error] No placeId or VIP link available to relaunch game.")
        return
    }
    
    print("\(logTimestamp()) [Action] Launching: \(launchUrl)")
    let openTask = Process()
    openTask.launchPath = "/usr/bin/open"
    openTask.arguments = [launchUrl]
    try? openTask.run()
    openTask.waitUntilExit()
    print("\(logTimestamp()) [Success] Rejoin request sent to macOS system.")
}

func teleportToEventArea(screenshotPath: String, targetKeywords: [String], maxWaitSeconds: Int = 50) {
    let keywordsDisplay = targetKeywords.joined(separator: ", ")
    print("\n\(logTimestamp()) [Event Nav] Waiting for game to load before teleporting (targets: [\(keywordsDisplay)])...")
    
    let startTime = Date()
    while Date().timeIntervalSince(startTime) < Double(maxWaitSeconds) {
        var foundAndClicked = false
        autoreleasepool {
            Thread.sleep(forTimeInterval: 2.5)
            
            guard let (screenImage, winBounds) = captureRobloxWindow(savePath: screenshotPath) else { return }
            let (detectedItems, _) = scanScreenForText(image: screenImage)
            
            // Check if any configured keyword matches an icon on the left side (x < 0.35)
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
                    
                    // The clickable icon button sits ~45px above the text label
                    let iconPoint = CGPoint(x: textX, y: max(currentBounds.origin.y, textY - 45))
                    
                    print("\(logTimestamp()) [Event Nav] Detected \"\(item.text)\" on Roblox window! Dispatching clicks...")
                    clickScreenAtPoint(point: iconPoint, label: "Event Icon Graphic")
                    print("\(logTimestamp()) [Event Nav] Teleport dispatched successfully!\n")
                    foundAndClicked = true
                    return
                }
            }
        }
        if foundAndClicked { return }
        
        let elapsed = Int(Date().timeIntervalSince(startTime))
        print("\r[Event Nav] Waiting for event icon [\(keywordsDisplay)] to appear (\(elapsed)/\(maxWaitSeconds)s)... ", terminator: "")
        fflush(stdout)
    }
    
    print("\n\(logTimestamp()) [Event Nav] Timeout: Event icon [\(keywordsDisplay)] not detected on Roblox window. Skipping click to prevent accidental inputs.\n")
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

// MARK: - Main Loop
func main() {
    let version = getAppVersion()
    print("==================================================")
    print("   ROBLOX DISCONNECT WATCHER & AUTO-REJOIN v\(version)")
    print("==================================================")
    
    let config = loadConfig()
    var stats = loadStats()
    var sessionRestarts = 0
    let screenshotPath = getScreenshotPath()
    var lastKnownPlaceId: String? = config.placeId
    var lastActionTimestamp: Date = Date.distantPast
    
    print("\(logTimestamp()) [Config] Check Interval: \(config.checkIntervalSeconds)s | Cooldown: \(config.reconnectCooldownSeconds)s")
    print("\(logTimestamp()) [Config] Screenshot Path: \(screenshotPath)")
    print("\(logTimestamp()) [Config] Reconnect Button Text: \"\(config.reconnectButtonText)\"")
    print("\(logTimestamp()) [Config] Disconnect Keywords: \(config.disconnectKeywords.count) phrases")
    print("\(logTimestamp()) [Config] Event Target Keywords: [\(config.eventTargetKeywords.joined(separator: ", "))]")
    print("\(logTimestamp()) [Config] Auto Teleport to Event: \(config.autoTeleportToEvent)")
    print("\(logTimestamp()) [Stats] Total Restarts Recorded: \(stats.totalGameRestarts)" + (stats.lastRestartTime != nil ? " (Last: \(stats.lastRestartTime!))" : ""))
    if let pId = lastKnownPlaceId {
        print("\(logTimestamp()) [Config] Target Place ID: \(pId)")
    }
    print("\(logTimestamp()) [Status] Watcher is actively monitoring screen.\n")
    
    if !checkScreenRecordingPermission() {
        print("\(logTimestamp()) [Notice] Waiting for Screen Recording permission to be granted in System Settings...\n")
    }
    
    if CommandLine.arguments.contains("--test-teleport") {
        print("\(logTimestamp()) [Test Mode] Executing immediate test teleport click...")
        teleportToEventArea(screenshotPath: screenshotPath, targetKeywords: config.eventTargetKeywords, maxWaitSeconds: 10)
        exit(0)
    }
    
    while true {
        autoreleasepool {
            let now = Date()
            
            // 1. Process Check
            if let currentRoblox = findRobloxProcess() {
                if let pid = currentRoblox.placeId {
                    if pid != lastKnownPlaceId {
                        lastKnownPlaceId = pid
                        print("\(logTimestamp()) [Process] Active Roblox Place ID updated: \(pid)")
                    }
                }
                print("\(logTimestamp()) [Process] Roblox is running (PID: \(currentRoblox.pid), PlaceID: \(lastKnownPlaceId ?? "unknown")) | Restarts: \(sessionRestarts)")
            } else {
                print("\(logTimestamp()) [Process] RobloxPlayer is not currently running.")
            }
            
            // 2. Cooldown Evaluation
            let elapsed = now.timeIntervalSince(lastActionTimestamp)
            let inCooldown = elapsed < config.reconnectCooldownSeconds
            
            if inCooldown {
                let remainingCooldown = Int(config.reconnectCooldownSeconds - elapsed)
                print("\(logTimestamp()) [Cooldown] Reconnect cooldown active (\(remainingCooldown)s remaining). Skipping screen OCR.")
            } else {
                // 3. Screen Capture & OCR (Roblox Window ONLY)
                if let (screenImage, winBounds) = captureRobloxWindow(savePath: screenshotPath) {
                    print("\(logTimestamp()) [Screen] Roblox window captured -> \(screenshotPath) (\(Int(winBounds.width))x\(Int(winBounds.height))px)")
                    
                    let (detectedItems, durationMs) = scanScreenForText(image: screenImage)
                    print("\(logTimestamp()) [OCR] Scanned \(detectedItems.count) text segments in \(String(format: "%.1f", durationMs))ms")
                    
                    var isDisconnected = false
                    var reconnectBox: CGRect? = nil
                    var matchedKeyword = ""
                    
                    let targetButton = config.reconnectButtonText.trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    for item in detectedItems {
                        let trimmed = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
                        let lower = trimmed.lowercased()
                        
                        // Match button explicitly from config
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
                        
                        print("\n\(logTimestamp()) [ALERT] Disconnect detected on Roblox window! Matched: \(matchedKeyword)")
                        print("\(logTimestamp()) [Stats] Total Game Restarts Count: \(stats.totalGameRestarts)")
                        lastActionTimestamp = now
                        
                        if let box = reconnectBox, config.autoClickReconnect {
                            print("\(logTimestamp()) [Decision] Identified \"\(targetButton)\" button. Dispatching click...")
                            let clickX = winBounds.origin.x + Double(box.midX) * winBounds.width
                            let clickY = winBounds.origin.y + (1.0 - Double(box.midY)) * winBounds.height
                            clickScreenAtPoint(point: CGPoint(x: clickX, y: clickY), label: "\(targetButton) Button")
                            if config.autoTeleportToEvent {
                                teleportToEventArea(screenshotPath: screenshotPath, targetKeywords: config.eventTargetKeywords)
                            }
                        } else if config.autoRelaunchOnKick {
                            print("\(logTimestamp()) [Decision] \"\(targetButton)\" button not found. Relaunching game...")
                            killAndRelaunchGame(placeId: lastKnownPlaceId, vipUrl: config.vipServerUrl)
                            if config.autoTeleportToEvent {
                                teleportToEventArea(screenshotPath: screenshotPath, targetKeywords: config.eventTargetKeywords)
                            }
                        }
                    } else {
                        if let firstThree = detectedItems.prefix(3).map({ "\"\($0.text)\"" }) as [String]?, !firstThree.isEmpty {
                            print("\(logTimestamp()) [Check] Game healthy. Screen samples: [\(firstThree.joined(separator: ", "))]")
                        } else {
                            print("\(logTimestamp()) [Check] Game healthy. No disconnect dialog present.")
                        }
                    }
                } else {
                    print("\(logTimestamp()) [Warning] Failed to capture screen. Verify Screen Recording permissions.")
                }
            }
        }
        
        // 4. Countdown to Next Capture
        let totalSeconds = max(1, Int(config.checkIntervalSeconds))
        for sec in stride(from: totalSeconds, through: 1, by: -1) {
            print("\r[Countdown] Next screen capture in \(sec)s... ", terminator: "")
            fflush(stdout)
            Thread.sleep(forTimeInterval: 1.0)
        }
        print("\r                                                 \r", terminator: "")
        fflush(stdout)
    }
}

main()
