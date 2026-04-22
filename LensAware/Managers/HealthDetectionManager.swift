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

    private let visionService: ClaudeVisionService?
    private let rulesEngine     = RulesEngine()
    private let responsePlayer  = ResponsePlayer()
    private let dbManager       = DatabaseManager()

    private let profileId = 1

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
        responsePlayer.playAcknowledgement()

        do {
            let analysis     = try await service.analyze(imageData: imageData)
            let activeRules  = rulesEngine.defaultHealthRules()
            let audioStrings = rulesEngine.evaluate(analysis: analysis, rules: activeRules)

            lastResponse   = analysis
            detectionState = .responded(analysis)

            responsePlayer.play(audioStrings)

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
            detectionState = .failed(error.localizedDescription)
            Task {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                if case .failed = detectionState { detectionState = .idle }
            }
        }
    }
}
