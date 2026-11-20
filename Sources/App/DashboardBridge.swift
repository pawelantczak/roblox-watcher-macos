import Foundation
import WebKit
import AppKit
import CoreGraphics

// MARK: - Dashboard Script Actions

public enum DashboardAction: String {
    case start
    case stop
    case testTeleport
    case refreshScreenshot
    case openExternal
    case getConfig
    case saveConfig
    case resetStats
    case requestPermissions
    case exportLogs
    case clearLogs
    case setAntiAfkInterval
    case setEventKeywords
}

// MARK: - WebKit Script Message Bridge

public class NativeBridgeHandler: NSObject, WKScriptMessageHandler {
    public weak var webView: WKWebView?
     
    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else { return }
        NativeBridgeHandler.handleAction(body: body, webView: webView)
    }
    
    public static func handleAction(body: [String: Any], webView: WKWebView? = nil) {
        guard let actionString = body["action"] as? String,
              let action = DashboardAction(rawValue: actionString) else { return }
        
        switch action {
        case .start:
            WatcherManager.shared.start()
        case .stop:
            WatcherManager.shared.stop()
        case .testTeleport:
            WatcherManager.shared.triggerTestTeleport()
        case .refreshScreenshot:
            _ = VisionService.captureRobloxWindow(savePath: StorageService.getScreenshotFileURL().path)
        case .openExternal:
            if let urlString = body["url"] as? String, let url = URL(string: urlString) {
                NSWorkspace.shared.open(url)
            }
        case .getConfig:
            let cfg = WatcherManager.shared.config
            if let data = try? JSONEncoder().encode(cfg),
               let jsonString = String(data: data, encoding: .utf8) {
                DispatchQueue.main.async {
                    webView?.evaluateJavaScript("window.populateConfig(\(jsonString));", completionHandler: nil)
                }
            }
        case .saveConfig:
            if let cfgDict = body["config"] as? [String: Any],
               let data = try? JSONSerialization.data(withJSONObject: cfgDict, options: []),
               let newCfg = try? JSONDecoder().decode(Config.self, from: data) {
                let prevEnabled = WatcherManager.shared.config.webServerEnabled
                let prevPort = WatcherManager.shared.config.webServerPort
                WatcherManager.shared.config = newCfg
                StorageService.saveConfig(newCfg)
                WatcherManager.shared.appendLog("\(WindowService.logTimestamp()) [Config] Settings updated via UI.")
                if newCfg.webServerEnabled != prevEnabled || newCfg.webServerPort != prevPort {
                    if newCfg.webServerEnabled {
                        WebServerService.shared.start(port: UInt16(newCfg.webServerPort))
                    } else {
                        WebServerService.shared.stop()
                    }
                }
            }
        case .resetStats:
            WatcherManager.shared.sessionRestarts = 0
            WatcherManager.shared.stats = Stats(totalGameRestarts: 0, lastRestartTime: nil)
            StorageService.saveStats(WatcherManager.shared.stats)
            WatcherManager.shared.appendLog("\(WindowService.logTimestamp()) [Stats] Restarts counter reset to 0.")
        case .requestPermissions:
            if !AXIsProcessTrusted() {
                let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
                _ = AXIsProcessTrustedWithOptions(options)
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                    NSWorkspace.shared.open(url)
                }
            }
            if !CGPreflightScreenCaptureAccess() {
                CGRequestScreenCaptureAccess()
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                    NSWorkspace.shared.open(url)
                }
            }
        case .exportLogs:
            DispatchQueue.main.async {
                let panel = NSSavePanel()
                panel.title = "Save Full Roblox Watcher Log"
                panel.nameFieldStringValue = "roblox-watcher.jsonl"
                panel.canCreateDirectories = true
                panel.begin { response in
                    guard response == .OK, let targetURL = panel.url else { return }
                    if !StorageService.exportLogFile(to: targetURL) {
                        let lines = WatcherManager.shared.logs.compactMap {
                            (try? JSONEncoder().encode(LogRecord(message: $0))).flatMap { String(data: $0, encoding: .utf8) }
                        }.joined(separator: "\n") + "\n"
                        try? lines.write(to: targetURL, atomically: true, encoding: .utf8)
                    }
                    WatcherManager.shared.appendLog("\(WindowService.logTimestamp()) [System] Full log exported to: \(targetURL.lastPathComponent)")
                }
            }
        case .clearLogs:
            WatcherManager.shared.clearLogs()
        case .setAntiAfkInterval:
            let val = (body["minutes"] as? Double) ?? (body["minutes"] as? Int).map(Double.init)
            if let minutes = val, minutes >= 1.0, minutes <= 19.0 {
                let seconds = minutes * 60.0
                if WatcherManager.shared.config.antiAfkIntervalSeconds != seconds {
                    WatcherManager.shared.config.antiAfkIntervalSeconds = seconds
                    StorageService.saveConfig(WatcherManager.shared.config)
                    WatcherManager.shared.appendLog("\(WindowService.logTimestamp()) [Anti-AFK Config] Interval set to \(Int(minutes))m (\(Int(seconds))s).")
                }
            }
        case .setEventKeywords:
            if let kws = body["keywords"] as? [String] {
                let cleaned = kws.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                if WatcherManager.shared.config.eventTargetKeywords != cleaned {
                    WatcherManager.shared.config.eventTargetKeywords = cleaned
                    StorageService.saveConfig(WatcherManager.shared.config)
                    WatcherManager.shared.appendLog("\(WindowService.logTimestamp()) [Event Config] Target keywords updated: [\(cleaned.joined(separator: ", "))]")
                }
            }
        }
    }
}
