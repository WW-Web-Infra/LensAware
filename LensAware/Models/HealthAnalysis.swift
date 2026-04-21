import Foundation

// MARK: - Food

struct FoodItem: Codable, Sendable {
    let name: String
    let calories: Int
    let proteinG: Double
    let carbsG: Double
    let fatG: Double

    enum CodingKeys: String, CodingKey {
        case name, calories
        case proteinG = "protein_g"
        case carbsG   = "carbs_g"
        case fatG     = "fat_g"
    }
}

struct FoodAnalysis: Codable, Sendable {
    let foodDetected: Bool
    let items: [FoodItem]
    let totalCalories: Int

    enum CodingKeys: String, CodingKey {
        case foodDetected  = "food_detected"
        case items
        case totalCalories = "total_calories"
    }
}

// MARK: - Dining context

struct DiningContext: Codable, Sendable {
    let location: String
    let screenVisible: Bool
    let eatingAlone: Bool
    let mindfulEatingScore: Int  // 1–5

    enum CodingKeys: String, CodingKey {
        case location
        case screenVisible      = "screen_visible"
        case eatingAlone        = "eating_alone"
        case mindfulEatingScore = "mindful_eating_score"
    }
}

// MARK: - Ergonomics

struct ErgonomicsAnalysis: Codable, Sendable {
    let monitorPosition: String
    let assessment: String
    let suggestion: String

    enum CodingKeys: String, CodingKey {
        case monitorPosition = "monitor_position"
        case assessment
        case suggestion
    }
}

// MARK: - Combined response

struct HealthAnalysisResponse: Codable, Sendable {
    let foodAnalysis: FoodAnalysis
    let diningContext: DiningContext
    let ergonomics: ErgonomicsAnalysis

    enum CodingKeys: String, CodingKey {
        case foodAnalysis = "food_analysis"
        case diningContext = "dining_context"
        case ergonomics
    }
}
