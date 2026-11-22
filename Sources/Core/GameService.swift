import Foundation
import CoreGraphics
import AppKit

// MARK: - Game Automation Workflows

public struct GameService {
    
    public static func killAndRelaunchGame(
        placeId: String?,
        vipUrl: String?,
        logger: ((String) -> Void)? = nil
    ) {
        logger?("\(WindowService.logTimestamp()) [Action] Force-closing stale RobloxPlayer...")
        
        // 1. Force-kill RobloxPlayer
        let killTask = Process()
        killTask.launchPath = "/usr/bin/pkill"
        killTask.arguments = ["-9", "-f", "RobloxPlayer"]
        try? killTask.run()
        killTask.waitUntilExit()
        
        // 2. Dismiss any modal macOS CrashReporter dialogs that block focus
        let killCrashReporter = Process()
        killCrashReporter.launchPath = "/usr/bin/pkill"
        killCrashReporter.arguments = ["-9", "-f", "Problem Reporter"]
        try? killCrashReporter.run()
        killCrashReporter.waitUntilExit()
        
        sleep(2)
        
        let launchUrl: String
        if let vip = vipUrl, !vip.isEmpty {
            launchUrl = vip
        } else if let pid = placeId, !pid.isEmpty {
            launchUrl = "roblox://experiences/start?placeId=\(pid)"
        } else {
            logger?("\(WindowService.logTimestamp()) [Error] No placeId or VIP link available to relaunch game.")
            return
        }
        
        logger?("\(WindowService.logTimestamp()) [Action] Launching: \(launchUrl)")
        let openTask = Process()
        openTask.launchPath = "/usr/bin/open"
        openTask.arguments = [launchUrl]
        try? openTask.run()
        openTask.waitUntilExit()
        logger?("\(WindowService.logTimestamp()) [Success] Rejoin request sent to macOS system.")
    }
    
    public static func teleportToEventArea(
        screenshotPath: String,
        targetKeywords: [String],
        maxWaitSeconds: Int = 50,
        logger: ((String, String?) -> Void)? = nil
    ) {
        let keywordsDisplay = targetKeywords.joined(separator: ", ")
        logger?("\n\(WindowService.logTimestamp()) [Event Nav] Waiting for game to load before teleporting (targets: [\(keywordsDisplay)])...", nil)
        
        let startTime = Date()
        while Date().timeIntervalSince(startTime) < Double(maxWaitSeconds) {
            var foundAndClicked = false
            autoreleasepool {
                Thread.sleep(forTimeInterval: 2.5)
                
                guard let (screenImage, winBounds) = VisionService.captureRobloxWindow(savePath: screenshotPath) else { return }
                let (detectedItems, _) = VisionService.scanScreenForText(image: screenImage)
                
                var target = WatcherClassifier.findEventTarget(in: detectedItems, keywords: targetKeywords)
                if target == nil {
                    let sidebarItems = VisionService.scanLeftSidebarForText(image: screenImage)
                    target = WatcherClassifier.findEventTarget(in: sidebarItems, keywords: targetKeywords)
                }
                
                if let target = target {
                    let refined = IconTracerService.refineTarget(target, in: screenImage)
                    let liveWin = WindowService.findRobloxWindow()
                    let currentBounds = liveWin?.bounds ?? winBounds
                    let targetX = currentBounds.origin.x + Double(refined.clickPoint.x) * currentBounds.width
                    let targetY = currentBounds.origin.y + (1.0 - Double(refined.clickPoint.y)) * currentBounds.height
                    let targetPoint = CGPoint(x: targetX, y: targetY)
                    
                    let cropBase64 = VisionService.cropBase64(from: screenImage, boundingBox: refined.wholeIconBox ?? refined.boundingBox)
                    
                    logger?("\(WindowService.logTimestamp()) [Event Nav] Detected \"\(refined.text)\" on Roblox window! Dispatching clicks to icon center at (\(Int(targetX)), \(Int(targetY))) (icon logged to file)...", cropBase64)
                    InputService.clickScreenAtPoint(point: targetPoint, label: "Event Target Text") { msg in
                        logger?(msg, nil)
                    }
                    logger?("\(WindowService.logTimestamp()) [Event Nav] Teleport dispatched successfully!\n", nil)
                    foundAndClicked = true
                }
            }
            if foundAndClicked { return }
            
            let elapsed = Int(Date().timeIntervalSince(startTime))
            logger?("[Event Nav] Waiting for event icon [\(keywordsDisplay)] to appear (\(elapsed)/\(maxWaitSeconds)s)...", nil)
        }
        
        logger?("\n\(WindowService.logTimestamp()) [Event Nav] Timeout: Event icon [\(keywordsDisplay)] not detected on Roblox window. Skipping click to prevent accidental inputs.\n", nil)
    }
    
