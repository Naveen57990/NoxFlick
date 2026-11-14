import Foundation
import Network
import AppKit

public struct FlickMetadata: Sendable {
    public let fileName: String
    public let fileSize: Int64
    public let mimeType: String
    public let flickAngle: Double // degrees -45 to +45
    public let flickVelocity: Double // 0.5 to 2.5
    public let aimX: Double // -1.0 (far left) to 0.0 (center) to +1.0 (far right)
    public let senderName: String

    public init(
        fileName: String,
        fileSize: Int64,
        mimeType: String,
        flickAngle: Double,
        flickVelocity: Double,
        aimX: Double = 0.0,
        senderName: String
    ) {
        self.fileName = fileName
        self.fileSize = fileSize
        self.mimeType = mimeType
        self.flickAngle = flickAngle
        self.flickVelocity = flickVelocity
        self.aimX = aimX
        self.senderName = senderName
    }
}

public protocol FlikServerDelegate: AnyObject, Sendable {
    func serverDidReceiveFile(fileURL: URL, metadata: FlickMetadata)
    func serverDidReceiveLink(url: URL, senderName: String)
    func serverStatusDidChange(isRunning: Bool, port: UInt16)
}

public final class FlikServer: @unchecked Sendable {
    public static let shared = FlikServer()
    public weak var delegate: FlikServerDelegate?
    
    private var listener: NWListener?
    public private(set) var port: UInt16 = 52840
    public private(set) var isRunning: Bool = false
    
    private let storageDirectory: URL
    
    private init() {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        self.storageDirectory = downloads.appendingPathComponent("Nox Flick Received", isDirectory: true)
        try? FileManager.default.createDirectory(at: self.storageDirectory, withIntermediateDirectories: true)
    }
    
