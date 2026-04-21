import Foundation

// MARK: - ResponsePlayer

@MainActor
final class ResponsePlayer {

    private let audioManager: AudioManager

    init(audioManager: AudioManager) {
        self.audioManager = audioManager
    }

    // MARK: - Public

    /// Formats and speaks all fired rules for a given analysis response.
    /// Food rule fires first; ergonomics second; mindfulness third.
    /// Stays silent if no rules matched.
    func play(analysis: HealthAnalysisResponse, firedRules: [Rule]) {
        let lines = firedRules.compactMap { rule in
            formatted(template: rule.responseTemplate, analysis: analysis)
        }
        guard !lines.isEmpty else { return }
        audioManager.speak(lines.joined(separator: " "))
    }

    // MARK: - Template substitution

    private func formatted(template: String, analysis: HealthAnalysisResponse) -> String? {
        var text = template

        // {meal_type} — first food item name or "meal"
        let mealType = analysis.foodAnalysis.items.first?.name ?? "meal"
        text = text.replacingOccurrences(of: "{meal_type}", with: mealType)

        // {calories} — total calories as integer string
        text = text.replacingOccurrences(of: "{calories}", with: "\(analysis.foodAnalysis.totalCalories)")

        // {suggestion} — ergonomics suggestion text
        text = text.replacingOccurrences(of: "{suggestion}", with: analysis.ergonomics.suggestion)

        // {score} — mindful eating score
        text = text.replacingOccurrences(of: "{score}", with: "\(analysis.diningContext.mindfulEatingScore)")

        // {location} — dining location
        text = text.replacingOccurrences(of: "{location}", with: analysis.diningContext.location)

        return text.isEmpty ? nil : text
    }
}
