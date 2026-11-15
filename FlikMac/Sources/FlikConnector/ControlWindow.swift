import AppKit
import Foundation

// MARK: - Interactive Reverse Flick Drop Zone View
public final class FlickDropZoneView: NSView {
    private let titleLabel = NSTextField(labelWithString: "📱 Flick File to Phone")
    private let phoneStatusLabel = NSTextField(labelWithString: "⚪ Checking phone connection...")
    private let hintLabel = NSTextField(labelWithString: "Drag & drop files here, or click to choose")
    private let borderLayer = CAShapeLayer()
    
    public override init(frame: NSRect) {
        super.init(frame: frame)
        setupUI()
        registerForDraggedTypes([.fileURL])
    }
    
    required init?(coder: NSCoder) { fatalError() }
    
    private func setupUI() {
        wantsLayer = true
        layer?.cornerRadius = 14
        layer?.masksToBounds = false
        layer?.backgroundColor = NSColor(calibratedRed: 0.08, green: 0.10, blue: 0.16, alpha: 0.95).cgColor
        
        borderLayer.strokeColor = NSColor(calibratedRed: 0.0, green: 0.96, blue: 1.0, alpha: 0.6).cgColor
        borderLayer.lineWidth = 1.5
        borderLayer.lineDashPattern = [6, 4]
        borderLayer.fillColor = nil
        layer?.addSublayer(borderLayer)
        
        titleLabel.isEditable = false
        titleLabel.isSelectable = false
        titleLabel.isBezeled = false
        titleLabel.drawsBackground = false
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .bold)
        titleLabel.textColor = NSColor(calibratedRed: 0.0, green: 0.96, blue: 1.0, alpha: 1.0)
        addSubview(titleLabel)
        
        phoneStatusLabel.isEditable = false
        phoneStatusLabel.isSelectable = false
        phoneStatusLabel.isBezeled = false
        phoneStatusLabel.drawsBackground = false
        phoneStatusLabel.font = NSFont.systemFont(ofSize: 11.5, weight: .semibold)
        phoneStatusLabel.textColor = NSColor.white.withAlphaComponent(0.85)
        addSubview(phoneStatusLabel)
        
        hintLabel.isEditable = false
        hintLabel.isSelectable = false
        hintLabel.isBezeled = false
        hintLabel.drawsBackground = false
        hintLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        hintLabel.textColor = NSColor(calibratedRed: 0.58, green: 0.64, blue: 0.72, alpha: 1.0)
        addSubview(hintLabel)
        
        updateStatus()
    }
    
    public override func layout() {
        super.layout()
        borderLayer.frame = bounds
        borderLayer.path = CGPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), cornerWidth: 14, cornerHeight: 14, transform: nil)
        titleLabel.frame = NSRect(x: 16, y: bounds.height - 30, width: bounds.width - 32, height: 20)
        phoneStatusLabel.frame = NSRect(x: 16, y: bounds.height - 54, width: bounds.width - 32, height: 18)
        hintLabel.frame = NSRect(x: 16, y: 12, width: bounds.width - 32, height: 18)
    }
    
    public func updateStatus() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if let name = ReverseFlikClient.shared.activePhoneName, let host = ReverseFlikClient.shared.activePhoneHost {
                self.phoneStatusLabel.stringValue = "🟢 \(name) Connected (\(host))"
                self.phoneStatusLabel.textColor = NSColor(calibratedRed: 0.20, green: 0.90, blue: 0.55, alpha: 1.0)
                self.borderLayer.strokeColor = NSColor(calibratedRed: 0.0, green: 0.96, blue: 1.0, alpha: 0.8).cgColor
            } else {
                self.phoneStatusLabel.stringValue = "⚪ Searching for Android phone on Wi-Fi..."
                self.phoneStatusLabel.textColor = NSColor.white.withAlphaComponent(0.6)
                self.borderLayer.strokeColor = NSColor.white.withAlphaComponent(0.2).cgColor
            }
        }
    }
    
    public override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        layer?.backgroundColor = NSColor(calibratedRed: 0.12, green: 0.16, blue: 0.28, alpha: 0.98).cgColor
        borderLayer.strokeColor = NSColor(calibratedRed: 0.0, green: 0.96, blue: 1.0, alpha: 1.0).cgColor
        borderLayer.lineWidth = 2.0
        return .copy
    }
    
    public override func draggingExited(_ sender: NSDraggingInfo?) {
        layer?.backgroundColor = NSColor(calibratedRed: 0.08, green: 0.10, blue: 0.16, alpha: 0.95).cgColor
        borderLayer.strokeColor = NSColor(calibratedRed: 0.0, green: 0.96, blue: 1.0, alpha: 0.6).cgColor
        borderLayer.lineWidth = 1.5
    }
    
    public override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        return true
    }
    
    public override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        draggingExited(nil)
        guard let items = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
              let fileURL = items.first else {
            return false
        }
        sendURL(fileURL)
        return true
    }
    
    public override func mouseDown(with event: NSEvent) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Flick to Phone"
        panel.title = "Select File to Flick to Phone"
        if panel.runModal() == .OK, let url = panel.url {
            sendURL(url)
        }
    }
    
    private func sendURL(_ url: URL) {
        hintLabel.stringValue = "🚀 Sending '\(url.lastPathComponent)'..."
        ReverseFlikClient.shared.sendFileToPhone(fileURL: url) { [weak self] success, message in
            DispatchQueue.main.async {
                self?.hintLabel.stringValue = success ? "✅ Delivered '\(url.lastPathComponent)' to phone!" : "❌ \(message)"
                let alert = NSAlert()
                alert.messageText = success ? "🚀 Flicked to Phone!" : "❌ Reverse Flick Failed"
                alert.informativeText = message
                alert.alertStyle = success ? .informational : .warning
                alert.runModal()
            }
        }
    }
}

