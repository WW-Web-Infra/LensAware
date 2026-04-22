import Foundation

// MARK: - RulesEngine

// @MainActor so that `lastVisionAnalysis` and `lastError` can be safely written
// from within async methods and read synchronously by HealthDetectionManager.
@MainActor
final class RulesEngine {

    // Stable UUIDs for built-in system profiles — must not change between launches.
    static let healthProfileID = UUID(uuidString: "6BA7B810-9DAD-11D1-80B4-00C04FD430C8")!
    static let qrProfileID     = UUID(uuidString: "6BA7B811-9DAD-11D1-80B4-00C04FD430C8")!

    /// Set after every process() call. HealthDetectionManager reads this
    /// to update its published lastAnalysis property.
    private(set) var lastVisionAnalysis: LensAnalysis?
    /// Set on API failure; nil on success.
    private(set) var lastError: Error?

    private let visionService: ClaudeVisionService

    init(visionService: ClaudeVisionService) {
        self.visionService = visionService
    }

    // MARK: - 1. defaultProfiles

    func defaultProfiles(tenantId: String = "default_tenant") -> [LensProfile] {
        let healthRules: [Rule] = [
            Rule(id: UUID(), profileId: Self.healthProfileID, tenantId: tenantId,
                 trigger: "food_detected",    actionType: .callVisionAPI,
                 actionConfigJSON: nil, responseTemplate: nil, priority: 0, isActive: true),
            Rule(id: UUID(), profileId: Self.healthProfileID, tenantId: tenantId,
                 trigger: "monitor_detected", actionType: .callVisionAPI,
                 actionConfigJSON: nil, responseTemplate: nil, priority: 1, isActive: true),
            Rule(id: UUID(), profileId: Self.healthProfileID, tenantId: tenantId,
                 trigger: "meal_context",     actionType: .callVisionAPI,
                 actionConfigJSON: nil, responseTemplate: nil, priority: 2, isActive: true),
        ]

        let qrRules: [Rule] = [
            Rule(id: UUID(), profileId: Self.qrProfileID, tenantId: tenantId,
                 trigger: "qr_detected", actionType: .decodeQR,
                 actionConfigJSON: nil, responseTemplate: nil, priority: 0, isActive: true),
        ]

        return [
            LensProfile(
                id:               Self.healthProfileID,
                tenantId:         tenantId,
                name:             "Health",
                description:      "Food nutrition, ergonomics, and mindful eating coaching.",
                triggerType:      .visionAI,
                datasetType:      .llmOnly,
                datasetConfigJSON: nil,
                tone:             .coach,
                isActive:         true,
                isSystem:         true,
                createdAt:        Date(),
                rules:            healthRules
            ),
            LensProfile(
                id:               Self.qrProfileID,
                tenantId:         tenantId,
                name:             "QR Scanner",
                description:      "Decodes QR codes and reads URLs aloud.",
                triggerType:      .qrCode,
                datasetType:      .urlLookup,
                datasetConfigJSON: nil,
                tone:             .guide,
                isActive:         false,
                isSystem:         true,
                createdAt:        Date(),
                rules:            qrRules
            ),
        ]
    }

    // MARK: - 2. process (main entry point — routes by triggerType)

    func process(imageData: Data, profile: LensProfile) async -> [String] {
        lastVisionAnalysis = nil
        lastError = nil

        switch profile.triggerType {
        case .visionAI:
            return await handleVisionAI(imageData: imageData, profile: profile)
        case .qrCode:
            return ["QR scanning — coming in next build"]
        case .textOCR:
            return ["OCR — coming soon"]
        default:
            return await handleVisionAI(imageData: imageData, profile: profile)
        }
    }

    // MARK: - 3. seedDefaultProfiles (call once on app launch)

