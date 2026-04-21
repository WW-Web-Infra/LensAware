import Foundation

// MARK: - RulesEngine

actor RulesEngine {

    private var rules: [Rule] = []

    // MARK: - Init

    init() {
        loadRules()
    }

    // MARK: - Public

    /// Returns the first rule matching both trigger and profile, or nil if none found.
    func match(trigger: String, profile: String) -> Rule? {
        rules.first { $0.trigger == trigger && $0.profile == profile }
    }

    /// Returns all triggers that fire given a health analysis response.
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

    // MARK: - Private

    private func loadRules() {
        guard let url = Bundle.main.url(forResource: "rules", withExtension: "json", subdirectory: "Rules"),
              let data = try? Data(contentsOf: url) else {
            rules = Self.defaultRules
            return
        }
        rules = (try? JSONDecoder().decode([Rule].self, from: data)) ?? Self.defaultRules
    }

    // MARK: - Defaults (fallback when rules.json is missing or malformed)

    private static let defaultRules: [Rule] = [
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