// MARK: - Main Control Window Controller
public final class ControlWindowController: NSWindowController, NSWindowDelegate, @unchecked Sendable {
    public static let shared = ControlWindowController()
    
    private var statusDot: NSView!
    private var statusTitleLabel: NSTextField!
    private var statusSubLabel: NSTextField!
    private var powerButton: NSButton!
    private var hostLabel: NSTextField!
    private var dropZoneView: FlickDropZoneView!
    private var saveAllBtn: NSButton!
    
    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "NoxFlick"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.backgroundColor = .clear
        
        super.init(window: window)
        window.delegate = self
        setupUI(in: window)
        window.orderOut(nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI(in window: NSWindow) {
        let visualEffect = NSVisualEffectView(frame: window.contentView!.bounds)
        visualEffect.autoresizingMask = [.width, .height]
        visualEffect.material = .underWindowBackground
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        visualEffect.wantsLayer = true
        visualEffect.layer?.backgroundColor = NSColor(calibratedRed: 0.05, green: 0.06, blue: 0.09, alpha: 0.94).cgColor
        window.contentView?.addSubview(visualEffect)
        
        let container = NSView(frame: window.contentView!.bounds)
        container.autoresizingMask = [.width, .height]
        visualEffect.addSubview(container)
        
        // 1. App Icon
        let iconView = NSImageView(frame: NSRect(x: (400 - 68) / 2, y: 544, width: 68, height: 68))
        if let iconImage = NSImage(named: "AppIcon") ?? NSImage(contentsOfFile: "/Users/naveen/Downloads/flick file transfer/FlikMac/Resources/AppIcon.png") {
            iconView.image = iconImage
        } else {
            iconView.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil)
        }
        iconView.wantsLayer = true
        iconView.layer?.cornerRadius = 17
        iconView.layer?.masksToBounds = true
        iconView.layer?.borderColor = NSColor(calibratedRed: 0.49, green: 0.23, blue: 0.93, alpha: 0.6).cgColor
        iconView.layer?.borderWidth = 1.5
        container.addSubview(iconView)
        
        // 2. Title & Subtitle
        let titleLabel = NSTextField(labelWithString: "NoxFlick")
        titleLabel.frame = NSRect(x: 20, y: 512, width: 360, height: 26)
        titleLabel.alignment = .center
        titleLabel.font = NSFont.systemFont(ofSize: 22, weight: .bold)
        titleLabel.textColor = .white
        container.addSubview(titleLabel)
        
        let subLabel = NSTextField(labelWithString: "Kinetic Spatial File Transfer")
        subLabel.frame = NSRect(x: 20, y: 492, width: 360, height: 16)
        subLabel.alignment = .center
        subLabel.font = NSFont.systemFont(ofSize: 11.5, weight: .medium)
        subLabel.textColor = NSColor(calibratedRed: 0.58, green: 0.64, blue: 0.72, alpha: 1.0)
        container.addSubview(subLabel)
        
        // 3. Receiver Status Card
        let statusCard = NSView(frame: NSRect(x: 24, y: 374, width: 352, height: 104))
        statusCard.wantsLayer = true
        statusCard.layer?.cornerRadius = 14
        statusCard.layer?.backgroundColor = NSColor(calibratedRed: 0.08, green: 0.09, blue: 0.14, alpha: 0.9).cgColor
        statusCard.layer?.borderColor = NSColor(calibratedRed: 0.2, green: 0.22, blue: 0.32, alpha: 0.8).cgColor
        statusCard.layer?.borderWidth = 1.0
        container.addSubview(statusCard)
        
        // Status Dot
        statusDot = NSView(frame: NSRect(x: 16, y: 74, width: 10, height: 10))
        statusDot.wantsLayer = true
        statusDot.layer?.cornerRadius = 5
        statusDot.layer?.backgroundColor = NSColor.systemGreen.cgColor
        statusCard.addSubview(statusDot)
        
        // Status Title
        statusTitleLabel = NSTextField(labelWithString: "RECEIVER ACTIVE")
        statusTitleLabel.frame = NSRect(x: 34, y: 70, width: 280, height: 18)
        statusTitleLabel.font = NSFont.systemFont(ofSize: 11.5, weight: .bold)
        statusTitleLabel.textColor = .white
        statusCard.addSubview(statusTitleLabel)
        
        // Status Subtitle
        statusSubLabel = NSTextField(labelWithString: "Listening on Port 52840 • Ready for phone throws")
        statusSubLabel.frame = NSRect(x: 34, y: 52, width: 290, height: 16)
        statusSubLabel.font = NSFont.systemFont(ofSize: 10.5)
        statusSubLabel.textColor = NSColor.white.withAlphaComponent(0.6)
        statusCard.addSubview(statusSubLabel)
        
        // Power Button
        powerButton = NSButton(frame: NSRect(x: 14, y: 10, width: 324, height: 36))
        powerButton.title = "SWITCH RECEIVER OFF"
        powerButton.font = NSFont.systemFont(ofSize: 12, weight: .bold)
        powerButton.isBordered = false
        powerButton.wantsLayer = true
        powerButton.layer?.cornerRadius = 8
        powerButton.layer?.backgroundColor = NSColor(calibratedRed: 0.49, green: 0.23, blue: 0.93, alpha: 0.9).cgColor
        powerButton.contentTintColor = .white
        powerButton.target = self
        powerButton.action = #selector(togglePower)
        statusCard.addSubview(powerButton)
        
        // 4. Reverse Flick Drop Zone (Mac -> Phone)
        dropZoneView = FlickDropZoneView(frame: NSRect(x: 24, y: 256, width: 352, height: 104))
        container.addSubview(dropZoneView)
        
        // 5. Stack Actions (Save All Cards + Received Files)
        saveAllBtn = NSButton(frame: NSRect(x: 24, y: 198, width: 170, height: 44))
        saveAllBtn.title = "💾 Save All Cards"
        saveAllBtn.font = NSFont.systemFont(ofSize: 12, weight: .bold)
        saveAllBtn.isBordered = false
        saveAllBtn.wantsLayer = true
        saveAllBtn.layer?.cornerRadius = 10
        saveAllBtn.layer?.backgroundColor = NSColor(calibratedRed: 0.0, green: 0.96, blue: 1.0, alpha: 0.22).cgColor
        saveAllBtn.layer?.borderColor = NSColor(calibratedRed: 0.0, green: 0.96, blue: 1.0, alpha: 0.5).cgColor
        saveAllBtn.layer?.borderWidth = 1.0
        saveAllBtn.contentTintColor = .white
        saveAllBtn.target = self
        saveAllBtn.action = #selector(saveAllCards)
        container.addSubview(saveAllBtn)
        
        let openFolderBtn = NSButton(frame: NSRect(x: 206, y: 198, width: 170, height: 44))
        openFolderBtn.title = "📁 Received Files"
        openFolderBtn.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        openFolderBtn.isBordered = false
        openFolderBtn.wantsLayer = true
        openFolderBtn.layer?.cornerRadius = 10
        openFolderBtn.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
        openFolderBtn.contentTintColor = .white
        openFolderBtn.target = self
        openFolderBtn.action = #selector(openFolder)
        container.addSubview(openFolderBtn)
        
        // 6. Simulate Flick Button
        let testFlickBtn = NSButton(frame: NSRect(x: 24, y: 144, width: 352, height: 40))
        testFlickBtn.title = "🚀 Simulate Incoming Flick"
        testFlickBtn.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        testFlickBtn.isBordered = false
        testFlickBtn.wantsLayer = true
        testFlickBtn.layer?.cornerRadius = 10
        testFlickBtn.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
        testFlickBtn.contentTintColor = .white
        testFlickBtn.target = self
        testFlickBtn.action = #selector(simulateFlick)
        container.addSubview(testFlickBtn)
        
        // 7. Host info
        let hostName = Host.current().localizedName ?? "MacBook"
        hostLabel = NSTextField(labelWithString: "Mac: \(hostName) • Auto-Discovered on LAN")
        hostLabel.frame = NSRect(x: 20, y: 96, width: 360, height: 18)
        hostLabel.alignment = .center
        hostLabel.font = NSFont.systemFont(ofSize: 11)
        hostLabel.textColor = NSColor.white.withAlphaComponent(0.45)
        container.addSubview(hostLabel)
        
        // 8. Quit Button
        let quitBtn = NSButton(frame: NSRect(x: 24, y: 36, width: 352, height: 42))
        quitBtn.title = "Quit NoxFlick"
        quitBtn.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        quitBtn.isBordered = false
        quitBtn.wantsLayer = true
        quitBtn.layer?.cornerRadius = 10
        quitBtn.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.04).cgColor
        quitBtn.layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
        quitBtn.layer?.borderWidth = 1.0
        quitBtn.contentTintColor = NSColor(calibratedRed: 0.94, green: 0.27, blue: 0.27, alpha: 0.9)
        quitBtn.target = self
        quitBtn.action = #selector(quitApp)
        container.addSubview(quitBtn)
        
