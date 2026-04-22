import AVFoundation

// MARK: - ResponsePlayer

@MainActor
final class ResponsePlayer: NSObject {

    var silentMode = false

    /// Called when the last queued utterance finishes (or the queue is empty after a stop).
    /// HealthDetectionManager uses this to transition responding → idle.
    var onPlaybackComplete: (() -> Void)?

    private let synthesizer = AVSpeechSynthesizer()

    // Each item in the pending queue carries its text and priority context.
    private struct QueueItem {
        let utterance: AVSpeechUtterance
        let isErgonomic: Bool
        let isAcknowledgement: Bool
    }

    private var queue: [QueueItem] = []
    private var currentIsErgonomic = false

    override init() {
        super.init()
        synthesizer.delegate = self
        configureAudioSession()
    }

    // MARK: - Public API

    /// Sequences each string with a 300 ms post-utterance gap.
    /// Ergonomic responses interrupt in-progress food/context responses;
    /// food responses never interrupt each other.
    func play(_ responses: [String]) {
        guard !silentMode, !responses.isEmpty else { return }

        let isErgonomic = responses.contains(where: isErgonomicContent)

        if isErgonomic && synthesizer.isSpeaking && !currentIsErgonomic {
            // Stop at a word boundary — never mid-sentence — then drain
            // non-ergonomic, non-acknowledgement items from the queue.
            synthesizer.stopSpeaking(at: .word)
            queue.removeAll { !$0.isErgonomic && !$0.isAcknowledgement }
        }

        responses
            .map { QueueItem(utterance: makeUtterance($0, gap: true),
                             isErgonomic: isErgonomic,
                             isAcknowledgement: false) }
            .forEach { queue.append($0) }

        if !synthesizer.isSpeaking { playNext() }
    }

    /// Inserts a brief "Got it" at the head of the queue so the user gets
    /// immediate audio feedback while the API call is in flight.
    func playAcknowledgement() {
        guard !silentMode else { return }
        let item = QueueItem(
            utterance: makeUtterance("Got it", gap: false),
            isErgonomic: false,
            isAcknowledgement: true
        )
        queue.insert(item, at: 0)
        if !synthesizer.isSpeaking { playNext() }
    }

    /// Clears the queue and stops any in-progress utterance immediately.
    func stop() {
        queue.removeAll()
        synthesizer.stopSpeaking(at: .immediate)
    }

    // MARK: - Private

    private func playNext() {
        guard !queue.isEmpty else {
            currentIsErgonomic = false
            onPlaybackComplete?()
            return
        }
        let item = queue.removeFirst()
        currentIsErgonomic = item.isErgonomic
        synthesizer.speak(item.utterance)
    }

    private func makeUtterance(_ text: String, gap: Bool) -> AVSpeechUtterance {
        let u = AVSpeechUtterance(string: text)
        u.voice = AVSpeechSynthesisVoice(language: "en-US")
        u.rate = AVSpeechUtteranceDefaultSpeechRate
        u.volume = 1.0
        u.postUtteranceDelay = gap ? 0.3 : 0.0
        return u
    }

    // Heuristic: ergonomic responses are built from monitor/posture analysis.
    private func isErgonomicContent(_ text: String) -> Bool {
        let lower = text.lowercased()
        return ["monitor", "screen", "posture", "neck", "head", "sitting",
                "position", "chair", "back", "ergonomic"].contains { lower.contains($0) }
    }

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio,
                                 options: [.allowBluetoothHFP, .mixWithOthers])
        try? session.setActive(true)
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension ResponsePlayer: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.playNext() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.playNext() }
    }
}
