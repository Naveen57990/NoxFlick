import AppKit
import AVFoundation
import CoreAudio
import AudioToolbox

public final class SoundManager: @unchecked Sendable {
    public static let shared = SoundManager()
    
    private var player: AVAudioPlayer?
    
    private init() {}
    
    /// Calculates the precise AVAudioPlayer volume scalar such that:
    /// - Max effective sound output is strictly capped at 50% (0.50) even if Mac system volume is at 100%.
    /// - If Mac system volume is below 50%, it respects that lower level (e.g. 30% -> 30%).
    /// - If Mac is muted, volume is 0.0.
    public func getCappedVolumeScalar() -> Float {
        var defaultOutputDeviceID = AudioDeviceID(0)
        var defaultOutputDeviceIDSize = UInt32(MemoryLayout.size(ofValue: defaultOutputDeviceID))

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let statusDevice = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &defaultOutputDeviceIDSize,
            &defaultOutputDeviceID
        )
        guard statusDevice == noErr else { return 0.50 }

        // Check Mute State
        var isMuted: UInt32 = 0
        var muteSize = UInt32(MemoryLayout.size(ofValue: isMuted))
        var muteAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        if AudioObjectGetPropertyData(defaultOutputDeviceID, &muteAddress, 0, nil, &muteSize, &isMuted) == noErr {
            if isMuted == 1 { return 0.0 }
        }

        // Query Master Volume Scalar (0.0 to 1.0)
        var sysVolume = Float32(1.0)
        var volumeSize = UInt32(MemoryLayout.size(ofValue: sysVolume))
        var volAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        var status = AudioObjectGetPropertyData(
            defaultOutputDeviceID,
            &volAddress,
            0,
            nil,
            &volumeSize,
            &sysVolume
        )

        if status != noErr {
            volAddress.mSelector = kAudioDevicePropertyVolumeScalar
            status = AudioObjectGetPropertyData(
                defaultOutputDeviceID,
                &volAddress,
                0,
                nil,
                &volumeSize,
                &sysVolume
            )
        }

        guard status == noErr else { return 0.50 }

        // If system volume is 0 or less, remain silent
        if sysVolume <= 0.001 {
            return 0.0
        }

        // If Mac system volume > 50%, cap effective output at 50%
        // player.volume * sysVolume = 0.50 => player.volume = 0.50 / sysVolume
        if sysVolume > 0.50 {
            return min(1.0, 0.50 / sysVolume)
        } else {
            // If Mac volume <= 50%, it stays at that lower level
            return 1.0
        }
    }
    
    public func playArrivalChime(aimX: Double) {
        NSLog("🔔 [NoxFlick] playArrivalChime called with aimX: %f", aimX)
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            var soundURL: URL? = Bundle.main.url(forResource: "ArrivalChime", withExtension: "wav")
            if soundURL == nil {
                soundURL = Bundle.main.url(forResource: "ArrivalChime", withExtension: "mp3")
            }
            
            // Check fallback locations if running directly or during dev
            let candidatePaths = [
                "/Applications/NoxFlick.app/Contents/Resources/ArrivalChime.wav",
                "/Applications/NoxFlick.app/Contents/Resources/ArrivalChime.mp3",
                "/Users/naveen/Downloads/flick file transfer/FlikMac/Resources/ArrivalChime.wav",
                "/Users/naveen/Downloads/flick file transfer/FlikMac/Resources/ArrivalChime.mp3",
                "/Users/naveen/Desktop/Dark Folder/09_NoxFlick/Source/Mac/Resources/ArrivalChime.wav"
            ]
            
            if soundURL == nil || !FileManager.default.fileExists(atPath: soundURL!.path) {
                for path in candidatePaths {
                    if FileManager.default.fileExists(atPath: path) {
                        soundURL = URL(fileURLWithPath: path)
                        break
                    }
                }
            }
            
            guard let url = soundURL, FileManager.default.fileExists(atPath: url.path) else {
                AudioServicesPlaySystemSound(1001) // System pop fallback
                return
            }
            
            do {
                self.player = try AVAudioPlayer(contentsOf: url)
                self.player?.prepareToPlay()
                
                // Spatial stereo panning:
                // -0.85 (extreme left speaker) ... 0.0 (center) ... +0.85 (extreme right speaker)
                let panValue = Float(max(-0.85, min(0.85, aimX)))
                self.player?.pan = panValue
                
                // Dynamic capped volume scalar (strictly <= 50% effective max loudness)
                let calculatedVolume = self.getCappedVolumeScalar()
                self.player?.volume = calculatedVolume
                self.player?.play()
            } catch {
                print("Failed to play arrival chime: \(error)")
                AudioServicesPlaySystemSound(1001)
            }
        }
    }
}
