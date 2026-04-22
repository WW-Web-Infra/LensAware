import Foundation

// CodingKeys are omitted — JSONDecoder uses .convertFromSnakeCase throughout.

struct LensAnalysis: Codable, Sendable {
    let foodAnalysis: FoodAnalysis
    let diningContext: DiningContext
    let ergonomics: ErgonomicsAnalysis
}

struct FoodAnalysis: Codable, Sendable {
    let foodDetected: Bool
    let items: [FoodItem]
    let totalCalories: Int
    let mealType: String
}

struct FoodItem: Codable, Sendable {
    let name: String
    let calories: Int
    let proteinG: Double
    let carbsG: Double
    let fatG: Double
}

struct DiningContext: Codable, Sendable {
    let location: String
    let screenVisible: Bool
    let eatingAlone: Bool
    let mindfulEatingScore: Int
}

struct ErgonomicsAnalysis: Codable, Sendable {
    let monitorPosition: String
    let assessment: String
    let suggestion: String
}
