import Foundation

struct Rule: Codable, Sendable {
    let tenantId: String
    let profile: String
    let trigger: String
    let dataset: String?
    let action: String
    let responseTemplate: String
    let tone: String
    let recipient: String
    let language: String

    enum CodingKeys: String, CodingKey {
        case tenantId        = "tenant_id"
        case profile
        case trigger
        case dataset
        case action
        case responseTemplate = "response_template"
        case tone
        case recipient
        case language
    }
}
