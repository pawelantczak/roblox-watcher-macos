import Foundation
import CoreGraphics

// MARK: - Minimal Lightweight Test Harness

var testCount = 0
var failureCount = 0

func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String = "", file: String = #file, line: Int = #line) {
    testCount += 1
    if actual != expected {
        failureCount += 1
        print("❌ Assertion Failed at \(file):\(line): expected [\(expected)], got [\(actual)]. \(message)")
    }
}

func assertTrue(_ condition: Bool, _ message: String = "", file: String = #file, line: Int = #line) {
    testCount += 1
    if !condition {
        failureCount += 1
        print("❌ Assertion Failed at \(file):\(line): condition is false. \(message)")
    }
}

func assertFalse(_ condition: Bool, _ message: String = "", file: String = #file, line: Int = #line) {
    testCount += 1
    if condition {
        failureCount += 1
        print("❌ Assertion Failed at \(file):\(line): condition is true (expected false). \(message)")
    }
}

// MARK: - Test Cases

func testConfigDefaultsAndSerialization() {
    print("▶ Running: testConfigDefaultsAndSerialization")
    let cfg = Config()
    assertEqual(cfg.checkIntervalSeconds, 5.0)
    assertEqual(cfg.reconnectCooldownSeconds, 30.0)
    assertTrue(cfg.autoClickReconnect)
    assertTrue(cfg.autoRelaunchOnKick)
    assertTrue(cfg.autoTeleportToEvent)
    assertTrue(cfg.antiAfkEnabled)
    assertEqual(cfg.antiAfkIntervalSeconds, 600.0)
    assertFalse(cfg.webServerEnabled)
    assertEqual(cfg.webServerPort, 8765)
    assertTrue(cfg.ignorePhrases.contains("voice chat"))
    assertTrue(cfg.ignorePhrases.contains("voice"))
    
    // Partial JSON decode test (legacy config without new fields)
    let json = """
    {
        "checkIntervalSeconds": 10.0,
        "placeId": "12345"
    }
    """.data(using: .utf8)!
    
    guard let decoded = try? JSONDecoder().decode(Config.self, from: json) else {
        failureCount += 1
        print("❌ Failed to decode partial JSON")
        return
    }
    assertEqual(decoded.checkIntervalSeconds, 10.0)
    assertEqual(decoded.placeId, "12345")
    assertEqual(decoded.antiAfkIntervalSeconds, 600.0) // Uses default
    assertTrue(decoded.autoTeleportToEvent) // Uses default
    assertTrue(decoded.ignorePhrases.contains("voice"))
}

func testFatalDisconnectDetection() {
    print("▶ Running: testFatalDisconnectDetection")
    let cfg = Config()
    
    let fatalPhrases = [
        "Disconnected from server",
        "Lost connection to the game",
        "Error Code: 277",
        "Error Code: 279",
        "error code: 267",
        "The server was shut down.",
        "Server has closed",
        "Please reconnect"
    ]
    
    for phrase in fatalPhrases {
        assertTrue(
            WatcherClassifier.isFatalDisconnect(text: phrase, disconnectKeywords: cfg.disconnectKeywords, ignorePhrases: cfg.ignorePhrases),
            "Expected '\(phrase)' to be recognized as fatal disconnect"
        )
    }
    
    // Innocent chat/normal messages should not trigger
    let innocentPhrases = [
        "Hello everyone!",
        "Trading pets in the plaza",
        "Huge cat obtained!",
        "Level 99 reached"
    ]
    
    for phrase in innocentPhrases {
        assertFalse(
            WatcherClassifier.isFatalDisconnect(text: phrase, disconnectKeywords: cfg.disconnectKeywords, ignorePhrases: cfg.ignorePhrases),
            "Expected '\(phrase)' to NOT trigger disconnect"
        )
    }
}

