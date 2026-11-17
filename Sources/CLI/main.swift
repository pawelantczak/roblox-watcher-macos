import Foundation
import CoreGraphics

// MARK: - Roblox Watcher CLI Daemon

func enforceSingleCLIInstance() {
    let lockPath = NSTemporaryDirectory() + "roblox_watcher_cli.lock"
    guard let fd = LockManager.acquireLock(lockFilePath: lockPath) else {
        print("[Error] Another instance of roblox-watcher CLI is already running. Exiting.")
        exit(1)
    }
    ftruncate(fd, 0)
    let pidString = "\(ProcessInfo.processInfo.processIdentifier)\n"
    pidString.withCString { ptr in
        _ = write(fd, ptr, strlen(ptr))
    }
}

func main() {
    enforceSingleCLIInstance()
    let version = StorageService.getAppVersion()
    print("==================================================")
    print("   ROBLOX DISCONNECT WATCHER & AUTO-REJOIN v\(version)")
    print("==================================================")
    
    let config = StorageService.loadConfig()
    var stats = StorageService.loadStats()
    var sessionRestarts = 0
    let screenshotPath = StorageService.getScreenshotFileURL().path
    var lastKnownPlaceId: String? = config.placeId
    var lastActionTimestamp: Date = Date.distantPast
    var lastAntiAfkClickTimestamp: Date = Date()
    
    let logTime = WindowService.logTimestamp
    
    print("\(logTime()) [Config] Check Interval: \(config.checkIntervalSeconds)s | Cooldown: \(config.reconnectCooldownSeconds)s")
    print("\(logTime()) [Config] Screenshot Path: \(screenshotPath)")
    print("\(logTime()) [Config] Reconnect Button Text: \"\(config.reconnectButtonText)\"")
    print("\(logTime()) [Config] Disconnect Keywords: \(config.disconnectKeywords.count) phrases")
    print("\(logTime()) [Config] Event Target Keywords: [\(config.eventTargetKeywords.joined(separator: ", "))]")
    print("\(logTime()) [Config] Auto Teleport to Event: \(config.autoTeleportToEvent)")
    print("\(logTime()) [Stats] Total Restarts Recorded: \(stats.totalGameRestarts)" + (stats.lastRestartTime != nil ? " (Last: \(stats.lastRestartTime!))" : ""))
    if let pId = lastKnownPlaceId {
        print("\(logTime()) [Config] Target Place ID: \(pId)")
    }
    print("\(logTime()) [Status] Watcher is actively monitoring screen.\n")
    
    if !WindowService.checkScreenRecordingPermission() {
        print("\(logTime()) [Notice] Waiting for Screen Recording permission to be granted in System Settings...\n")
    }
    
    if CommandLine.arguments.contains("--test-teleport") {
        print("\(logTime()) [Test Mode] Executing immediate test teleport click...")
        GameService.teleportToEventArea(screenshotPath: screenshotPath, targetKeywords: config.eventTargetKeywords, maxWaitSeconds: 10)
        exit(0)
    }
    
    while true {
        autoreleasepool {
            let now = Date()
            
            // 1. Process Check
            if let currentRoblox = WindowService.findRobloxProcess() {
                if let pid = currentRoblox.placeId {
                    if pid != lastKnownPlaceId {
                        lastKnownPlaceId = pid
                        print("\(logTime()) [Process] Active Roblox Place ID updated: \(pid)")
                    }
                }
                print("\(logTime()) [Process] Roblox is running (PID: \(currentRoblox.pid), PlaceID: \(lastKnownPlaceId ?? "unknown")) | Restarts: \(sessionRestarts)")
            } else {
                print("\(logTime()) [Process] RobloxPlayer is not currently running.")
            }
            
            // 2. Cooldown Evaluation
            let elapsed = now.timeIntervalSince(lastActionTimestamp)
            let inCooldown = elapsed < config.reconnectCooldownSeconds
            
            if inCooldown {
                let remainingCooldown = Int(config.reconnectCooldownSeconds - elapsed)
                print("\(logTime()) [Cooldown] Reconnect cooldown active (\(remainingCooldown)s remaining). Skipping screen OCR.")
            } else {
                // 3. Screen Capture & OCR (Roblox Window ONLY)
                if let (screenImage, winBounds) = VisionService.captureRobloxWindow(savePath: screenshotPath) {
                    print("\(logTime()) [Screen] Roblox window captured -> \(screenshotPath) (\(Int(winBounds.width))x\(Int(winBounds.height))px)")
                    
                    let (detectedItems, durationMs) = VisionService.scanScreenForText(image: screenImage)
                    print("\(logTime()) [OCR] Scanned \(detectedItems.count) text segments in \(String(format: "%.1f", durationMs))ms")
                    
                    var isDisconnected = false
                    var reconnectBox: CGRect? = nil
                    var matchedKeyword = ""
                    
                    if let btn = WatcherClassifier.findReconnectButton(
                        in: detectedItems,
                        buttonText: config.reconnectButtonText,
                        ignorePhrases: config.ignorePhrases
                    ) {
                        reconnectBox = btn.boundingBox
                        isDisconnected = true
                        matchedKeyword = "\"\(config.reconnectButtonText)\" button"
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
                        
                        print("\n\(logTime()) [ALERT] Disconnect detected on Roblox window! Matched: \(matchedKeyword)")
                        print("\(logTime()) [Stats] Total Game Restarts Count: \(stats.totalGameRestarts)")
                        lastActionTimestamp = now
                        
                        let targetButton = config.reconnectButtonText
                        if let box = reconnectBox, config.autoClickReconnect {
                            print("\(logTime()) [Decision] Identified \"\(targetButton)\" button. Dispatching click...")
                            let clickX = winBounds.origin.x + Double(box.midX) * winBounds.width
                            let clickY = winBounds.origin.y + (1.0 - Double(box.midY)) * winBounds.height
                            InputService.clickScreenAtPoint(point: CGPoint(x: clickX, y: clickY), label: "\(targetButton) Button")
                            if config.autoTeleportToEvent {
                                GameService.teleportToEventArea(screenshotPath: screenshotPath, targetKeywords: config.eventTargetKeywords)
                            }
                        } else if config.autoRelaunchOnKick {
                            print("\(logTime()) [Decision] \"\(targetButton)\" button not found. Relaunching game...")
                            GameService.killAndRelaunchGame(placeId: lastKnownPlaceId, vipUrl: config.vipServerUrl)
                            if config.autoTeleportToEvent {
                                GameService.teleportToEventArea(screenshotPath: screenshotPath, targetKeywords: config.eventTargetKeywords)
                            }
                        }
                    } else {
                        print("\(logTime()) [Status] Game connection OK. No disconnect dialogs detected.")
                    }
                } else {
                    print("\(logTime()) [Warning] Roblox window not detected or minimised. Retrying next cycle...")
                }
            }
            
            // 4. Anti-AFK Keep-Alive Check
            if config.antiAfkEnabled {
                let afkElapsed = now.timeIntervalSince(lastAntiAfkClickTimestamp)
                if afkElapsed >= config.antiAfkIntervalSeconds {
                    if let win = WindowService.findRobloxWindow() {
                        print("\(logTime()) [Anti-AFK] Triggering periodic keep-alive click on Roblox window...")
                        InputService.clickRobloxCenterInBackground(bounds: win.bounds, pid: win.ownerPID)
                        lastAntiAfkClickTimestamp = now
                    }
                }
            }
        }
        
        Thread.sleep(forTimeInterval: config.checkIntervalSeconds)
    }
}

main()
