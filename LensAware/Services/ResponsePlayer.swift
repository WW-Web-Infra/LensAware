import Foundation

@MainActor
final class ResponsePlayer {

    private let audioManager: AudioManager

    init(audioManager: AudioManager) {
        self.audioManager = audioManager
    }

    // MARK: - Public

    func play(analysis: LensAnalysis, firedRules: [Rule]) {
        let lines = firedRules.compactMap { formatted(template: $0.responseTemplate, analysis: analysis) }
        guard !lines.isEmpty else { return }
        audioManager.speak(lines.joined(separator: " "))
    }

    // MARK: - Template substitution

    private func formatted(template: String, analysis: LensAnalysis) -> String? {
        var text = template

        // {meal_type} — meal type from API response ("lunch", "snack", etc.)
        text = text.replacingOccurrences(of: "{meal_type}", with: analysis.foodAnalysis.mealType)

        // {calories} — total calories
        text = text.replacingOccurrences(of: "{calories}", with: "\(analysis.foodAnalysis.totalCalories)")

        // {suggestion} — ergonomics suggestion
        text = text.replacingOccurrences(of: "{suggestion}", with: analysis.ergonomics.suggestion)

        // {score} — mindful eating score
        text = text.replacingOccurrences(of: "{score}", with: "\(analysis.diningContext.mindfulEatingScore)")

        // {location} — dining location
        text = text.replacingOccurrences(of: "{location}", with: analysis.diningContext.location)

        return text.isEmpty ? nil : text
    }
}
