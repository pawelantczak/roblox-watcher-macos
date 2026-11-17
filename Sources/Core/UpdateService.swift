import Foundation

// MARK: - GitHub Release & Update Checker

public class UpdateService {
    public static let shared = UpdateService()
    
    public private(set) var isUpdateAvailable: Bool = false
    public private(set) var latestVersion: String? = nil
    public private(set) var releaseUrl: String? = nil
    
    private let repoSlug = "pawel-antczak/roblox-watcher"
    
    public init() {}
    
    public static func isNewerVersion(remote: String, current: String) -> Bool {
        let cleanRemote = remote.trimmingCharacters(in: CharacterSet(charactersIn: "vV \t\r\n"))
        let cleanCurrent = current.trimmingCharacters(in: CharacterSet(charactersIn: "vV \t\r\n"))
        
        let remoteParts = cleanRemote.split(separator: ".").compactMap { Int($0) }
        let currentParts = cleanCurrent.split(separator: ".").compactMap { Int($0) }
        
        guard !remoteParts.isEmpty && !currentParts.isEmpty else { return false }
        
        let maxCount = max(remoteParts.count, currentParts.count)
        for i in 0..<maxCount {
            let r = i < remoteParts.count ? remoteParts[i] : 0
            let c = i < currentParts.count ? currentParts[i] : 0
            if r > c { return true }
            if r < c { return false }
        }
        return false
    }
    
    public func checkForUpdates(completion: ((Bool, String?, String?) -> Void)? = nil) {
        guard let url = URL(string: "https://api.github.com/repos/\(repoSlug)/releases/latest") else {
            completion?(false, nil, nil)
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.setValue("RobloxWatcher/\(StorageService.getAppVersion())", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 8.0
        
        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self,
                  let data = data,
                  error == nil,
                  let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                completion?(false, nil, nil)
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                   let tagName = json["tag_name"] as? String,
                   let htmlUrl = json["html_url"] as? String {
                    
                    let remoteTag = tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV \t\r\n"))
                    let currentVersion = StorageService.getAppVersion()
                    
                    let updateAvailable = UpdateService.isNewerVersion(remote: remoteTag, current: currentVersion)
                    
                    DispatchQueue.main.async {
                        self.isUpdateAvailable = updateAvailable
                        self.latestVersion = remoteTag
                        self.releaseUrl = htmlUrl
                        completion?(updateAvailable, remoteTag, htmlUrl)
                    }
                    return
                }
            } catch {
                // Ignore parse errors on network interruptions
            }
            completion?(false, nil, nil)
        }
        task.resume()
    }
}
