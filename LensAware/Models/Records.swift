import Foundation

struct MealRecord: Sendable {
    let id: Int64?
    let profileId: Int64
    let timestamp: Date
    let mealType: String
    let foodItemsJSON: String
    let totalCalories: Double
    let context: String
    let screenVisible: Bool
    let eatingAlone: Bool
    let mindfulScore: Int
    let confidence: Double
}

struct ErgonomicEvent: Sendable {
    let id: Int64?
    let profileId: Int64
    let timestamp: Date
    let monitorPosition: String
    let assessment: String
    let recommendation: String
}

struct DailySummary: Sendable {
    let id: Int64?
    let profileId: Int64
    let date: String          // "yyyy-MM-dd"
    let totalCalories: Double
    let mealCount: Int
    let ergonomicAlerts: Int
    let llmSummary: String?
}
