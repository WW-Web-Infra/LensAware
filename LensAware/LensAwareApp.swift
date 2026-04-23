import SwiftUI
import MWDATCore

@main
struct LensAwareApp: App {
    @State   private var appState        = AppState()
    @StateObject private var glassesManager   = GlassesManager()
    @StateObject private var detectionManager = HealthDetectionManager()

    init() {
        // configure() throws WearablesError; alreadyConfigured is safe to ignore
        try? Wearables.configure()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .environmentObject(glassesManager)
                .environmentObject(detectionManager)
                .onOpenURL { url in
                    Task { await glassesManager.handleUrl(url) }
                }
                .onChange(of: glassesManager.isConnected) { _, connected in
                    appState.isGlassesConnected = connected
                }
        }
    }
}
