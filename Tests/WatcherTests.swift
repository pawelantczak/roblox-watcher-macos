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
    assertEqual(cfg.antiAfkIntervalSeconds, 300.0)
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
    assertEqual(decoded.antiAfkIntervalSeconds, 300.0) // Uses default
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
    
    // Event icons must be on the left panel (origin.x < 0.35)
    let leftPanelEvent = DetectedText(text: "Pumpkin Event", boundingBox: CGRect(x: 0.05, y: 0.5, width: 0.1, height: 0.08))
    let rightPanelEvent = DetectedText(text: "Tycoon Boost", boundingBox: CGRect(x: 0.75, y: 0.5, width: 0.1, height: 0.08))
    let leftNonEvent = DetectedText(text: "Settings", boundingBox: CGRect(x: 0.05, y: 0.8, width: 0.1, height: 0.05))
    
    let detectedLeft = WatcherClassifier.findEventTarget(in: [leftPanelEvent, rightPanelEvent, leftNonEvent], keywords: cfg.eventTargetKeywords)
    assertTrue(detectedLeft != nil, "Expected to find left panel event icon")
    assertEqual(detectedLeft?.text, "Pumpkin Event")
    
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
