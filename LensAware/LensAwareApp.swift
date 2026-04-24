import SwiftUI
import MWDATCore

@main
struct LensAwareApp: App {
    @State   private var appState        = AppState()
    @StateObject private var glassesManager   = GlassesManager()
    @StateObject private var detectionManager = HealthDetectionManager()
    @State   private var showOnboarding  = false

    init() {
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
                .fullScreenCover(isPresented: $showOnboarding) {
                    OnboardingView {
                        UserDefaults.standard.set(true, forKey: "lensaware_onboarding_complete")
                        showOnboarding = false
                    }
                    .environment(appState)
                    .environmentObject(glassesManager)
                }
                .task {
                    await appState.seedDefaultProfilesIfNeeded()
                    await appState.setup()
                    glassesManager.startConnection()
                    if !UserDefaults.standard.bool(forKey: "lensaware_onboarding_complete") {
                        showOnboarding = true
                    }
                }
        }
    }
}