    public func start(preferredPort: UInt16 = 52840) {
        stop()
        
        let localPort = NWEndpoint.Port(rawValue: preferredPort) ?? NWEndpoint.Port(rawValue: 0)!
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        
        do {
            let newListener = try NWListener(using: params, on: localPort)
            
            // Advertise Bonjour service
            let machineName = Host.current().localizedName ?? "MacBook"
            var txtRecord = NWTXTRecord()
            txtRecord["device"] = machineName
            txtRecord["v"] = "1.0"
            txtRecord["proto"] = "flik"
            newListener.service = NWListener.Service(name: machineName, type: "_flick._tcp", domain: nil, txtRecord: txtRecord.data)
            
            newListener.stateUpdateHandler = { [weak self] state in
                guard let self = self else { return }
                switch state {
                case .ready:
                    if let actualPort = newListener.port?.rawValue {
                        self.port = actualPort
                        self.isRunning = true
                        print("⚡ FlikServer listening on port \(actualPort) with Bonjour _flick._tcp")
                        DispatchQueue.main.async {
                            self.delegate?.serverStatusDidChange(isRunning: true, port: actualPort)
                        }
                    }
                case .failed(let error):
                    print("⚠️ Nox Flick server failed: \(error). Auto-recovering in 2s...")
                    self.isRunning = false
                    DispatchQueue.main.async {
                        self.delegate?.serverStatusDidChange(isRunning: false, port: 0)
                    }
                    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2.0) { [weak self] in
                        guard let self = self else { return }
                        print("🔄 Auto-restarting Nox Flick server...")
                        self.start(preferredPort: self.port)
                    }
                case .cancelled:
                    self.isRunning = false
                    DispatchQueue.main.async {
                        self.delegate?.serverStatusDidChange(isRunning: false, port: 0)
                    }
                default:
                    break
                }
            }
            
            newListener.newConnectionHandler = { [weak self] connection in
                self?.handleIncomingConnection(connection)
            }
            
            newListener.start(queue: .global(qos: .userInitiated))
            self.listener = newListener
        } catch {
            print("❌ Failed to create NWListener: \(error)")
        }
    }
    
    public func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
    }
    
    private func handleIncomingConnection(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .userInitiated))
        
        var requestBuffer = Data()
        var headersParsed = false
        var method = ""
        var path = ""
        var headers: [String: String] = [:]
        var contentLength: Int64 = 0
        var bodyReceived: Int64 = 0
        var fileHandle: FileHandle?
        var tempFileURL: URL?
        var metadata: FlickMetadata?
        
        func readNext() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
                if let data = data, !data.isEmpty {
                    if !headersParsed {
                        requestBuffer.append(data)
                        // Search for double CRLF
                        if let range = requestBuffer.range(of: Data("\r\n\r\n".utf8)) {
                            let headerData = requestBuffer.subdata(in: 0..<range.lowerBound)
                            let remainderData = requestBuffer.subdata(in: range.upperBound..<requestBuffer.count)
                            headersParsed = true
                            
                            if let headerString = String(data: headerData, encoding: .utf8) {
                                let lines = headerString.components(separatedBy: "\r\n")
                                if let requestLine = lines.first {
                                    let parts = requestLine.split(separator: " ")
                                    if parts.count >= 2 {
                                        method = String(parts[0]).uppercased()
                                        path = String(parts[1])
                                    }
                                }
                                for line in lines.dropFirst() {
                                    let kv = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                                    if kv.count == 2 {
                                        headers[kv[0].lowercased()] = kv[1]
                                    }
                                }
                            }
                            
                            let lengthStr = headers["content-length"] ?? headers["x-file-size"] ?? "0"
                            contentLength = Int64(lengthStr) ?? 0
                            
                            // Check path
                            if path == "/ping" || path == "/status" {
                                self.respondOK(connection: connection, json: [
                                    "status": "ready",
                                    "deviceName": Host.current().localizedName ?? "MacBook",
                                    "version": "1.0"
                                ])
                                return
                            } else if path == "/pair" {
                                self.respondOK(connection: connection, json: [
                                    "status": "approved",
                                    "deviceName": Host.current().localizedName ?? "MacBook"
                                ])
                                return
                            } else if path.starts(with: "/link") {
                                // Accumulate JSON body
                                var bodyData = remainderData
                                func finishLink() {
                                    if let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
                                       let urlStr = json["url"] as? String,
                                       let url = URL(string: urlStr) {
                                        let sender = (json["senderName"] as? String) ?? "Android Device"
                                        DispatchQueue.main.async {
                                            NSWorkspace.shared.open(url)
                                            self.delegate?.serverDidReceiveLink(url: url, senderName: sender)
                                        }
                                    }
                                    self.respondOK(connection: connection, json: ["success": true])
                                }
                                
                                if Int64(bodyData.count) >= contentLength {
                                    finishLink()
                                } else {
                                    func readRemainder() {
                                        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { chunk, _, isComplete, _ in
                                            if let chunk = chunk { bodyData.append(chunk) }
                                            if Int64(bodyData.count) >= contentLength || isComplete {
                                                finishLink()
                                            } else {
                                                readRemainder()
                                            }
                                        }
                                    }
                                    readRemainder()
                                }
                                return
                            } else if path.starts(with: "/transfer") {
                                // Prepare file streaming
                                let rawFileName = headers["x-file-name"] ?? "received_\(Int(Date().timeIntervalSince1970)).dat"
                                let cleanFileName = rawFileName.removingPercentEncoding ?? rawFileName
                                let mime = headers["x-mime-type"] ?? "application/octet-stream"
                                let angle = Double(headers["x-flick-angle"] ?? "0") ?? 0.0
                                let velocity = Double(headers["x-flick-velocity"] ?? "1.5") ?? 1.5
                                let rawAim = headers["x-flick-position-x"]
                                let aimX: Double
                                if let rawAim = rawAim, let val = Double(rawAim) {
                                    aimX = val
                                } else {
                                    // Fallback: estimate from angle (-30° to +30° -> -1.0 to +1.0)
                                    aimX = angle / 30.0
                                }
                                let sender = headers["x-sender-name"] ?? "Android"
                                
                                metadata = FlickMetadata(
                                    fileName: cleanFileName,
                                    fileSize: contentLength,
                                    mimeType: mime,
                                    flickAngle: angle,
                                    flickVelocity: velocity,
                                    aimX: aimX,
                                    senderName: sender
                                )
                                
                                // Generate unique file URL in storage directory
                                var destURL = self.storageDirectory.appendingPathComponent(cleanFileName)
                                if FileManager.default.fileExists(atPath: destURL.path) {
                                    let ext = destURL.pathExtension
                                    let base = destURL.deletingPathExtension().lastPathComponent
                                    let timestamp = Int(Date().timeIntervalSince1970)
                                    destURL = self.storageDirectory.appendingPathComponent("\(base)_\(timestamp).\(ext)")
                                }
                                tempFileURL = destURL
                                
                                FileManager.default.createFile(atPath: destURL.path, contents: nil)
                                fileHandle = try? FileHandle(forWritingTo: destURL)
                                
                                if !remainderData.isEmpty {
                                    fileHandle?.write(remainderData)
                                    bodyReceived += Int64(remainderData.count)
                                }
                                
                                if bodyReceived >= contentLength && contentLength > 0 {
                                    fileHandle?.closeFile()
                                    if let url = tempFileURL, let meta = metadata {
                                        self.delegate?.serverDidReceiveFile(fileURL: url, metadata: meta)
                                    }
                                    self.respondOK(connection: connection, json: ["success": true, "fileName": cleanFileName])
                                    return
                                }
                            } else {
                                self.respond404(connection: connection)
                                return
                            }
                        }
                    } else {
                        // Streaming body data for transfer
                        fileHandle?.write(data)
                        bodyReceived += Int64(data.count)
                        if contentLength > 0 && bodyReceived >= contentLength {
                            fileHandle?.closeFile()
                            fileHandle = nil
                            if let url = tempFileURL, let meta = metadata {
                                self.delegate?.serverDidReceiveFile(fileURL: url, metadata: meta)
                            }
                            let name = metadata?.fileName ?? "file"
                            self.respondOK(connection: connection, json: ["success": true, "fileName": name])
                            return
                        }
                    }
                }
                
                if isComplete {
                    fileHandle?.closeFile()
                    if fileHandle != nil {
                        fileHandle = nil
                        if let url = tempFileURL, let meta = metadata {
                            self.delegate?.serverDidReceiveFile(fileURL: url, metadata: meta)
                            let name = meta.fileName
                            self.respondOK(connection: connection, json: ["success": true, "fileName": name])
                        }
                    }
                    return
                }
                if error != nil {
                    fileHandle?.closeFile()
                    return
                }
                
                readNext()
            }
        }
        
        readNext()
    }
    
    private func respondOK(connection: NWConnection, json: [String: Any]) {
        let data = (try? JSONSerialization.data(withJSONObject: json)) ?? Data("{}".utf8)
        let response = """
        HTTP/1.1 200 OK\r
        Content-Type: application/json\r
        Content-Length: \(data.count)\r
        Access-Control-Allow-Origin: *\r
        Connection: close\r
        \r
        
        """
        connection.send(content: Data(response.utf8) + data, completion: .contentProcessed({ _ in
            connection.cancel()
        }))
    }
    
    private func respond404(connection: NWConnection) {
        let resp = "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(resp.utf8), completion: .contentProcessed({ _ in
            connection.cancel()
        }))
    }
}
