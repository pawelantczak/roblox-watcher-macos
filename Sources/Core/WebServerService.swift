import Foundation
import Network

// MARK: - Embedded Zero-Dependency HTTP & SSE Server

public class WebServerService {
    public static let shared = WebServerService()
    
    private var listener: NWListener?
    private var sseClients: [ObjectIdentifier: NWConnection] = [:]
    private let queue = DispatchQueue(label: "xyz.ps99clan.robloxwatcher.webserver")
    public private(set) var port: UInt16 = 8765
    public private(set) var isRunning: Bool = false
    private var latestStateJSON: String?
    
    public var onActionReceived: (([String: Any]) -> Void)?
    
    public init() {}
    
    public static func getLocalIP() -> String? {
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(80).bigEndian
        inet_pton(AF_INET, "8.8.8.8", &addr.sin_addr)
        
        let sock = socket(AF_INET, SOCK_DGRAM, 0)
        if sock >= 0 {
            defer { close(sock) }
            var castAddr = sockaddr()
            memcpy(&castAddr, &addr, MemoryLayout<sockaddr_in>.size)
            if connect(sock, &castAddr, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0 {
                var localAddr = sockaddr_in()
                var len = socklen_t(MemoryLayout<sockaddr_in>.size)
                var castLocal = sockaddr()
                if getsockname(sock, &castLocal, &len) == 0 {
                    memcpy(&localAddr, &castLocal, MemoryLayout<sockaddr_in>.size)
                    var buf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                    if inet_ntop(AF_INET, &localAddr.sin_addr, &buf, socklen_t(INET_ADDRSTRLEN)) != nil {
                        let ip = String(cString: buf)
                        if ip != "0.0.0.0" { return ip }
                    }
                }
            }
        }
        
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }
        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let flags = Int32(ptr.pointee.ifa_flags)
            let saddr = ptr.pointee.ifa_addr.pointee
            if (flags & (IFF_UP|IFF_RUNNING|IFF_LOOPBACK)) == (IFF_UP|IFF_RUNNING) && saddr.sa_family == UInt8(AF_INET) {
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(ptr.pointee.ifa_addr, socklen_t(saddr.sa_len), &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST) == 0 {
                    return String(cString: hostname)
                }
            }
        }
        return nil
    }
    
    public func start(port: UInt16 = 8765) {
        guard !isRunning else { return }
        self.port = port
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            let listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
            self.listener = listener
            
            listener.newConnectionHandler = { [weak self] connection in
                self?.handleNewConnection(connection)
            }
            listener.stateUpdateHandler = { [weak self] state in
                if case .ready = state {
                    self?.isRunning = true
                } else if case .failed = state {
                    self?.stop()
                }
            }
            listener.start(queue: queue)
        } catch {
            print("Failed to start WebServer on port \(port): \(error)")
        }
    }
    
    public func stop() {
        queue.async {
            self.listener?.cancel()
            self.listener = nil
            for (_, client) in self.sseClients {
                client.cancel()
            }
            self.sseClients.removeAll()
            self.isRunning = false
        }
    }
    
    public func broadcastState(_ jsonString: String) {
        queue.async {
            self.latestStateJSON = jsonString
            let sseMessage = "data: \(jsonString)\n\n"
            guard let data = sseMessage.data(using: .utf8) else { return }
            for (id, client) in self.sseClients {
                client.send(content: data, completion: .contentProcessed { error in
                    if error != nil {
                        client.cancel()
                        self.queue.async { self.sseClients.removeValue(forKey: id) }
                    }
                })
            }
        }
    }
    
    private func handleNewConnection(_ connection: NWConnection) {
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                let id = ObjectIdentifier(connection)
                self?.queue.async { self?.sseClients.removeValue(forKey: id) }
            default: break
            }
        }
        connection.start(queue: queue)
        readHTTPRequest(connection: connection)
    }
    
    private func readHTTPRequest(connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self, let data = data, !data.isEmpty, let req = String(data: data, encoding: .utf8) else {
                if isComplete || error != nil { connection.cancel() }
                return
            }
            self.processRequest(req, connection: connection)
        }
    }
    
    private func processRequest(_ req: String, connection: NWConnection) {
        let lines = req.components(separatedBy: "\r\n")
        guard let firstLine = lines.first else { connection.cancel(); return }
        let parts = firstLine.components(separatedBy: " ")
        guard parts.count >= 2 else { connection.cancel(); return }
        let method = parts[0]
        let path = parts[1]
        
        if method == "GET" {
            if path == "/events" {
                let headers = "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nCache-Control: no-cache\r\nConnection: keep-alive\r\nAccess-Control-Allow-Origin: *\r\n\r\n"
                connection.send(content: headers.data(using: .utf8), completion: .contentProcessed { _ in })
                let id = ObjectIdentifier(connection)
                self.sseClients[id] = connection
                if let initial = self.latestStateJSON {
                    let msg = "data: \(initial)\n\n"
                    connection.send(content: msg.data(using: .utf8), completion: .contentProcessed { _ in })
                }
            } else if path == "/api/state" {
                sendHTTPResponse(connection: connection, contentType: "application/json", body: (self.latestStateJSON ?? "{}").data(using: .utf8)!)
            } else if path == "/api/config" {
                let cfg = StorageService.loadConfig()
                let data = (try? JSONEncoder().encode(cfg)) ?? "{}".data(using: .utf8)!
                sendHTTPResponse(connection: connection, contentType: "application/json", body: data)
            } else {
                serveStaticFile(path: path, connection: connection)
            }
        } else if method == "POST" && path == "/api/action" {
            var responseData: Data? = nil
            if let bodyRange = req.range(of: "\r\n\r\n") {
                let bodyStr = String(req[bodyRange.upperBound...])
                if let bodyData = bodyStr.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] {
                    DispatchQueue.main.async { self.onActionReceived?(json) }
                    if let act = json["action"] as? String, act == "getConfig" {
                        let cfg = StorageService.loadConfig()
                        if let cfgData = try? JSONEncoder().encode(cfg),
                           let cfgDict = try? JSONSerialization.jsonObject(with: cfgData) {
                            let resp: [String: Any] = ["success": true, "config": cfgDict]
                            responseData = try? JSONSerialization.data(withJSONObject: resp)
                        }
                    }
                }
            }
            let resp = responseData ?? "{\"success\":true}".data(using: .utf8)!
            sendHTTPResponse(connection: connection, contentType: "application/json", body: resp)
        } else {
            sendHTTPResponse(connection: connection, status: "404 Not Found", contentType: "text/plain", body: "Not Found".data(using: .utf8)!)
        }
    }
    
    private func serveStaticFile(path: String, connection: NWConnection) {
        var cleanPath = (path == "/" || path.isEmpty) ? "index.html" : String(path.dropFirst())
        if cleanPath == "favicon.ico" { cleanPath = "menubar_inactive.png" }
        let resourceURL = Bundle.main.url(forResource: (cleanPath as NSString).deletingPathExtension, withExtension: (cleanPath as NSString).pathExtension)
            ?? URL(fileURLWithPath: "Resources/\(cleanPath)")
        
        guard let data = try? Data(contentsOf: resourceURL) else {
            sendHTTPResponse(connection: connection, status: "404 Not Found", contentType: "text/plain", body: "File Not Found".data(using: .utf8)!)
            return
        }
        let mime = cleanPath.hasSuffix(".html") ? "text/html; charset=utf-8" : (cleanPath.hasSuffix(".png") ? "image/png" : "application/octet-stream")
        sendHTTPResponse(connection: connection, contentType: mime, body: data)
    }
    
    private func sendHTTPResponse(connection: NWConnection, status: String = "200 OK", contentType: String, body: Data) {
        let headers = "HTTP/1.1 \(status)\r\nContent-Type: \(contentType)\r\nContent-Length: \(body.count)\r\nAccess-Control-Allow-Origin: *\r\nConnection: close\r\n\r\n"
        var full = headers.data(using: .utf8)!
        full.append(body)
        connection.send(content: full, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { error in
            if error != nil {
                connection.cancel()
            } else {
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
                    connection.cancel()
                }
            }
        })
    }
}