func testVoiceChatNonFatalIgnoreFilter() {
    print("▶ Running: testVoiceChatNonFatalIgnoreFilter")
    let cfg = Config()
    
    // Non-fatal voice chat disconnects MUST NOT trigger game reconnect
    let voiceChatToasts = [
        "You've disconnected from Voice Chat",
        "Disconnected from Voice Chat (Error 277)",
        "Voice chat connection lost",
        "Voice Chat is currently unavailable"
    ]
    
    for toast in voiceChatToasts {
        assertTrue(
            WatcherClassifier.isIgnored(text: toast, ignorePhrases: cfg.ignorePhrases),
            "Expected '\(toast)' to be ignored"
        )
        assertFalse(
            WatcherClassifier.isFatalDisconnect(text: toast, disconnectKeywords: cfg.disconnectKeywords, ignorePhrases: cfg.ignorePhrases),
            "Expected '\(toast)' to NOT be classified as fatal disconnect"
        )
    }
}

func testReconnectButtonDetection() {
    print("▶ Running: testReconnectButtonDetection")
    let cfg = Config()
    
    let items = [
        DetectedText(text: "Something Else", boundingBox: CGRect(x: 0.1, y: 0.2, width: 0.1, height: 0.05)),
        DetectedText(text: "You've disconnected from Voice Chat", boundingBox: CGRect(x: 0.5, y: 0.9, width: 0.3, height: 0.05)),
        DetectedText(text: "Reconnect", boundingBox: CGRect(x: 0.45, y: 0.4, width: 0.1, height: 0.05)),
        DetectedText(text: "Leave", boundingBox: CGRect(x: 0.6, y: 0.4, width: 0.1, height: 0.05))
    ]
    
    let btn = WatcherClassifier.findReconnectButton(in: items, buttonText: cfg.reconnectButtonText, ignorePhrases: cfg.ignorePhrases)
    assertTrue(btn != nil, "Expected to find Reconnect button")
    assertEqual(btn?.text, "Reconnect")
    assertEqual(btn?.boundingBox.origin.x, 0.45)
}

func testEventTargetDetectionBoundingBox() {
    print("▶ Running: testEventTargetDetectionBoundingBox")
    let cfg = Config()
    
    // Single-line detection (origin.x < 0.35)
    let leftPanelEvent = DetectedText(text: "Pumpkin Event", boundingBox: CGRect(x: 0.05, y: 0.5, width: 0.1, height: 0.08))
    let rightPanelEvent = DetectedText(text: "Tycoon Boost", boundingBox: CGRect(x: 0.75, y: 0.5, width: 0.1, height: 0.08))
    let leftNonEvent = DetectedText(text: "Settings", boundingBox: CGRect(x: 0.05, y: 0.8, width: 0.1, height: 0.05))
    
    let detectedLeft = WatcherClassifier.findEventTarget(in: [leftPanelEvent, rightPanelEvent, leftNonEvent], keywords: cfg.eventTargetKeywords)
    assertTrue(detectedLeft != nil, "Expected to find left panel event icon")
    assertEqual(detectedLeft?.text, "Pumpkin Event")
    assertEqual(detectedLeft?.boundingBox.midX, 0.10)
    assertEqual(detectedLeft?.boundingBox.midY, 0.54)
    
    // Multi-line detection: vertical center between first line top and last line bottom
    let line1 = DetectedText(text: "Pumpkin", boundingBox: CGRect(x: 0.05, y: 0.52, width: 0.08, height: 0.04)) // maxY: 0.56
    let line2 = DetectedText(text: "Tycoon", boundingBox: CGRect(x: 0.06, y: 0.46, width: 0.06, height: 0.04))  // minY: 0.46
    let multiDetected = WatcherClassifier.findEventTarget(in: [line1, line2], keywords: cfg.eventTargetKeywords)
    assertTrue(multiDetected != nil, "Expected multi-line event target to be detected")
    assertEqual(multiDetected?.text, "Pumpkin Tycoon")
    // Expected midY: (0.56 + 0.46) / 2.0 = 0.51
    assertEqual(Double(multiDetected!.boundingBox.midY), 0.51)
    
    // If only right-side target exists, it should be ignored
    let detectedRight = WatcherClassifier.findEventTarget(in: [rightPanelEvent, leftNonEvent], keywords: cfg.eventTargetKeywords)
    assertTrue(detectedRight == nil, "Right-side target should be ignored (not in event panel)")
}

