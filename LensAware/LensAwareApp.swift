import SwiftUI
import MWDATCore

@main
struct LensAwareApp: App {
    @StateObject private var glassesManager = GlassesManager()
    @StateObject private var detectionManager = HealthDetectionManager()

    init() {
        // configure() throws WearablesError; alreadyConfigured is safe to ignore
        try? Wearables.configure()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(glassesManager)
                .environmentObject(detectionManager)
                .onOpenURL { url in
                    Task { await glassesManager.handleUrl(url) }
                }
        }
    }
}
