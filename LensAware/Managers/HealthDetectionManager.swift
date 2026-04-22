import Foundation

// MARK: - Capture state

enum CaptureState: Equatable {
    case idle
    case capturing
    case analyzing
    case responding
    case error(String)

    static func == (lhs: CaptureState, rhs: CaptureState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.capturing, .capturing),
             (.analyzing, .analyzing), (.responding, .responding): return true
        case (.error(let a), .error(let b)):                        return a == b
        default:                                                     return false
        }
    }
}

// MARK: - HealthDetectionManager

@MainActor
final class HealthDetectionManager: ObservableObject {
    @Published private(set) var captureState: CaptureState = .idle
    @Published private(set) var lastAnalysis: LensAnalysis?

    private let visionService: ClaudeVisionService?
    private let rulesEngine    = RulesEngine()
    private let responsePlayer = ResponsePlayer()
    private let dbManager      = DatabaseManager()

    private let profileId = 1

    // MARK: - Init

    init() {
        do {
            visionService = try ClaudeVisionService()
        } catch {
            visionService = nil
            captureState = .error(error.localizedDescription)
        }

        // Transition responding → idle when the audio queue drains.
        responsePlayer.onPlaybackComplete = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if case .responding = self.captureState { self.captureState = .idle }
            }
        }
    }

    // MARK: - Setup (call once on app launch)

    func setup() async {
        await dbManager.setupDatabase()
    }

    // MARK: - Manual capture (button-tap path)

    func captureAndAnalyze(_ imageData: Data) async {
        guard case .idle = captureState else { return }
        captureState = .capturing
        responsePlayer.playAcknowledgement()
        await runPipeline(imageData)
    }

    // MARK: - Public helpers

    func resetCaptureState() { captureState = .idle }
    func clearLastAnalysis()  { lastAnalysis = nil  }
}

// MARK: - CameraFrameDelegate (streaming / automatic path)

extension HealthDetectionManager: CameraFrameDelegate {
    nonisolated func didReceiveFrame(_ imageData: Data) {
        Task { @MainActor in await captureAndAnalyze(imageData) }
    }
}

// MARK: - Shared analysis pipeline

private extension HealthDetectionManager {
    func runPipeline(_ imageData: Data) async {
        guard let service = visionService else {
            captureState = .error("Vision service unavailable.")
            return
        }

        captureState = .analyzing

        do {
            let analysis     = try await service.analyze(imageData: imageData)
            let rules        = rulesEngine.defaultHealthRules()
            let audioStrings = rulesEngine.evaluate(analysis: analysis, rules: rules)

            lastAnalysis = analysis

            if audioStrings.isEmpty {
                captureState = .idle
            } else {
                captureState = .responding
                responsePlayer.play(audioStrings)
            }

            Task.detached { [dbManager, profileId, analysis] in
                if analysis.foodAnalysis.foodDetected {
                    let itemsJSON = (try? JSONEncoder().encode(analysis.foodAnalysis.items))
                        .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
                    let meal = MealRecord(
                        id:            nil,
                        profileId:     Int64(profileId),
                        timestamp:     Date(),
                        mealType:      analysis.foodAnalysis.mealType,
                        foodItemsJSON: itemsJSON,
                        totalCalories: Double(analysis.foodAnalysis.totalCalories),
                        context:       analysis.diningContext.location,
                        screenVisible: analysis.diningContext.screenVisible,
                        eatingAlone:   analysis.diningContext.eatingAlone,
                        mindfulScore:  analysis.diningContext.mindfulEatingScore,
                        confidence:    1.0
                    )
                    await dbManager.saveMeal(meal)
                }
                if analysis.ergonomics.assessment == "needs_adjustment" {
                    let event = ErgonomicEvent(
                        id:              nil,
                        profileId:       Int64(profileId),
                        timestamp:       Date(),
                        monitorPosition: analysis.ergonomics.monitorPosition,
                        assessment:      analysis.ergonomics.assessment,
                        recommendation:  analysis.ergonomics.suggestion
                    )
                    await dbManager.saveErgonomicEvent(event)
                }
            }
        } catch {
            captureState = .error(error.localizedDescription)
            Task {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                if case .error = captureState { captureState = .idle }
            }
        }
    }
}
