import AppKit
import Foundation
import AudioToolbox

public final class AppDelegate: NSObject, NSApplicationDelegate, FlikServerDelegate {
    
    public func applicationDidFinishLaunching(_ notification: Notification) {
        print("🚀 NoxFlick initializing...")
        
        // Menu bar accessory app (no Dock icon)
        NSApp.setActivationPolicy(.accessory)
        
        // Setup menu bar controller
        StatusBarController.shared.setup()
        
        // Start server by default
        FlikServer.shared.delegate = self
        FlikServer.shared.start()
        
        print("✨ NoxFlick ready in menu bar!")
    }
    
    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        return true
    }
    
    public func applicationWillTerminate(_ notification: Notification) {
        FlikServer.shared.stop()
        FloatingCardManager.shared.closeAll(deleteFiles: false)
    }
    
    // MARK: - FlikServerDelegate
    public func serverDidReceiveFile(fileURL: URL, metadata: FlickMetadata) {
        NSLog("📥 [NoxFlick] serverDidReceiveFile: %@ (%lld bytes) from %@", metadata.fileName, metadata.fileSize, metadata.senderName)
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
