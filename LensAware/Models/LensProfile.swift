import Foundation

// MARK: - TriggerType

enum TriggerType: String, Codable, Sendable {
    case visionAI
    case qrCode
    case textOCR
    case faceRecognition
    case objectDetection
    case combined
}

// MARK: - ActionType

enum ActionType: String, Codable, Sendable {
    case callVisionAPI
    case decodeQR
    case runOCR
    case lookupLocal
    case fetchURL
}

// MARK: - DatasetType

enum DatasetType: String, Codable, Sendable {
    case builtInNutrition
    case builtInErgonomics
    case urlLookup
    case localJSON
    case cloudAPI
    case llmOnly
}

// MARK: - LensProfile

struct LensProfile: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let tenantId: String
    let name: String
    let description: String
    let triggerType: TriggerType
    let datasetType: DatasetType
    let datasetConfigJSON: String?
    let tone: ToneType
    var isActive: Bool
    let isSystem: Bool
    let createdAt: Date
    var rules: [Rule]
}
