import AppKit
import SwiftUI

public final class StatusBarController: NSObject, @unchecked Sendable {
    public static let shared = StatusBarController()
    
    private var statusItem: NSStatusItem?
    
    private override init() {
        super.init()
    }
    
    public func setup() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            
            if let button = self.statusItem?.button {
                let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
                let image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "Nox Flick")?
                    .withSymbolConfiguration(config)
                image?.isTemplate = true
                button.image = image
                button.toolTip = "Nox Flick (Ready for your phone)"
            }
            
            self.rebuildMenu()
        }
    }
    
    public func rebuildMenu() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let menu = NSMenu()
            
            let headerItem = NSMenuItem(title: "⚡ NoxFlick", action: nil, keyEquivalent: "")
            headerItem.isEnabled = false
            menu.addItem(headerItem)
            
            let status = FlikServer.shared.isRunning ? "🟢 Receiver: Online (Port \(FlikServer.shared.port))" : "🔴 Receiver: Paused"
            let statusItem = NSMenuItem(title: status, action: nil, keyEquivalent: "")
            statusItem.isEnabled = false
            menu.addItem(statusItem)
            
            let phoneStatus: String
            if let name = ReverseFlikClient.shared.activePhoneName, let host = ReverseFlikClient.shared.activePhoneHost {
                phoneStatus = "📱 Phone: \(name) (\(host))"
            } else {
                phoneStatus = "📱 Phone: Searching on Wi-Fi..."
            }
            let phoneItem = NSMenuItem(title: phoneStatus, action: nil, keyEquivalent: "")
            phoneItem.isEnabled = false
            menu.addItem(phoneItem)
            
            menu.addItem(NSMenuItem.separator())
            
            let flickToPhone = NSMenuItem(title: "📱 Flick File to Phone...", action: #selector(self.flickToPhoneClicked), keyEquivalent: "f")
            flickToPhone.target = self
            menu.addItem(flickToPhone)
            
            let cardCount = FloatingCardManager.shared.activeCardCount
            let saveTitle = cardCount > 0 ? "💾 Save All Received Cards (\(cardCount))..." : "💾 Save All Received Cards..."
            let saveAll = NSMenuItem(title: saveTitle, action: #selector(self.saveAllClicked), keyEquivalent: "s")
            saveAll.keyEquivalentModifierMask = [.command, .shift]
            saveAll.target = self
            menu.addItem(saveAll)
            
            let dismissAll = NSMenuItem(title: "✕ Dismiss All Floating Cards", action: #selector(self.dismissAllClicked), keyEquivalent: "d")
            dismissAll.keyEquivalentModifierMask = [.option]
            dismissAll.target = self
            menu.addItem(dismissAll)
            
            let openFolder = NSMenuItem(title: "📁 Open Received Files", action: #selector(self.openFolderClicked), keyEquivalent: "o")
            openFolder.target = self
            menu.addItem(openFolder)
            
            menu.addItem(NSMenuItem.separator())
            
            let togglePower = NSMenuItem(
                title: FlikServer.shared.isRunning ? "Turn Receiver OFF" : "Turn Receiver ON",
                action: #selector(self.togglePowerClicked),
                keyEquivalent: "s"
            )
            togglePower.target = self
            menu.addItem(togglePower)
            
            let showWindow = NSMenuItem(title: "🎛️ Open NoxFlick Panel...", action: #selector(self.showWindowClicked), keyEquivalent: "p")
            showWindow.target = self
            menu.addItem(showWindow)
            
            let testFlick = NSMenuItem(title: "🚀 Simulate Incoming Flick", action: #selector(self.testFlickClicked), keyEquivalent: "t")
            testFlick.target = self
            menu.addItem(testFlick)
            
            menu.addItem(NSMenuItem.separator())
            
            let quitItem = NSMenuItem(title: "Quit NoxFlick", action: #selector(self.quitClicked), keyEquivalent: "q")
            quitItem.target = self
            menu.addItem(quitItem)
            
            self.statusItem?.menu = menu
        }
    }
    
    @objc private func flickToPhoneClicked() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Flick to Phone"
        panel.title = "Select Files to Flick to Phone"
        if panel.runModal() == .OK {
            let urls = panel.urls
            guard !urls.isEmpty else { return }
            
            for (idx, url) in urls.enumerated() {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(idx) * 0.15) {
                    ReverseFlikClient.shared.sendFileToPhone(fileURL: url) { success, message in
                        if idx == urls.count - 1 {
                            DispatchQueue.main.async {
                                let alert = NSAlert()
                                alert.messageText = success ? "🚀 Flicked to Phone!" : "❌ Reverse Flick Failed"
                                alert.informativeText = success ? (urls.count > 1 ? "Delivered \(urls.count) files to phone!" : message) : message
                                alert.alertStyle = success ? .informational : .warning
                                alert.runModal()
                            }
                        }
                    }
                }
            }
        }
    }
    
    @objc private func saveAllClicked() {
        FloatingCardManager.shared.promptSaveAll()
    }
    
    @objc private func showWindowClicked() {
        ControlWindowController.shared.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @objc private func togglePowerClicked() {
        if FlikServer.shared.isRunning {
            FlikServer.shared.stop()
        } else {
            FlikServer.shared.start()
        }
        rebuildMenu()
        ControlWindowController.shared.updateStatusUI()
    }
    
    @objc private func dismissAllClicked() {
        FloatingCardManager.shared.closeAll(deleteFiles: false)
    }
    
    @objc private func openFolderClicked() {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        let folder = downloads.appendingPathComponent("Nox Flick Received", isDirectory: true)
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: folder.path)
    }
    
    @objc private func testFlickClicked() {
        let size = NSSize(width: 400, height: 300)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor(red: 0.15, green: 0.45, blue: 0.85, alpha: 1.0).setFill()
        NSRect(origin: .zero, size: size).fill()
        
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 22),
            .foregroundColor: NSColor.white
        ]
        let text = "Nox Flick Card"
        (text as NSString).draw(at: NSPoint(x: 80, y: 135), withAttributes: attributes)
        image.unlockFocus()
        
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("test_flick_\(Int(Date().timeIntervalSince1970)).png")
        if let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) {
            try? png.write(to: fileURL)
            
            let meta = FlickMetadata(
                fileName: fileURL.lastPathComponent,
                fileSize: Int64(png.count),
                mimeType: "image/png",
                flickAngle: Double.random(in: -12...12),
                flickVelocity: 1.5,
                senderName: "Test Device"
            )
            FloatingCardManager.shared.showCard(fileURL: fileURL, metadata: meta)
        }
    }
    
    @objc private func quitClicked() {
        NSApplication.shared.terminate(nil)
    }
}
