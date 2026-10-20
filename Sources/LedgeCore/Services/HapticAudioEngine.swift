import AppKit

public enum SoundEffect: Sendable {
    case dropSuccess      // "Pop" oder "Purr"
    case conversionDone   // "Tink" (kristallklarer Belohnungs-Sound)
    case dragOut          // "Bottle" (sanftes Lösen)
    case deleteItem       // "Basso" (Papierkorb-Feedback)
    case screenshotTaken  // "Hero" (Kamera-Klick)
    case pinToggled       // "Morse" (mechanischer Schalter)
}

public final class HapticAudioEngine: Sendable {
    public static let shared = HapticAudioEngine()
    
    private init() {}
    
    public func play(_ effect: SoundEffect) {
        DispatchQueue.main.async {
            // 1. Physisches Trackpad-Feedback auslösen
            NSHapticFeedbackManager.defaultPerformer.perform(
                .alignment,
                performanceTime: .now
            )
            
            // 2. Passenden System-Sound abspielen
            let soundName: String
            switch effect {
            case .dropSuccess: soundName = "Pop"
            case .conversionDone: soundName = "Tink"
            case .dragOut: soundName = "Bottle"
            case .deleteItem: soundName = "Basso"
            case .screenshotTaken: soundName = "Hero"
            case .pinToggled: soundName = "Morse"
            }
            
            NSSound(named: soundName)?.play()
        }
    }
}
