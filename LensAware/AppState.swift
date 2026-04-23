import Foundation
import Observation

// MARK: - DetectionItem

enum DetectionItem: Identifiable, Sendable {
    case meal(MealRecord)
    case ergonomic(ErgonomicEvent)
    case qrScan(QRScan)

    var id: String {
        switch self {
        case .meal(let m):      return "meal-\(m.id ?? 0)-\(m.timestamp.timeIntervalSince1970)"
        case .ergonomic(let e): return "ergo-\(e.id ?? 0)-\(e.timestamp.timeIntervalSince1970)"
        case .qrScan(let q):    return "qr-\(q.id ?? 0)-\(q.timestamp.timeIntervalSince1970)"
        }
    }

    var timestamp: Date {
        switch self {
        case .meal(let m):      return m.timestamp
        case .ergonomic(let e): return e.timestamp
        case .qrScan(let q):    return q.timestamp
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

        let recentQR    = await dbManager.fetchRecentQRScans(limit: 5)

        let mealItems   = meals.suffix(10).map  { DetectionItem.meal($0) }
        let ergoItems   = ergoEvents.suffix(5).map { DetectionItem.ergonomic($0) }
        let qrItems     = recentQR.map { DetectionItem.qrScan($0) }

        recentDetections = (mealItems + ergoItems + qrItems)
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
}
