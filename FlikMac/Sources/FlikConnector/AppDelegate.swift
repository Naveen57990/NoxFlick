import AppKit
import Foundation
import AudioToolbox

public final class AppDelegate: NSObject, NSApplicationDelegate, FlikServerDelegate {
    
    public func applicationDidFinishLaunching(_ notification: Notification) {
        print("🚀 Nox Flick initializing...")
        
        // Run as menu bar agent (no dock icon, stays unobtrusive)
        NSApp.setActivationPolicy(.accessory)
        
        // Setup controllers
        StatusBarController.shared.setup()
        
        // Start server
        FlikServer.shared.delegate = self
        FlikServer.shared.start()
        
        print("✨ Nox Flick ready!")
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
        }
    }
}
