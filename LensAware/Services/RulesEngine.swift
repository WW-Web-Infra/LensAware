import Foundation

// MARK: - RulesEngine
// Actor serialises all public reads. Internal rules array is nonisolated(unsafe)
// because it is only written once in init (before the actor is shared) and
// read afterwards through actor-isolated methods only.

actor RulesEngine {

    nonisolated(unsafe) private var rules: [Rule] = []

    // MARK: - Init

    init() {
        loadRules()  // nonisolated — safe to call from sync init
    }

    // MARK: - Public

    func match(trigger: String, profile: String) -> Rule? {
        rules.first { $0.trigger == trigger && $0.profile == profile }
    }

    func triggers(for analysis: HealthAnalysisResponse, profile: String) -> [Rule] {
        var fired: [Rule] = []

        if analysis.foodAnalysis.foodDetected,
           let rule = match(trigger: "food_detected", profile: profile) {
            fired.append(rule)
        }

        if analysis.ergonomics.assessment == "needs_adjustment",
           let rule = match(trigger: "ergonomics_alert", profile: profile) {
            fired.append(rule)
        }

        if analysis.foodAnalysis.foodDetected,
           analysis.diningContext.mindfulEatingScore <= 2,
           let rule = match(trigger: "mindful_eating_low", profile: profile) {
            fired.append(rule)
        }

        return fired
    }

    // MARK: - Private (nonisolated — called only from init before actor is shared)

    private nonisolated func loadRules() {
        guard let url = Bundle.main.url(
            forResource: "rules",
            withExtension: "json",
            subdirectory: "Rules"
        ),
        let data = try? Data(contentsOf: url),
        let loaded = try? JSONDecoder().decode([Rule].self, from: data) else {
            rules = Self.defaultRules
            return
        }
        rules = loaded
    }

    private nonisolated static let defaultRules: [Rule] = [
        Rule(
            tenantId: "health_user_001",
            profile: "health",
            trigger: "food_detected",
            dataset: "nutrition_db",
            action: "estimate_nutrition",
            responseTemplate: "{meal_type}, approximately {calories} calories.",
            tone: "coach",
            recipient: "self",
            language: "en"
        ),
        Rule(
            tenantId: "health_user_001",
            profile: "health",
            trigger: "ergonomics_alert",
            dataset: nil,
            action: "ergonomics_nudge",
            responseTemplate: "Posture check. {suggestion}",
            tone: "calm",
            recipient: "self",
            language: "en"
        ),
        Rule(
            tenantId: "health_user_001",
            profile: "health",
            trigger: "mindful_eating_low",
            dataset: nil,
            action: "mindfulness_nudge",
            responseTemplate: "Try putting the screen away while you eat.",
            tone: "gentle",
            recipient: "self",
            language: "en"
        )
    ]
}
