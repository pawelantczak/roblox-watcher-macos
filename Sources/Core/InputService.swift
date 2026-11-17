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
    
    public static func clickRobloxCenterInBackground(bounds: CGRect, pid: pid_t, logger: ((String) -> Void)? = nil) {
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
        
        logger?("\(WindowService.logTimestamp()) [Anti-AFK] Keep-alive dual-click sent at (\(Int(center.x)), \(Int(center.y))) with verified focus & restore.")
    }
}
