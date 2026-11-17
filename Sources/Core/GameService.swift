import Foundation
import CoreGraphics

// MARK: - Game Automation Workflows

public struct GameService {
    
    public static func killAndRelaunchGame(
        placeId: String?,
        vipUrl: String?,
        logger: ((String) -> Void)? = nil
    ) {
        logger?("\(WindowService.logTimestamp()) [Action] Force-closing stale RobloxPlayer...")
        
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
        logger: ((String) -> Void)? = nil
    ) {
        let keywordsDisplay = targetKeywords.joined(separator: ", ")
        logger?("\n\(WindowService.logTimestamp()) [Event Nav] Waiting for game to load before teleporting (targets: [\(keywordsDisplay)])...")
        
        let startTime = Date()
        while Date().timeIntervalSince(startTime) < Double(maxWaitSeconds) {
            var foundAndClicked = false
            autoreleasepool {
                Thread.sleep(forTimeInterval: 2.5)
                
                guard let (screenImage, winBounds) = VisionService.captureRobloxWindow(savePath: screenshotPath) else { return }
                let (detectedItems, _) = VisionService.scanScreenForText(image: screenImage)
                
                if let target = WatcherClassifier.findEventTarget(in: detectedItems, keywords: targetKeywords) {
                    let liveWin = WindowService.findRobloxWindow()
                    let currentBounds = liveWin?.bounds ?? winBounds
                    let localX = Double(target.boundingBox.midX) * currentBounds.width
                    let localY = (1.0 - Double(target.boundingBox.midY)) * currentBounds.height
                    
                    let textX = currentBounds.origin.x + localX
                    let textY = currentBounds.origin.y + localY
                    let iconPoint = CGPoint(x: textX, y: max(currentBounds.origin.y, textY - 45))
                    
                    logger?("\(WindowService.logTimestamp()) [Event Nav] Detected \"\(target.text)\" on Roblox window! Dispatching clicks...")
                    InputService.clickScreenAtPoint(point: iconPoint, label: "Event Icon Graphic", logger: logger)
                    logger?("\(WindowService.logTimestamp()) [Event Nav] Teleport dispatched successfully!\n")
                    foundAndClicked = true
                }
            }
            if foundAndClicked { return }
            
            let elapsed = Int(Date().timeIntervalSince(startTime))
            logger?("[Event Nav] Waiting for event icon [\(keywordsDisplay)] to appear (\(elapsed)/\(maxWaitSeconds)s)...")
        }
        
        logger?("\n\(WindowService.logTimestamp()) [Event Nav] Timeout: Event icon [\(keywordsDisplay)] not detected on Roblox window. Skipping click to prevent accidental inputs.\n")
    }
}
