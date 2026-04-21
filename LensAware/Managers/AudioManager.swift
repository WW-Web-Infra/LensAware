import Foundation
import AVFoundation

@MainActor
final class AudioManager: NSObject, ObservableObject, AVSpeechSynthesizerDelegate, Sendable {
    @Published private(set) var isSpeaking = false

    private let synthesizer = AVSpeechSynthesizer()

    override init() {
        super.init()
        synthesizer.delegate = self
        configureAudioSession()
    }

    // MARK: - Public

    func speak(_ text: String) {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .word)
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.volume = 1.0
        synthesizer.speak(utterance)
        isSpeaking = true
    }

    func stopSpeaking() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    // MARK: - AVSpeechSynthesizerDelegate

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
        }
    }

    // MARK: - Private

    private func configureAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playback,
                mode: .spokenAudio,
                options: [.allowBluetoothHFP, .mixWithOthers]
            )
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            // Non-fatal — TTS will still work through default session
        }
    }
}
