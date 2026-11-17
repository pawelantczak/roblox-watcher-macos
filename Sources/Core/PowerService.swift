import Foundation
import IOKit.pwr_mgt

// MARK: - Display Sleep & Auto-Lock Prevention Service

public class PowerService {
    public static let shared = PowerService()
    
    private var assertionID: IOPMAssertionID = 0
    public private(set) var isHoldingAssertion: Bool = false
    private let lock = NSLock()
    
    private init() {}
    
    /// Prevents macOS display sleep, screensaver, and auto-lock to preserve automation uptime.
    @discardableResult
    public func enableSleepPrevention(reason: String = "Roblox Watcher Active Monitoring") -> Bool {
        lock.lock()
        defer { lock.unlock() }
        
        guard !isHoldingAssertion else { return true }
        
        let assertionType = kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString
        let result = IOPMAssertionCreateWithName(
            assertionType,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &assertionID
        )
        
        if result == kIOReturnSuccess {
            isHoldingAssertion = true
            return true
        } else {
            return false
        }
    }
    
    /// Releases the power assertion, restoring normal macOS idle dimming and sleep timers.
    @discardableResult
    public func disableSleepPrevention() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        
        guard isHoldingAssertion else { return true }
        
        let result = IOPMAssertionRelease(assertionID)
        assertionID = 0
        isHoldingAssertion = false
        return result == kIOReturnSuccess
    }
}