func testPlaceIdParsing() {
    print("▶ Running: testPlaceIdParsing")
    let cmdLine1 = "/Applications/Roblox.app/Contents/MacOS/RobloxPlayer -placeId=8737899170 -launchtime=12345"
    assertEqual(WatcherUtils.parsePlaceId(from: cmdLine1), "8737899170")
    
    let cmdLine2 = "RobloxPlayer -ticket xyz -placeId=999888777"
    assertEqual(WatcherUtils.parsePlaceId(from: cmdLine2), "999888777")
    
    let cmdLineNoId = "RobloxPlayer -nothingHere"
    assertEqual(WatcherUtils.parsePlaceId(from: cmdLineNoId), nil)
}

func testAntiAfkCountdownFormatting() {
    print("▶ Running: testAntiAfkCountdownFormatting")
    assertEqual(WatcherUtils.formatCountdown(seconds: 300), "in 5m 00s")
    assertEqual(WatcherUtils.formatCountdown(seconds: 299), "in 4m 59s")
    assertEqual(WatcherUtils.formatCountdown(seconds: 65), "in 1m 05s")
    assertEqual(WatcherUtils.formatCountdown(seconds: 45), "in 45s")
    assertEqual(WatcherUtils.formatCountdown(seconds: 0), "Clicking...")
    assertEqual(WatcherUtils.formatCountdown(seconds: -1), "Clicking...")
}

func testSingleInstanceKernelLock() {
    print("▶ Running: testSingleInstanceKernelLock")
    let testLockPath = NSTemporaryDirectory() + "test_roblox_watcher_\(UUID().uuidString).lock"
    defer { unlink(testLockPath) }
    
    // First lock acquisition should succeed
    guard let fd1 = WatcherUtils.acquireKernelLock(lockFilePath: testLockPath) else {
        failureCount += 1
        print("❌ Failed to acquire primary lock on \(testLockPath)")
        return
    }
    assertTrue(fd1 >= 0)
    
    // Second lock acquisition while first is held MUST fail
    let fd2 = WatcherUtils.acquireKernelLock(lockFilePath: testLockPath)
    assertTrue(fd2 == nil, "Second lock acquisition should fail with nil while first lock is held")
    
    // Closing primary lock releases it
    close(fd1)
    
    // Third acquisition should now succeed
    if let fd3 = WatcherUtils.acquireKernelLock(lockFilePath: testLockPath) {
        assertTrue(fd3 >= 0, "Third acquisition should succeed after release")
        close(fd3)
    } else {
        failureCount += 1
        print("❌ Failed to acquire lock after release")
    }
}

func testPowerServiceSleepPrevention() {
    print("▶ Running: testPowerServiceSleepPrevention")
    let power = PowerService.shared
    
    // Initial state
    assertFalse(power.isHoldingAssertion, "PowerService should not hold assertion initially")
    
    // Enable
    let acquired = power.enableSleepPrevention(reason: "Unit Test Assertion")
    assertTrue(acquired, "enableSleepPrevention should return true")
    assertTrue(power.isHoldingAssertion, "isHoldingAssertion should be true after enable")
    
    // Redundant enable should succeed gracefully
    let redundantAcquired = power.enableSleepPrevention(reason: "Unit Test Redundant")
    assertTrue(redundantAcquired, "Redundant enable should return true")
    assertTrue(power.isHoldingAssertion)
    
    // Disable
    let released = power.disableSleepPrevention()
    assertTrue(released, "disableSleepPrevention should return true")
    assertFalse(power.isHoldingAssertion, "isHoldingAssertion should be false after disable")
    
    // Redundant disable should succeed gracefully
    let redundantReleased = power.disableSleepPrevention()
    assertTrue(redundantReleased, "Redundant disable should return true")
    assertFalse(power.isHoldingAssertion)
}