        updateStatusUI()
    }
    
    public func updateStatusUI() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let isRunning = FlikServer.shared.isRunning
            let port = FlikServer.shared.port
            
            if isRunning {
                self.statusDot.layer?.backgroundColor = NSColor.systemGreen.cgColor
                self.statusTitleLabel.stringValue = "RECEIVER ACTIVE"
                self.statusTitleLabel.textColor = NSColor.systemGreen
                self.statusSubLabel.stringValue = "Listening on Port \(port) • Ready for phone throws"
                self.powerButton.title = "SWITCH RECEIVER OFF"
                self.powerButton.layer?.backgroundColor = NSColor(calibratedRed: 0.85, green: 0.20, blue: 0.20, alpha: 0.9).cgColor
            } else {
                self.statusDot.layer?.backgroundColor = NSColor.systemGray.cgColor
                self.statusTitleLabel.stringValue = "RECEIVER OFF"
                self.statusTitleLabel.textColor = NSColor.systemGray
                self.statusSubLabel.stringValue = "Paused • Incoming transfers are disabled"
                self.powerButton.title = "SWITCH RECEIVER ON"
                self.powerButton.layer?.backgroundColor = NSColor(calibratedRed: 0.10, green: 0.72, blue: 0.45, alpha: 0.9).cgColor
            }
            
            self.dropZoneView?.updateStatus()
        }
    }
    
    public func updatePhoneStatus() {
        DispatchQueue.main.async { [weak self] in
            self?.dropZoneView?.updateStatus()
        }
    }
    
    @objc private func togglePower() {
        if FlikServer.shared.isRunning {
            FlikServer.shared.stop()
        } else {
            FlikServer.shared.start()
        }
        updateStatusUI()
    }
    
    @objc private func saveAllCards() {
        FloatingCardManager.shared.promptSaveAll()
    }
    
    @objc private func openFolder() {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        let folder = downloads.appendingPathComponent("Nox Flick Received", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: folder.path)
    }
    
    @objc private func simulateFlick() {
        let size = NSSize(width: 400, height: 300)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor(red: 0.10, green: 0.12, blue: 0.22, alpha: 1.0).setFill()
        NSRect(origin: .zero, size: size).fill()
        
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 22),
            .foregroundColor: NSColor.white
        ]
        let text = "NoxFlick Test"
        (text as NSString).draw(at: NSPoint(x: 120, y: 135), withAttributes: attributes)
        image.unlockFocus()
        
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("test_flick_\(Int(Date().timeIntervalSince1970)).png")
        if let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) {
            try? png.write(to: fileURL)
            
            let meta = FlickMetadata(
                fileName: fileURL.lastPathComponent,
                fileSize: Int64(png.count),
                mimeType: "image/png",
                flickAngle: Double.random(in: -15...15),
                flickVelocity: 1.6,
                aimX: Double.random(in: -0.7...0.7),
                senderName: "Local Test"
            )
            FloatingCardManager.shared.showCard(fileURL: fileURL, metadata: meta)
        }
    }
    
    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
    
    public func windowWillClose(_ notification: Notification) {
        // Keeps the receiver running in the menu bar when the user closes the window with the red 'x'
    }
}
