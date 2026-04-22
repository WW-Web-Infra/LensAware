import Foundation

enum ProfileType: String, Codable, Sendable {
    case health
    case care
}

struct Profile: Sendable {
    let id: Int64?            // nil when creating; set by DB on insert
    let tenantId: String
    let name: String
    let profileType: ProfileType
    let settingsJSON: String?
}