func testUpdateServiceSemverComparison() {
    print("▶ Running: testUpdateServiceSemverComparison")
    assertTrue(UpdateService.isNewerVersion(remote: "1.2.0", current: "1.1.0"))
    assertTrue(UpdateService.isNewerVersion(remote: "v1.2.0", current: "1.1.0"))
    assertTrue(UpdateService.isNewerVersion(remote: "2.0.0", current: "1.9.9"))
    assertTrue(UpdateService.isNewerVersion(remote: "1.1.1", current: "1.1.0"))
    assertFalse(UpdateService.isNewerVersion(remote: "1.1.0", current: "1.1.0"))
    assertFalse(UpdateService.isNewerVersion(remote: "v1.1.0", current: "1.1.0"))
    assertFalse(UpdateService.isNewerVersion(remote: "1.0.9", current: "1.1.0"))
    assertFalse(UpdateService.isNewerVersion(remote: "0.9.0", current: "1.0.0"))
    assertFalse(UpdateService.isNewerVersion(remote: "invalid", current: "1.0.0"))
}

func testLogPersistence() {
    print("▶ Running: testLogPersistence")
    let logUrl = StorageService.getLogFileURL()
    assertTrue(logUrl.path.hasSuffix("watcher.jsonl"))
    
    let testLine = "[Test] Persistent log verification \(UUID().uuidString)"
    let testBase64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
    StorageService.appendLogToFile(testLine, eventCropBase64: testBase64)
    Thread.sleep(forTimeInterval: 0.15)
    
    let content = (try? String(contentsOf: logUrl, encoding: .utf8)) ?? ""
    assertTrue(content.contains(testLine), "Expected watcher.jsonl to contain written log line")
    assertTrue(content.contains(testBase64), "Expected watcher.jsonl to contain event crop base64")
    
    // Verify JSON parsing of the logged line
    let matchingLine = content.components(separatedBy: "\n").filter { $0.contains(testLine) }.last ?? ""
    let record = try? JSONDecoder().decode(LogRecord.self, from: Data(matchingLine.utf8))
    assertTrue(record != nil, "Expected matching line in watcher.jsonl to parse as valid LogRecord")
    assertEqual(record?.message, testLine)
    assertEqual(record?.eventCropBase64, testBase64)
    
    // Verify exportLogFile copies the full file
    let tempExportURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("test_export_\(UUID().uuidString).jsonl")
    let exportSuccess = StorageService.exportLogFile(to: tempExportURL)
    assertTrue(exportSuccess, "Expected exportLogFile to succeed")
    let exportedContent = (try? String(contentsOf: tempExportURL, encoding: .utf8)) ?? ""
    assertTrue(exportedContent.contains(testLine), "Exported file should contain all logged lines")
    try? FileManager.default.removeItem(at: tempExportURL)
}

func testWebServerService() {
    print("▶ Running: testWebServerService")
    let ip = WebServerService.getLocalIP()
    assertTrue(ip != nil && !ip!.isEmpty, "Expected getLocalIP to return a non-empty IP address")
    
    let server = WebServerService.shared
    server.start(port: 18765)
    Thread.sleep(forTimeInterval: 0.15)
    assertTrue(server.isRunning, "Expected WebServer to be running")
    assertEqual(server.port, 18765)
    
    // Broadcast state test
    server.broadcastState("{\"test\": true}")
    server.stop()
    Thread.sleep(forTimeInterval: 0.15)
    assertFalse(server.isRunning, "Expected WebServer to be stopped")
}

// MARK: - Main Test Runner Execution

@main
struct TestRunner {
    static func main() {
        print("==========================================")
        print("      Roblox Watcher Unit Test Suite      ")
        print("==========================================")
        let start = DispatchTime.now()
        
        testConfigDefaultsAndSerialization()
        testFatalDisconnectDetection()
        testVoiceChatNonFatalIgnoreFilter()
        testReconnectButtonDetection()
        testEventTargetDetectionBoundingBox()
        testPlaceIdParsing()
        testAntiAfkCountdownFormatting()
        testSingleInstanceKernelLock()
        testPowerServiceSleepPrevention()
        testUpdateServiceSemverComparison()
        testLogPersistence()
        testWebServerService()
        
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000.0
        print("==========================================")
        if failureCount == 0 {
            print("✅ ALL \(testCount) ASSERTIONS PASSED in \(String(format: "%.1f", elapsed))ms!")
            exit(0)
        } else {
            print("❌ \(failureCount) of \(testCount) ASSERTIONS FAILED in \(String(format: "%.1f", elapsed))ms!")
            exit(1)
        }
    }
}
