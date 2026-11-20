import Foundation
import AppKit
import CoreGraphics

// MARK: - Input Synthesis & Anti-AFK Engine

public struct InputService {
    
    public static func clickScreenAtPoint(point: CGPoint, label: String = "Target", logger: ((String) -> Void)? = nil) {
        logger?("\(WindowService.logTimestamp()) [Action] Focusing Roblox & clicking \(label) at (\(Int(point.x)), \(Int(point.y)))...")
        WindowService.activateRoblox()
        
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
        
        logger?("\(WindowService.logTimestamp()) [Success] Two-click sequence dispatched to \(label) (1st activate, 2nd action).")
    }
    
    public static func nextAntiAfkInterval(base: Double, variance: Double = 15.0) -> Double {
        let v = max(0.0, variance)
        return max(30.0, base + Double.random(in: -v...v))
    }

    public static func clickRobloxCenterInBackground(bounds: CGRect, pid: pid_t, jitterMax: CGFloat = 8.0, logger: ((String) -> Void)? = nil) {
        let jitterX = CGFloat.random(in: -jitterMax...jitterMax)
        let jitterY = CGFloat.random(in: -jitterMax...jitterMax)
        let targetPoint = CGPoint(x: bounds.midX + jitterX, y: bounds.midY + jitterY)
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
        
        // 2. Warp hardware cursor to target point with jitter
        CGWarpMouseCursorPosition(targetPoint)
        
        // 3. Click 1: Focus click to confirm active window focus in AppKit
        if let down1 = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: targetPoint, mouseButton: .left),
           let up1 = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: targetPoint, mouseButton: .left) {
            down1.post(tap: .cghidEventTap)
            usleep(40_000)
            up1.post(tap: .cghidEventTap)
        }
        
        // Dwell pause so Roblox window and frame update
        usleep(80_000)
        
        // 4. Send Spacebar key event (jump) to reset Roblox idle timer
        if let spaceDown = CGEvent(keyboardEventSource: nil, virtualKey: 49, keyDown: true),
           let spaceUp = CGEvent(keyboardEventSource: nil, virtualKey: 49, keyDown: false) {
            spaceDown.post(tap: .cghidEventTap)
            usleep(40_000)
            spaceUp.post(tap: .cghidEventTap)
        }
        
        // Allow game engine to process input before focus restore
        usleep(80_000)
        
        // 5. Restore previous application focus and hardware cursor position
        if !isRobloxAlreadyFrontmost {
            CGWarpMouseCursorPosition(savedCursor)
            frontmost?.activate()
        }
        
        logger?("\(WindowService.logTimestamp()) [Anti-AFK] Keep-alive signal (Focus Click + Space) sent at (\(Int(targetPoint.x)), \(Int(targetPoint.y))) with verified focus & restore.")
    }
}
