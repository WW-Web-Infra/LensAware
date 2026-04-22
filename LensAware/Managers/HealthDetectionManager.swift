import Foundation

// MARK: - Detection state

enum HealthDetectionState: Equatable {
    case idle
    case analyzing
    case responded(LensAnalysis)
    case failed(String)

    static func == (lhs: HealthDetectionState, rhs: HealthDetectionState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.analyzing, .analyzing): return true
        case (.responded, .responded):                 return true
        case (.failed(let a), .failed(let b)):         return a == b
        default:                                       return false
        }
    }
}

// MARK: - HealthDetectionManager

@MainActor
final class HealthDetectionManager: ObservableObject {
    @Published private(set) var detectionState: HealthDetectionState = .idle
    @Published private(set) var lastResponse: LensAnalysis?
    @Published private(set) var lastFiredRules: [Rule] = []

    private let visionService: ClaudeVisionService?
    private let rulesEngine   = RulesEngine()
    private let audioManager  = AudioManager()
    private let dbManager     = DatabaseManager()
    private lazy var responsePlayer = ResponsePlayer(audioManager: audioManager)

    private let activeProfile = "health"
    private let profileId     = 1

    // MARK: - Init

    init() {
        do {
            visionService = try ClaudeVisionService()
        } catch {
            visionService = nil
            detectionState = .failed(error.localizedDescription)
        }
    }

    // MARK: - Public

    func resetState() {
        detectionState = .idle
    }
}

// MARK: - CameraFrameDelegate

extension HealthDetectionManager: CameraFrameDelegate {
    nonisolated func didReceiveFrame(_ imageData: Data) {
        Task { @MainActor in
            await processFrame(imageData)
        }
    }

    private func processFrame(_ imageData: Data) async {
        guard let service = visionService else { return }
        guard case .idle = detectionState else { return }

        detectionState = .analyzing

        do {
            let analysis   = try await service.analyze(imageData: imageData)
            let firedRules = await rulesEngine.triggers(for: analysis, profile: activeProfile)

            lastResponse   = analysis
            lastFiredRules = firedRules
            detectionState = .responded(analysis)

            responsePlayer.play(analysis: analysis, firedRules: firedRules)

            Task.detached { [dbManager, profileId, analysis] in
                await dbManager.saveMeal(profileId: profileId, analysis: analysis)
                await dbManager.saveErgonomicEvent(profileId: profileId, analysis: analysis)
            }
        } catch {
            detectionState = .failed(error.localizedDescription)
            Task {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                if case .failed = detectionState { detectionState = .idle }
            }
        }
    }
}
