import Foundation

enum ToneType: String, Sendable {
    case coach
    case companion
}

struct Rule: Sendable {
    let id: UUID
    let tenantId: String
    let profile: ProfileType
    let trigger: String
    let action: String
    let tone: ToneType
    let recipient: String
    let isActive: Bool
}
