import SwiftUI

struct HomeView: View {
    @Environment(AppState.self) private var appState
    @EnvironmentObject private var glassesManager: GlassesManager

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    ConnectionStatusPill(isConnected: appState.isGlassesConnected) {
                        if appState.isGlassesConnected {
                            glassesManager.disconnect()
                        } else {
                            glassesManager.startConnection()
                        }
                    }

                    if let profile = appState.activeProfile {
                        Label("Active: \(profile.name)", systemImage: "sparkles")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.blue)
                    }

                    LazyVGrid(
                        columns: [GridItem(.flexible()), GridItem(.flexible())],
                        spacing: 12
                    ) {
                        StatCard(
                            title: "Meals Today",
                            value: "\(appState.todayMealCount)",
                            systemImage: "fork.knife",
                            tint: .green
                        )
                        StatCard(
                            title: "Calories",
                            value: "\(Int(appState.todayCalories))",
                            systemImage: "flame.fill",
                            tint: .orange
                        )
                        StatCard(
                            title: "Posture Alerts",
                            value: "\(appState.todayErgonomicAlerts)",
                            systemImage: "figure.seated.seatbelt",
                            tint: .red
                        )
                        StatCard(
                            title: "Profile",
                            value: appState.activeProfile?.name ?? "—",
                            systemImage: "cpu",
                            tint: .purple
                        )
                    }

                    if !appState.recentDetections.isEmpty {
                        Text("Recent")
                            .font(.headline)

                        ForEach(appState.recentDetections.prefix(8)) { item in
                            DetectionBadge(item: item)
                        }
                    } else {
                        ContentUnavailableView(
                            "No Activity Yet",
                            systemImage: "eye.slash",
                            description: Text("Capture a frame to see health insights here.")
                        )
                        .padding(.top, 32)
                    }
                }
                .padding(16)
            }
            .navigationTitle("LensAware")
            .navigationBarTitleDisplayMode(.large)
            .refreshable {
                await appState.refreshStats()
            }
        }
    }
}
