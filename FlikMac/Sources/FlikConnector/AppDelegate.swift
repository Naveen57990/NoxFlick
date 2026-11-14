import AppKit
import Foundation
import AudioToolbox

public final class AppDelegate: NSObject, NSApplicationDelegate, FlikServerDelegate {
    
    public func applicationDidFinishLaunching(_ notification: Notification) {
        print("🚀 NoxFlick initializing...")
        
        // Full native macOS app with Dock presence & Window
        NSApp.setActivationPolicy(.regular)
        
        // Setup menu bar controller
        StatusBarController.shared.setup()
        
        // Start server by default
        FlikServer.shared.delegate = self
        FlikServer.shared.start()
        
        // Display Control Panel window
        ControlWindowController.shared.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        print("✨ NoxFlick ready!")
    }
    
    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            ControlWindowController.shared.showWindow(nil)
        }
        return true
    }
    
    public func applicationWillTerminate(_ notification: Notification) {
        FlikServer.shared.stop()
        FloatingCardManager.shared.closeAll(deleteFiles: false)
    }
    
    // MARK: - FlikServerDelegate
    public func serverDidReceiveFile(fileURL: URL, metadata: FlickMetadata) {
        print("📥 Received file: \(metadata.fileName) (\(metadata.fileSize) bytes) from \(metadata.senderName)")
        AudioServicesPlaySystemSound(1001) // Pop sound
        FloatingCardManager.shared.showCard(fileURL: fileURL, metadata: metadata)
    }
    
    public func serverDidReceiveLink(url: URL, senderName: String) {
        print("🔗 Received link: \(url) from \(senderName)")
        AudioServicesPlaySystemSound(1001)
    }
    
    public func serverStatusDidChange(isRunning: Bool, port: UInt16) {
        DispatchQueue.main.async {
            StatusBarController.shared.rebuildMenu()
            ControlWindowController.shared.updateStatusUI()
        }
    }
}
