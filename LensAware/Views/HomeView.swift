import SwiftUI

struct HomeView: View {
    @Environment(AppState.self) private var appState
    @EnvironmentObject private var glassesManager: GlassesManager

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    ConnectionStatusPill(
                        isConnected: appState.isGlassesConnected,
                        isSearching: glassesManager.connectionState == .searching
                    ) {
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

                    VStack(spacing: 12) {
                        ForEach(appState.allProfiles) { profile in
                            ProfileCard(
                                profile: profile,
                                isActive: profile.id == appState.activeProfile?.id,
                                appState: appState
                            )
                        }
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

// MARK: - ProfileCard

private struct ProfileCard: View {
    let profile: LensProfile
    let isActive: Bool
    let appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(iconTint.opacity(0.12))
                        .frame(width: 36, height: 36)
                    Image(systemName: iconName)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(iconTint)
                }

                Text(profile.name)
                    .font(.subheadline.weight(.semibold))

                Spacer()

                if isActive {
                    Text("Active")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.blue)
                        .clipShape(Capsule())
                }
            }

            statsRow
        }
        .padding(14)
        .background(Color(.secondarySystemBackground))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(isActive ? Color.blue.opacity(0.4) : Color.clear, lineWidth: 1.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private var statsRow: some View {
        switch profile.triggerType {
        case .visionAI:
            HStack(spacing: 0) {
                miniStat(value: "\(appState.todayMealCount)", label: "Meals", image: "fork.knife", tint: .green)
                Divider().frame(height: 32).padding(.horizontal, 8)
                miniStat(value: "\(Int(appState.todayCalories))", label: "kcal", image: "flame.fill", tint: .orange)
                Divider().frame(height: 32).padding(.horizontal, 8)
                miniStat(value: "\(appState.todayErgonomicAlerts)", label: "Posture", image: "figure.seated.seatbelt", tint: .red)
            }
        case .qrCode:
            let count = appState.recentDetections.filter {
                if case .qrScan = $0 { return true }
                return false
            }.count
            miniStat(value: "\(count)", label: "Recent scans", image: "qrcode", tint: .indigo)
        default:
            EmptyView()
        }
    }

    private func miniStat(value: String, label: String, image: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: image)
                .font(.caption)
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.subheadline.weight(.semibold))
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var iconName: String {
        switch profile.triggerType {
        case .visionAI:        return "figure.run"
        case .qrCode:          return "qrcode"
        case .textOCR:         return "text.viewfinder"
        case .objectDetection: return "cube"
        case .faceRecognition: return "person.crop.circle"
        default:               return "cpu"
        }
    }

    private var iconTint: Color {
        switch profile.triggerType {
        case .visionAI:        return .green
        case .qrCode:          return .indigo
        case .textOCR:         return .orange
        case .objectDetection: return .purple
        case .faceRecognition: return .pink
        default:               return .gray
        }
    }
}
