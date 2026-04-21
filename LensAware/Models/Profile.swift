import Foundation

enum ProfileType: String, Codable, Sendable {
    case health
    case care
}

struct Profile: Codable, Sendable {
    let id: Int
    let tenantId: String
    let profileType: ProfileType
    let settingsJSON: String?

    enum CodingKeys: String, CodingKey {
        case id
        case tenantId     = "tenant_id"
        case profileType  = "profile_type"
        case settingsJSON = "settings_json"
    }
}
