import Foundation

// MARK: - Persistent Storage Management

public struct StorageService {
    
    public static func getStorageDirectory() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("RobloxWatcher")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    
    public static func getConfigFileURL() -> URL {
        let local = URL(fileURLWithPath: "config.json")
        if FileManager.default.fileExists(atPath: local.path) {
            return local
        }
        return getStorageDirectory().appendingPathComponent("config.json")
    }
    
    public static func getStatsFileURL() -> URL {
        let local = URL(fileURLWithPath: "stats.json")
        if FileManager.default.fileExists(atPath: local.path) {
            return local
        }
        return getStorageDirectory().appendingPathComponent("stats.json")
    }
    
    public static func getScreenshotFileURL() -> URL {
        return getStorageDirectory().appendingPathComponent("latest_capture.png")
    }
    
    public static func getLogFileURL() -> URL {
        return getStorageDirectory().appendingPathComponent("watcher.log")
    }
    
    private static let logFileQueue = DispatchQueue(label: "xyz.ps99clan.robloxwatcher.logqueue")
    
    public static func appendLogToFile(_ line: String) {
        logFileQueue.async {
            let fileURL = getLogFileURL()
            let logLine = line + "\n"
            if let data = logLine.data(using: .utf8) {
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    if let handle = try? FileHandle(forWritingTo: fileURL) {
                        handle.seekToEndOfFile()
                        handle.write(data)
                        try? handle.close()
                    }
                } else {
                    try? data.write(to: fileURL, options: .atomic)
                }
            }
        }
    }
    
    public static func exportLogFile(to targetURL: URL) -> Bool {
        return logFileQueue.sync {
            let sourceURL = getLogFileURL()
            guard FileManager.default.fileExists(atPath: sourceURL.path) else { return false }
            try? FileManager.default.removeItem(at: targetURL)
            do {
                try FileManager.default.copyItem(at: sourceURL, to: targetURL)
                return true
            } catch {
                return false
            }
        }
    }
    
    public static func loadConfig() -> Config {
        let file = getConfigFileURL()
        if let data = try? Data(contentsOf: file),
           let config = try? JSONDecoder().decode(Config.self, from: data) {
            return config
        }
        let defaultConfig = Config()
        saveConfig(defaultConfig)
        return defaultConfig
    }
    
    public static func saveConfig(_ config: Config) {
        let file = getConfigFileURL()
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        if let encoded = try? encoder.encode(config) {
            try? encoded.write(to: file)
        }
    }
    
    public static func loadStats() -> Stats {
        let file = getStatsFileURL()
        if let data = try? Data(contentsOf: file),
           let stats = try? JSONDecoder().decode(Stats.self, from: data) {
            return stats
        }
        return Stats()
    }
    
    public static func saveStats(_ stats: Stats) {
        let file = getStatsFileURL()
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        if let encoded = try? encoder.encode(stats) {
            try? encoded.write(to: file)
        }
    }
    
    public static func getAppVersion() -> String {
        if let path = Bundle.main.path(forResource: "VERSION", ofType: nil),
           let version = try? String(contentsOfFile: path, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines) {
            return version
        }
        if let version = try? String(contentsOfFile: "VERSION", encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines) {
            return version
        }
        return "1.0.0"
    }
}
