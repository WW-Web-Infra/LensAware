import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @EnvironmentObject private var glassesManager: GlassesManager
    @EnvironmentObject private var detectionManager: HealthDetectionManager

    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Home",    systemImage: "house.fill") }

            DetectView()
                .tabItem { Label("Detect",  systemImage: "camera.viewfinder") }

            RulesView()
                .tabItem { Label("Rules",   systemImage: "list.bullet.clipboard.fill") }

            HistoryView()
                .tabItem { Label("History", systemImage: "clock.fill") }
        }
        .task {
            await appState.setup()
            await detectionManager.setup()
            glassesManager.startConnection()
        }
    }
}
