import SwiftUI

struct OnboardingScreen6Ready: View {
    let coordinator: OnboardingCoordinator
    let onComplete: () -> Void

    @Environment(AppState.self) private var appState
    @EnvironmentObject private var glassesManager: GlassesManager

    private var healthProfile: LensProfile? {
        appState.allProfiles.first(where: { $0.name == "Health" })
    }

    private var activeRulesCount: Int {
        healthProfile?.rules.filter { coordinator.ruleToggles[$0.id] ?? $0.isActive }.count
        ?? healthProfile?.rules.filter(\.isActive).count
        ?? 0
    }

    private var totalRulesCount: Int { healthProfile?.rules.count ?? 0 }

    private var glassesStatus: String {
        switch glassesManager.connectionState {
        case .connected: return "Glasses connected"
        default: return "Glasses not connected — pair later from Settings"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
                .padding(.bottom, 24)

            Text("You're all set")
                .font(.largeTitle.bold())

            Text("\(activeRulesCount) rules active. \(glassesStatus).")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 8)
                .padding(.horizontal, 32)

            // Profile summary card
            VStack(alignment: .leading, spacing: 12) {
                summaryRow(label: "Name", value: coordinator.userName.isEmpty ? "—" : coordinator.userName)
                Divider()
                summaryRow(label: "Profile", value: coordinator.path == .health ? "Health" : "Custom")
                if coordinator.path == .health {
                    Divider()
                    summaryRow(label: "Target", value: "\(coordinator.calorieTarget) kcal / day")
                }
                Divider()
                summaryRow(label: "Rules active", value: "\(activeRulesCount) of \(totalRulesCount)", valueColor: .green)
            }
            .padding(16)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 24)
            .padding(.top, 32)

            Spacer()

            OnboardingPrimaryButton(title: "Go to home") {
                onComplete()
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 48)
        }
    }

    private func summaryRow(label: String, value: String, valueColor: Color = .primary) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(valueColor)
        }
    }
}
