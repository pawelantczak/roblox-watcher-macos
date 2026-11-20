import Foundation
import AppKit
import WebKit

// MARK: - Cocoa Application Delegate & Window Management

public class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    public var window: NSWindow!
    public var webView: WKWebView!
    public var bridgeHandler: NativeBridgeHandler!
    public var updateTimer: Timer?
    
    // Status Bar & Menu
    public var statusItem: NSStatusItem!
    public var statusMenuItem: NSMenuItem!
    public var toggleWatcherMenuItem: NSMenuItem!
    public var showWindowMenuItem: NSMenuItem!
    
    // Thumbnail Caching
    private var lastThumbnailModDate: Date? = nil
    private var cachedThumbnailBase64: String? = nil
    
    public func applicationDidFinishLaunching(_ notification: Notification) {
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
        
        // Fixed dimensions
        window.minSize = NSSize(width: windowWidth, height: windowHeight)
        window.maxSize = NSSize(width: windowWidth, height: windowHeight)
        window.collectionBehavior = [.fullScreenNone]
        
        // Status Bar
        setupStatusBar()
        
        // App Icon
        if let icon = Bundle.main.url(forResource: "app_icon", withExtension: "png").flatMap({ NSImage(contentsOf: $0) }) ?? NSImage(contentsOfFile: "Resources/app_icon.png") {
            NSApp.applicationIconImage = icon
        }
        
        // Window Styling
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
        
        loadHTML()
        
        // Check permissions and latest releases
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            if !AXIsProcessTrusted() {
                let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
                _ = AXIsProcessTrustedWithOptions(options)
            }
            if !CGPreflightScreenCaptureAccess() {
                CGRequestScreenCaptureAccess()
            }
            UpdateService.shared.checkForUpdates()
        }
        
        // Start WebServer if enabled
        if WatcherManager.shared.config.webServerEnabled {
            WebServerService.shared.start(port: UInt16(WatcherManager.shared.config.webServerPort))
            WebServerService.shared.onActionReceived = { [weak self] body in
                NativeBridgeHandler.handleAction(body: body, webView: self?.webView)
            }
        }
        
        // Periodic UI Sync
        updateTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.syncUIState()
        }
        
        if ProcessInfo.processInfo.arguments.contains("--start") {
            WatcherManager.shared.start()
        }
    }
    
    public func setupStatusBar() {
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
    
    public func updateStatusBarIcon(isActive: Bool) {
        let name = isActive ? "menubar_active" : "menubar_inactive"
        let imgURL = Bundle.main.url(forResource: name, withExtension: "png") ?? URL(fileURLWithPath: "Resources/\(name).png")
        if let image = NSImage(contentsOf: imgURL) {
            image.size = NSSize(width: 18, height: 18)
            image.isTemplate = false
            statusItem.button?.image = image
            statusItem.button?.imagePosition = .imageOnly
        }
    }
    
    @objc public func toggleWatcherFromMenu() {
        if WatcherManager.shared.isRunning { WatcherManager.shared.stop() } else { WatcherManager.shared.start() }
        syncUIState()
    }
    
    @objc public func showWindowFromMenu() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @objc public func quitAppFromMenu() {
        WatcherManager.shared.stop()
        NSApp.terminate(nil)
    }
    
    public func windowShouldClose(_ sender: NSWindow) -> Bool {
        window.orderOut(nil)
        return false
    }
    
    public func loadHTML() {
        let url = Bundle.main.url(forResource: "index", withExtension: "html") ?? URL(fileURLWithPath: "Resources/index.html")
        let baseDir = url.deletingLastPathComponent()
        webView.loadFileURL(url, allowingReadAccessTo: baseDir.path.hasPrefix("/Users") ? URL(fileURLWithPath: "/") : baseDir)
    }
    
    public func syncUIState() {
        let mgr = WatcherManager.shared
        let robloxInfo = WindowService.findRobloxProcess()
        let screenshotURL = StorageService.getScreenshotFileURL()
        let fileAttrs = try? FileManager.default.attributesOfItem(atPath: screenshotURL.path)
        let currentModDate = fileAttrs?[.modificationDate] as? Date
        if currentModDate != lastThumbnailModDate || cachedThumbnailBase64 == nil {
            cachedThumbnailBase64 = VisionService.createThumbnailBase64(from: screenshotURL, maxDimension: 960)
            lastThumbnailModDate = currentModDate
        }
        let base64Img = cachedThumbnailBase64
        
        var liveCoords: [String: Int]? = nil
        if let norm = mgr.latestEventNormalizedCoords, let win = WindowService.findRobloxWindow() {
            let liveX = Int(win.bounds.origin.x + (norm.x * win.bounds.width))
            let liveY = Int(win.bounds.origin.y + (norm.y * win.bounds.height))
            liveCoords = ["x": liveX, "y": liveY]
        }
        
        var antiAfkSecondsRemaining: Int = 0
        if mgr.isRunning && mgr.config.antiAfkEnabled {
            let elapsed = Date().timeIntervalSince(mgr.lastAntiAfkClickTimestamp)
            antiAfkSecondsRemaining = max(0, Int(mgr.config.antiAfkIntervalSeconds - elapsed))
        }
        
        let updater = UpdateService.shared
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
            "antiAfkIntervalMinutes": Int(round(mgr.config.antiAfkIntervalSeconds / 60.0)),
            "eventKeywords": mgr.config.eventTargetKeywords,
            "eventIconBase64": mgr.latestEventCropBase64 as Any,
            "eventCoords": liveCoords as Any,
            "eventMatchedText": mgr.latestEventMatchedText as Any,
            "appVersion": StorageService.getAppVersion(),
            "screenRecordingGranted": CGPreflightScreenCaptureAccess(),
            "accessibilityGranted": AXIsProcessTrusted(),
            "updateAvailable": updater.isUpdateAvailable,
            "latestVersion": updater.latestVersion as Any,
            "releaseUrl": updater.releaseUrl as Any,
            "remoteUrl": ((mgr.config.webServerEnabled && WebServerService.shared.isRunning) ? WebServerService.getLocalIP().map { "http://\($0):\(mgr.config.webServerPort)" } : nil) as Any
        ]
        
        if let jsonData = try? JSONSerialization.data(withJSONObject: state, options: []),
           let jsonStr = String(data: jsonData, encoding: .utf8) {
            WebServerService.shared.broadcastState(jsonStr)
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.updateStatusBarIcon(isActive: mgr.isRunning)
                self.statusMenuItem.title = mgr.isRunning ? "Status: Active (PID \(robloxInfo?.pid ?? 0))" : "Status: Stopped"
                self.toggleWatcherMenuItem.title = mgr.isRunning ? "Stop Watcher" : "Start Watcher"
                self.webView.evaluateJavaScript("window.updateUIState(\(jsonStr));", completionHandler: nil)
            }
        }
    }
    
    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
    
    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        return true
    }
    
    public func applicationWillTerminate(_ notification: Notification) {
        WatcherManager.shared.stop()
        WebServerService.shared.stop()
    }
}
