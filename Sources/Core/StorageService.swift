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
