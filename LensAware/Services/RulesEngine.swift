import Foundation

final class RulesEngine {

    // MARK: - 1. defaultHealthRules

    func defaultHealthRules() -> [Rule] {
        [
            Rule(
                id: UUID(),
                tenantId: "health_user_001",
                profile: .health,
                trigger: "food_detected",
                action: "estimate_nutrition",
                tone: .coach,
                recipient: "self",
                isActive: true
            ),
            Rule(
                id: UUID(),
                tenantId: "health_user_001",
                profile: .health,
                trigger: "monitor_detected",
                action: "ergonomics_check",
                tone: .coach,
                recipient: "self",
                isActive: true
            ),
            Rule(
                id: UUID(),
                tenantId: "health_user_001",
                profile: .health,
                trigger: "meal_context",
                action: "mindful_eating",
                tone: .coach,
                recipient: "self",
                isActive: true
            )
        ]
    }

    // MARK: - 2. evaluate

    /// Filters active rules, checks trigger conditions against the analysis,
    /// and returns ordered audio strings ready to be played.
    func evaluate(analysis: LensAnalysis, rules: [Rule]) -> [String] {
        rules
            .filter { $0.isActive }
            .filter { triggerFires($0, for: analysis) }
            .compactMap { buildAudioResponse(rule: $0, analysis: analysis) }
    }

    // MARK: - 3. buildAudioResponse

    /// Maps a rule trigger to the matching fields in LensAnalysis and returns
    /// a natural-language audio string, or nil if there is nothing to say.
    func buildAudioResponse(rule: Rule, analysis: LensAnalysis) -> String? {
        switch rule.trigger {

        case "food_detected":
            guard analysis.foodAnalysis.foodDetected else { return nil }
            let food = analysis.foodAnalysis
            guard !food.items.isEmpty else {
                return "\(food.mealType.capitalized). About \(food.totalCalories) calories."
            }
            let top     = food.items[0]
            let protein = Int(top.proteinG)
            let carbs   = Int(top.carbsG)
            return "\(food.mealType.capitalized). About \(food.totalCalories) calories — \(protein)g protein, \(carbs)g carbs."

        case "monitor_detected":
            guard analysis.ergonomics.assessment == "needs_adjustment" else { return nil }
            return analysis.ergonomics.suggestion

        case "meal_context":
            guard analysis.foodAnalysis.foodDetected else { return nil }
            switch analysis.diningContext.mindfulEatingScore {
            case 1...2: return "You're eating with distractions. Try stepping away from the screen for this meal."
            case 3:     return "Put down distractions to get more from your meal."
            case 4...5: return "Good mindful eating. Enjoy your meal."
            default:    return nil
            }

        default:
            return nil
        }
    }

    // MARK: - Private

    private func triggerFires(_ rule: Rule, for analysis: LensAnalysis) -> Bool {
        switch rule.trigger {
        case "food_detected":    return analysis.foodAnalysis.foodDetected
        case "monitor_detected": return analysis.ergonomics.assessment == "needs_adjustment"
        case "meal_context":     return analysis.foodAnalysis.foodDetected
        default:                 return false
        }
    }
}
