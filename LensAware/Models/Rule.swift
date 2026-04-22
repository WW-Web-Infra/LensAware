import Foundation

// MARK: - ToneType

enum ToneType: String, Codable, Sendable {
    case coach      // direct, data-rich
    case guide      // warm, narrative
    case companion  // calm, simple, short
    case alert      // brief, urgent
}

// MARK: - Rule

struct Rule: Codable, Identifiable, Sendable {
    let id: UUID
    let profileId: UUID
    let tenantId: String
    let trigger: String
    let actionType: ActionType
    let actionConfigJSON: String?
    let responseTemplate: String?
    let priority: Int
    var isActive: Bool
}
