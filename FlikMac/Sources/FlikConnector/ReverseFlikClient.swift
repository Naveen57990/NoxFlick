import AppKit
import Foundation
import Network

public final class ReverseFlikClient: @unchecked Sendable {
    public static let shared = ReverseFlikClient()
    
    public private(set) var activePhoneHost: String? = nil
    public private(set) var activePhoneName: String? = nil
    public private(set) var phonePort: UInt16 = 52841
    
    private var browser: NWBrowser?
    
    private var probeTimer: Timer?
    
    private init() {
        startBrowsing()
        startPeriodicProbing()
    }
    
    public func startPeriodicProbing() {
        DispatchQueue.main.async { [weak self] in
            self?.probeGatewayAndKnownHosts()
            self?.probeTimer?.invalidate()
            self?.probeTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { [weak self] _ in
                self?.probeGatewayAndKnownHosts()
            }
        }
    }
    
    public func probeGatewayAndKnownHosts() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            
            // Check default gateway (e.g. Android Hotspot phone IP)
            if let gw = self.getDefaultGateway(), !gw.isEmpty {
                self.probePhone(ip: gw)
            }
            
            // If we have an existing host, verify it's still active
            if let host = self.activePhoneHost, !host.isEmpty {
                self.probePhone(ip: host)
            }
        }
    }
    
    public func probePhone(ip: String) {
        guard let url = URL(string: "http://\(ip):\(phonePort)/ping") else { return }
        var req = URLRequest(url: url)
        req.timeoutInterval = 2.0
        
        URLSession.shared.dataTask(with: req) { [weak self] data, response, error in
            guard let self = self,
                  let httpRes = response as? HTTPURLResponse, httpRes.statusCode == 200,
                  let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return
            }
            
            let deviceName = json["deviceName"] as? String ?? "Android Phone"
            DispatchQueue.main.async {
                self.activePhoneHost = ip
                self.activePhoneName = deviceName
                ControlWindowController.shared.updatePhoneStatus()
                StatusBarController.shared.rebuildMenu()
            }
        }.resume()
    }
    
    private func getDefaultGateway() -> String? {
        let task = Process()
        task.launchPath = "/sbin/route"
        task.arguments = ["-n", "get", "default"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        
        do {
            try task.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()
            if let output = String(data: data, encoding: .utf8) {
                for line in output.components(separatedBy: "\n") {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    if trimmed.hasPrefix("gateway:") {
                        let parts = trimmed.components(separatedBy: ":")
                        if parts.count > 1 {
                            return parts[1].trimmingCharacters(in: .whitespaces)
                        }
                    }
                }
            }
        } catch {
            return nil
        }
        return nil
    }
    
    public func recordPhoneActivity(ip: String, name: String? = nil) {
        self.activePhoneHost = ip
        if let name = name, !name.isEmpty {
            self.activePhoneName = name
        } else if self.activePhoneName == nil {
            self.activePhoneName = "Android Phone"
        }
        NSLog("📱 [NoxFlick] Recorded active phone at: %@ (%@)", ip, self.activePhoneName ?? "")
        probePhone(ip: ip)
    }
    
    public func startBrowsing() {
        let params = NWParameters()
        let descriptor = NWBrowser.Descriptor.bonjour(type: "_flick_phone._tcp.", domain: nil)
        let newBrowser = NWBrowser(for: descriptor, using: params)
        
        newBrowser.browseResultsChangedHandler = { [weak self] results, _ in
            for result in results {
                switch result.endpoint {
                case .service(let name, _, _, _):
                    self?.resolveService(endpoint: result.endpoint, serviceName: name)
                default:
                    break
                }
            }
        }
        
        newBrowser.start(queue: .main)
        self.browser = newBrowser
    }
    
    private func resolveService(endpoint: NWEndpoint, serviceName: String) {
        let connection = NWConnection(to: endpoint, using: .tcp)
        connection.stateUpdateHandler = { [weak self] state in
            if case .ready = state {
                if let innerEndpoint = connection.currentPath?.remoteEndpoint {
                    switch innerEndpoint {
                    case .hostPort(let host, let port):
                        let ip: String
                        switch host {
                        case .ipv4(let addr): ip = "\(addr)"
                        case .ipv6(let addr): ip = "\(addr)"
                        default: ip = "\(host)"
                        }
                        DispatchQueue.main.async {
                            self?.activePhoneHost = ip
                            self?.activePhoneName = serviceName
                            self?.phonePort = port.rawValue
                            NSLog("✨ [NoxFlick] Resolved phone service: %@ at %@:%d", serviceName, ip, port.rawValue)
                        }
                    default:
                        break
                    }
                }
                connection.cancel()
            }
        }
        connection.start(queue: .main)
    }
    
    public func sendFileToPhone(fileURL: URL, completion: @escaping (Bool, String) -> Void) {
        guard let host = activePhoneHost, !host.isEmpty else {
            completion(false, "No Android phone detected on your Wi-Fi yet. Open Nox Flick on your phone first!")
            return
        }
        
        let port = phonePort
        let targetURL = URL(string: "http://\(host):\(port)/transfer")!
        
        var request = URLRequest(url: targetURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 60.0
        
        let fileName = fileURL.lastPathComponent
        let encodedName = fileName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? fileName
        request.setValue(encodedName, forHTTPHeaderField: "X-File-Name")
        
        let mime = mimeType(for: fileURL.pathExtension)
        request.setValue(mime, forHTTPHeaderField: "Content-Type")
        
        let fileSize: Int64
        if let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
           let size = attrs[.size] as? Int64 {
            fileSize = size
            request.setValue("\(size)", forHTTPHeaderField: "Content-Length")
        } else {
            fileSize = 0
        }
        
        // Play launch swoosh chime
        SoundManager.shared.playArrivalChime(aimX: 0.0)
        
        let task = URLSession.shared.uploadTask(with: request, fromFile: fileURL) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(false, "Failed to send: \(error.localizedDescription)")
                    return
                }
                if let httpRes = response as? HTTPURLResponse, httpRes.statusCode == 200 {
                    completion(true, "Delivered '\(fileName)' to \(self.activePhoneName ?? "Phone")!")
                } else {
                    completion(false, "Transfer rejected by phone.")
                }
            }
        }
        task.resume()
    }
    
    private func mimeType(for ext: String) -> String {
        switch ext.lowercased() {
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "heic": return "image/heic"
        case "mp4": return "video/mp4"
        case "mov": return "video/quicktime"
        case "pdf": return "application/pdf"
        case "zip": return "application/zip"
        case "txt": return "text/plain"
        default: return "application/octet-stream"
        }
    }
}
