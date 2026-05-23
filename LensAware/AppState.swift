import Foundation
import Observation

// MARK: - DetectionItem

enum DetectionItem: Identifiable, Sendable {
    case meal(MealRecord)
    case ergonomic(ErgonomicEvent)
    case qrScan(QRScan)
    case customDetection(CustomDetectionRecord)

    var id: String {
        switch self {
        case .meal(let m):             return "meal-\(m.id ?? 0)-\(m.timestamp.timeIntervalSince1970)"
        case .ergonomic(let e):        return "ergo-\(e.id ?? 0)-\(e.timestamp.timeIntervalSince1970)"
        case .qrScan(let q):           return "qr-\(q.id.uuidString)"
        case .customDetection(let c):  return "custom-\(c.id.uuidString)"
        }
    }

    var timestamp: Date {
        switch self {
        case .meal(let m):             return m.timestamp
        case .ergonomic(let e):        return e.timestamp
        case .qrScan(let q):           return q.timestamp
        case .customDetection(let c):  return c.timestamp
        }
    }
}

// MARK: - AppState

@Observable
@MainActor
final class AppState {
    var isGlassesConnected: Bool = false
    var activeProfile: LensProfile?
    var allProfiles: [LensProfile] = []

    var todayMealCount: Int = 0
    var todayCalories: Double = 0
    var todayErgonomicAlerts: Int = 0
    var recentDetections: [DetectionItem] = []

    private let dbManager = DatabaseManager()
    private let tenantId: String

    init() {
        let config = Bundle.main.path(forResource: "Config", ofType: "plist")
            .flatMap { NSDictionary(contentsOfFile: $0) }
        tenantId = (config?["TenantID"] as? String) ?? "default_tenant"
    }

    func setup() async {
        await dbManager.setupDatabase()
        await refreshStats()
        await loadProfiles()
    }

    func refreshStats() async {
        let meals = await dbManager.fetchTodayMeals(profileId: 1)
        todayMealCount  = meals.count
        todayCalories   = meals.reduce(0) { $0 + $1.totalCalories }

        let ergoEvents  = await dbManager.fetchTodayErgonomicEvents()
        todayErgonomicAlerts = ergoEvents.count

        let recentQR      = await dbManager.fetchRecentQRScans(limit: 5)
        let recentCustom  = await dbManager.fetchRecentCustomDetections(limit: 10)

        let mealItems     = meals.suffix(10).map     { DetectionItem.meal($0) }
        let ergoItems     = ergoEvents.suffix(5).map { DetectionItem.ergonomic($0) }
        let qrItems       = recentQR.map             { DetectionItem.qrScan($0) }
        let customItems   = recentCustom.map         { DetectionItem.customDetection($0) }

        recentDetections = (mealItems + ergoItems + qrItems + customItems)
            .sorted { $0.timestamp > $1.timestamp }
    }

    func loadProfiles() async {
        allProfiles   = await dbManager.fetchAllProfiles(tenantId: tenantId)
        activeProfile = allProfiles.first(where: { $0.isActive })
    }

    func setActiveProfile(_ profile: LensProfile) async {
        try? await dbManager.setActiveProfile(id: profile.id, tenantId: tenantId)
        await loadProfiles()
    }

    // MARK: - userName (UserDefaults backed)

    var userName: String {
        get { UserDefaults.standard.string(forKey: "lensaware_user_name") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "lensaware_user_name") }
    }

    // MARK: - seedDefaultProfilesIfNeeded

    func seedDefaultProfilesIfNeeded() async {
        await loadProfiles()
        guard allProfiles.isEmpty else { return }

        let healthId = UUID()
        let healthProfile = LensProfile(
            id: healthId,
            tenantId: tenantId,
            name: "Health",
            description: "Food, ergonomics, and mindful eating",
            triggerType: .visionAI,
            datasetType: .builtInNutrition,
            datasetConfigJSON: nil,
            tone: .coach,
            isActive: true,
            isSystem: true,
            createdAt: Date(),
            rules: [
                Rule(id: UUID(), profileId: healthId, tenantId: tenantId, trigger: "food_detected",   actionType: .callVisionAPI, actionConfigJSON: nil, responseTemplate: nil, priority: 0, isActive: true),
                Rule(id: UUID(), profileId: healthId, tenantId: tenantId, trigger: "screen_detected", actionType: .callVisionAPI, actionConfigJSON: nil, responseTemplate: nil, priority: 1, isActive: true),
                Rule(id: UUID(), profileId: healthId, tenantId: tenantId, trigger: "meal_context",    actionType: .callVisionAPI, actionConfigJSON: nil, responseTemplate: nil, priority: 2, isActive: true),
            ]
        )

        let qrId = UUID()
        let qrProfile = LensProfile(
            id: qrId,
            tenantId: tenantId,
            name: "QR Scanner",
            description: "Scan and decode QR codes instantly",
            triggerType: .qrCode,
            datasetType: .llmOnly,
            datasetConfigJSON: nil,
            tone: .guide,
            isActive: false,
            isSystem: true,
            createdAt: Date().addingTimeInterval(1),
            rules: [
                Rule(id: UUID(), profileId: qrId, tenantId: tenantId, trigger: "qr_code_detected", actionType: .decodeQR, actionConfigJSON: nil, responseTemplate: nil, priority: 0, isActive: true),
            ]
        )

        try? await dbManager.saveProfile(healthProfile)
        try? await dbManager.saveProfile(qrProfile)
        await loadProfiles()
    }

    // MARK: - createProfile

    func createProfile(_ profile: LensProfile) async throws {
        let duplicate = allProfiles.contains {
            $0.name.lowercased() == profile.name.lowercased()
        }
        if duplicate { throw ProfileCreationError.duplicateName }
        try await dbManager.saveProfile(profile)
        await loadProfiles()
    }

    // MARK: - deleteProfile

    func deleteProfile(_ profile: LensProfile) async throws {
        try await dbManager.deleteProfile(id: profile.id)
        await loadProfiles()
        await refreshStats()
    }

    // MARK: - deleteRule

    func deleteRule(_ rule: Rule) async throws {
        try await dbManager.deleteRule(id: rule.id)
        await loadProfiles()
    }

    // MARK: - saveRuleToggle

    func saveRuleToggle(_ rule: Rule) async {
        try? await dbManager.saveRule(rule)
        await loadProfiles()
    }

    // MARK: - saveHealthSettings

    func saveHealthSettings(calorieTarget: Int, goals: Set<String>) async {
        guard let profile = allProfiles.first(where: { $0.name == "Health" }) else { return }
        let goalsArray = Array(goals).sorted()
        let dict: [String: Any] = ["calorie_target": calorieTarget, "health_goals": goalsArray]
        let configJSON = (try? JSONSerialization.data(withJSONObject: dict))
            .flatMap { String(data: $0, encoding: .utf8) }
        let updated = LensProfile(
            id: profile.id,
            tenantId: profile.tenantId,
            name: profile.name,
            description: profile.description,
            triggerType: profile.triggerType,
            datasetType: profile.datasetType,
            datasetConfigJSON: configJSON,
            tone: profile.tone,
            isActive: profile.isActive,
            isSystem: profile.isSystem,
            createdAt: profile.createdAt,
            rules: profile.rules
        )
        try? await dbManager.saveProfile(updated)
        await loadProfiles()
    }
}

// MARK: - ProfileCreationError

enum ProfileCreationError: LocalizedError {
    case duplicateName
    var errorDescription: String? {
        switch self {
        case .duplicateName: return "A profile with this name already exists."
        }
    }
}
