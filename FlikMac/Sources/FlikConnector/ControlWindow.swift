import AppKit
import Foundation

public final class ControlWindowController: NSWindowController, NSWindowDelegate, @unchecked Sendable {
    public static let shared = ControlWindowController()
    
    private var statusDot: NSView!
    private var statusTitleLabel: NSTextField!
    private var statusSubLabel: NSTextField!
    private var powerButton: NSButton!
    private var hostLabel: NSTextField!
    
    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 540),
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
        let iconView = NSImageView(frame: NSRect(x: (400 - 80) / 2, y: 405, width: 80, height: 80))
        if let iconImage = NSImage(named: "AppIcon") ?? NSImage(contentsOfFile: "/Users/naveen/Downloads/flick file transfer/FlikMac/Resources/AppIcon.png") {
            iconView.image = iconImage
        } else {
            iconView.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil)
        }
        iconView.wantsLayer = true
        iconView.layer?.cornerRadius = 20
        iconView.layer?.masksToBounds = true
        iconView.layer?.borderColor = NSColor(calibratedRed: 0.49, green: 0.23, blue: 0.93, alpha: 0.6).cgColor
        iconView.layer?.borderWidth = 1.5
        container.addSubview(iconView)
        
        // 2. Title & Subtitle
        let titleLabel = NSTextField(labelWithString: "NoxFlick")
        titleLabel.frame = NSRect(x: 20, y: 365, width: 360, height: 30)
        titleLabel.alignment = .center
        titleLabel.font = NSFont.systemFont(ofSize: 24, weight: .bold)
        titleLabel.textColor = .white
        container.addSubview(titleLabel)
        
        let subLabel = NSTextField(labelWithString: "Kinetic Spatial File Transfer")
        subLabel.frame = NSRect(x: 20, y: 343, width: 360, height: 18)
        subLabel.alignment = .center
        subLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        subLabel.textColor = NSColor(calibratedRed: 0.58, green: 0.64, blue: 0.72, alpha: 1.0)
        container.addSubview(subLabel)
        
        // 3. Power & Status Card
        let statusCard = NSView(frame: NSRect(x: 24, y: 198, width: 352, height: 128))
        statusCard.wantsLayer = true
        statusCard.layer?.cornerRadius = 16
        statusCard.layer?.backgroundColor = NSColor(calibratedRed: 0.08, green: 0.09, blue: 0.14, alpha: 0.9).cgColor
        statusCard.layer?.borderColor = NSColor(calibratedRed: 0.2, green: 0.22, blue: 0.32, alpha: 0.8).cgColor
        statusCard.layer?.borderWidth = 1.0
        container.addSubview(statusCard)
        
        // Status Dot
        statusDot = NSView(frame: NSRect(x: 18, y: 92, width: 10, height: 10))
        statusDot.wantsLayer = true
        statusDot.layer?.cornerRadius = 5
        statusDot.layer?.backgroundColor = NSColor.systemGreen.cgColor
        statusCard.addSubview(statusDot)
        
        // Status Title
        statusTitleLabel = NSTextField(labelWithString: "RECEIVER ACTIVE")
        statusTitleLabel.frame = NSRect(x: 36, y: 88, width: 280, height: 18)
        statusTitleLabel.font = NSFont.systemFont(ofSize: 12, weight: .bold)
        statusTitleLabel.textColor = .white
        statusCard.addSubview(statusTitleLabel)
        
        // Status Subtitle
        statusSubLabel = NSTextField(labelWithString: "Listening on Port 52840 • Bonjour: _flick._tcp")
        statusSubLabel.frame = NSRect(x: 36, y: 70, width: 290, height: 16)
        statusSubLabel.font = NSFont.systemFont(ofSize: 11)
        statusSubLabel.textColor = NSColor.white.withAlphaComponent(0.6)
        statusCard.addSubview(statusSubLabel)
        
        // Big Power Button
        powerButton = NSButton(frame: NSRect(x: 18, y: 14, width: 316, height: 44))
        powerButton.title = "SWITCH RECEIVER OFF"
        powerButton.font = NSFont.systemFont(ofSize: 13, weight: .bold)
        powerButton.isBordered = false
        powerButton.wantsLayer = true
        powerButton.layer?.cornerRadius = 10
        powerButton.layer?.backgroundColor = NSColor(calibratedRed: 0.49, green: 0.23, blue: 0.93, alpha: 0.9).cgColor
        powerButton.contentTintColor = .white
        powerButton.target = self
        powerButton.action = #selector(togglePower)
        statusCard.addSubview(powerButton)
        
        // 4. Action Buttons
        let openFolderBtn = NSButton(frame: NSRect(x: 24, y: 136, width: 170, height: 42))
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
        
        let testFlickBtn = NSButton(frame: NSRect(x: 206, y: 136, width: 170, height: 42))
        testFlickBtn.title = "🚀 Simulate Flick"
        testFlickBtn.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        testFlickBtn.isBordered = false
        testFlickBtn.wantsLayer = true
        testFlickBtn.layer?.cornerRadius = 10
        testFlickBtn.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
        testFlickBtn.contentTintColor = .white
        testFlickBtn.target = self
        testFlickBtn.action = #selector(simulateFlick)
        container.addSubview(testFlickBtn)
        
        // 5. Host info
        let hostName = Host.current().localizedName ?? "MacBook"
        hostLabel = NSTextField(labelWithString: "Mac: \(hostName) • Auto-Discovered on LAN")
        hostLabel.frame = NSRect(x: 20, y: 92, width: 360, height: 18)
        hostLabel.alignment = .center
        hostLabel.font = NSFont.systemFont(ofSize: 11)
        hostLabel.textColor = NSColor.white.withAlphaComponent(0.45)
        container.addSubview(hostLabel)
        
        // 6. Close / Quit Button
        let quitBtn = NSButton(frame: NSRect(x: 24, y: 32, width: 352, height: 42))
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
