import Foundation

@MainActor
final class ResponsePlayer {

    private let audioManager: AudioManager

    init(audioManager: AudioManager) {
        self.audioManager = audioManager
    }

    /// Speaks each audio string in order, joining with a short pause marker.
    /// RulesEngine.evaluate() is responsible for all formatting — no templates here.
    func play(_ audioStrings: [String]) {
        guard !audioStrings.isEmpty else { return }
        audioManager.speak(audioStrings.joined(separator: " "))
    }
}
