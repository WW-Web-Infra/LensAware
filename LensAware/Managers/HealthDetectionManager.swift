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

    private let rulesEngine:    RulesEngine?
    private let responsePlayer = ResponsePlayer()
    private let dbManager      = DatabaseManager()

    private let tenantId:  String
    private let profileId = 1     // integer FK for legacy meals/ergonomic_events tables

    private var activeProfile: LensProfile?

    private var lastAudioFingerprint: String = ""
    private var lastAudioFingerprintTime: Date = .distantPast
    private let deduplicationWindow: TimeInterval = 30

    // MARK: - Init

    init() {
        let config    = Bundle.main.path(forResource: "Config", ofType: "plist")
            .flatMap { NSDictionary(contentsOfFile: $0) }
        tenantId = (config?["TenantID"] as? String) ?? "default_tenant"

        do {
            let svc  = try ClaudeVisionService()
            rulesEngine = RulesEngine(visionService: svc)
        } catch {
            rulesEngine  = nil
            captureState = .error(error.localizedDescription)
        }

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

        if let engine = rulesEngine {
            await engine.seedDefaultProfiles(database: dbManager, tenantId: tenantId)
        }

        activeProfile = await dbManager.fetchActiveProfile(tenantId: tenantId)
            ?? rulesEngine?.defaultProfiles(tenantId: tenantId).first
    }

    // MARK: - Manual capture (button-tap path)

    func captureAndAnalyze(_ imageData: Data) async {
        guard case .idle = captureState else { return }
        captureState = .capturing
        await runPipeline(imageData)
    }

    // MARK: - Public helpers

    func resetCaptureState() { captureState = .idle }
    func clearLastAnalysis()  { lastAnalysis = nil  }

    func setActiveProfile(_ profile: LensProfile) {
        activeProfile = profile
    }
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
        guard let engine = rulesEngine else {
            captureState = .error("Vision service unavailable.")
            return
        }

        let profile = activeProfile ?? engine.defaultProfiles(tenantId: tenantId)[0]

        captureState = .analyzing

        let audioStrings = await engine.process(imageData: imageData, profile: profile)
        lastAnalysis = engine.lastVisionAnalysis

        if let err = engine.lastError {
            captureState = .error(err.localizedDescription)
            Task {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                if case .error = captureState { captureState = .idle }
            }
            return
        }

        if audioStrings.isEmpty {
            captureState = .idle
        } else {
            let fingerprint = audioStrings.joined(separator: "|")
            let now = Date()
            if fingerprint == lastAudioFingerprint,
               now.timeIntervalSince(lastAudioFingerprintTime) < deduplicationWindow {
                captureState = .idle
            } else {
                lastAudioFingerprint = fingerprint
                lastAudioFingerprintTime = now
                captureState = .responding
                responsePlayer.play(audioStrings)
            }
        }

        let qrActions   = engine.lastQRActions
        let qrProfileId = profile.id
        let qrTenantId  = tenantId

        Task.detached { [dbManager, profileId, analysis = engine.lastVisionAnalysis] in
            if let analysis {
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
            for action in qrActions {
                let scan = QRScan(
                    id:            UUID(),
                    profileId:     qrProfileId,
                    tenantId:      qrTenantId,
                    timestamp:     Date(),
                    qrValue:       action.qrValue,
                    audioResponse: action.audioResponse,
                    actionTaken:   action.actionTaken,
                    success:       action.success
                )
                try? await dbManager.saveQRScan(scan)
            }
        }
    }
}