    public static func teleportToEventArea(
        screenshotPath: String,
        targetKeywords: [String],
        maxWaitSeconds: Int = 50,
        logger: ((String) -> Void)?
    ) {
        teleportToEventArea(screenshotPath: screenshotPath, targetKeywords: targetKeywords, maxWaitSeconds: maxWaitSeconds) { msg, _ in
            logger?(msg)
        }
    }
    
    public static func executeManualEventClick(
        keywords: [String],
        logger: ((String, String?) -> Void)? = nil,
        onFound: ((CGPoint, String) -> Void)? = nil
    ) {
        if !AXIsProcessTrusted() {
            logger?("\(WindowService.logTimestamp()) [ALERT] macOS Accessibility permission is missing for Roblox Watcher!", nil)
            logger?("\(WindowService.logTimestamp()) [Action] Opening System Settings > Accessibility. Please enable Roblox Watcher.", nil)
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
            return
        }
        
        guard let liveWin = WindowService.findRobloxWindow() else {
            logger?("\(WindowService.logTimestamp()) [Error] Roblox window not found on screen. Bring Roblox into view.", nil)
            return
        }
        
        let screenshotPath = StorageService.getScreenshotFileURL().path
        if let (screenImage, winBounds) = VisionService.captureRobloxWindow(savePath: screenshotPath) {
            let (detectedItems, _) = VisionService.scanScreenForText(image: screenImage)
            var target = WatcherClassifier.findEventTarget(in: detectedItems, keywords: keywords)
            if target == nil {
                let sidebarItems = VisionService.scanLeftSidebarForText(image: screenImage)
                target = WatcherClassifier.findEventTarget(in: sidebarItems, keywords: keywords)
            }
            
            if let target = target {
                let refined = IconTracerService.refineTarget(target, in: screenImage)
                let localX = Double(refined.clickPoint.x) * winBounds.width
                let localY = (1.0 - Double(refined.clickPoint.y)) * winBounds.height
                
                let currentWin = WindowService.findRobloxWindow() ?? liveWin
                let targetX = currentWin.bounds.origin.x + localX
                let targetY = currentWin.bounds.origin.y + localY
                let pt = CGPoint(x: targetX, y: targetY)
                let norm = CGPoint(x: refined.clickPoint.x, y: 1.0 - refined.clickPoint.y)
                let cropBase64 = VisionService.cropBase64(from: screenImage, boundingBox: refined.wholeIconBox ?? refined.boundingBox)
                
                onFound?(norm, refined.text)
                logger?("\(WindowService.logTimestamp()) [Action] Found \"\(refined.text)\" on UI! Clicking icon center at (\(Int(targetX)), \(Int(targetY))) (icon logged to file)...", cropBase64)
                InputService.clickScreenAtPoint(point: pt, label: "Detected Event Text") { msg in
                    logger?(msg, nil)
                }
                return
            }
        }
        
        let kwList = keywords.joined(separator: ", ")
        logger?("\(WindowService.logTimestamp()) [Warning] Event icon matching [\(kwList)] not detected on screen. No click dispatched.", nil)
    }
    
    public static func executeManualEventClick(
        keywords: [String],
        logger: ((String) -> Void)?,
        onFound: ((CGPoint, String) -> Void)? = nil
    ) {
        executeManualEventClick(keywords: keywords, logger: { msg, _ in logger?(msg) }, onFound: onFound)
    }
}