    func seedDefaultProfiles(database: DatabaseManager, tenantId: String) async {
        let existing = await database.fetchAllProfiles(tenantId: tenantId)
        let defaults = defaultProfiles(tenantId: tenantId)

        for profile in defaults {
            guard !existing.contains(where: { $0.id == profile.id }) else { continue }
            try? await database.saveProfile(profile)
        }

        if await database.fetchActiveProfile(tenantId: tenantId) == nil {
            try? await database.setActiveProfile(id: Self.healthProfileID, tenantId: tenantId)
        }
    }

    // MARK: - Private: handleVisionAI

    private func handleVisionAI(imageData: Data, profile: LensProfile) async -> [String] {
        do {
            let analysis = try await visionService.analyze(imageData: imageData)
            lastVisionAnalysis = analysis

            return profile.rules
                .filter  { $0.isActive }
                .sorted  { $0.priority < $1.priority }
                .filter  { triggerFires($0, for: analysis) }
                .compactMap { buildAudioResponse(rule: $0, analysis: analysis, tone: profile.tone) }
        } catch {
            lastError = error
            return []
        }
    }

    // MARK: - Private: buildAudioResponse (tone-aware)

    private func buildAudioResponse(rule: Rule,
                                    analysis: LensAnalysis,
                                    tone: ToneType) -> String? {
        switch rule.trigger {

        case "food_detected":
            guard analysis.foodAnalysis.foodDetected else { return nil }
            let food = analysis.foodAnalysis
            let type = food.mealType.capitalized
            let cal  = food.totalCalories
            if food.items.isEmpty {
                switch tone {
                case .coach:     return "\(type). \(cal) calories."
                case .guide:     return "Looks like \(type.lowercased()) — around \(cal) calories."
                case .companion: return "\(type). About \(cal) calories."
                case .alert:     return "\(cal) calories."
                }
            }
            let top     = food.items[0]
            let protein = Int(top.proteinG)
            let carbs   = Int(top.carbsG)
            switch tone {
            case .coach:
                return "\(type). \(cal) calories — \(protein)g protein, \(carbs)g carbs."
            case .guide:
                return "Looks like \(type.lowercased()) — around \(cal) calories."
            case .companion:
                return "\(type). About \(cal) calories."
            case .alert:
                return "\(cal) calories."
            }

        case "monitor_detected":
            guard analysis.ergonomics.assessment == "needs_adjustment" else { return nil }
            let s = analysis.ergonomics.suggestion
            switch tone {
            case .coach, .companion, .alert:
                return s
            case .guide:
                return "Your monitor position could use a small adjustment. \(s)"
            }

        case "meal_context":
            guard analysis.foodAnalysis.foodDetected else { return nil }
            let score = analysis.diningContext.mindfulEatingScore
            switch (tone, score) {
            case (.coach,     1...2): return "You're eating with distractions. Try stepping away from the screen."
            case (.coach,     3...4): return "Put down distractions to get more from your meal."
            case (.coach,     5...6): return "Decent focus. Room to improve your eating environment."
            case (.coach,     7...):  return "Good mindful eating. Enjoy your meal."
            case (.guide,     1...2): return "It looks like you're eating while distracted — even a short screen break helps."
            case (.guide,     3...4): return "A little distracted. Try to focus on your food."
            case (.guide,     7...):  return "Lovely, you're eating mindfully."
            case (.companion, 1...2): return "Maybe take a screen break while you eat."
            case (.companion, 7...):  return "Enjoying your meal. Nice."
            case (.alert,     1...2): return "Distracted eating."
            default:                  return nil
            }

        default:
            return nil
        }
    }

    // MARK: - Private: triggerFires

    private func triggerFires(_ rule: Rule, for analysis: LensAnalysis) -> Bool {
        switch rule.trigger {
        case "food_detected":    return analysis.foodAnalysis.foodDetected
        case "monitor_detected": return analysis.ergonomics.assessment == "needs_adjustment"
        case "meal_context":     return analysis.foodAnalysis.foodDetected
        default:                 return false
        }
    }
}
