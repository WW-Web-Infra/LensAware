import SwiftUI

// MARK: - Onboarding path

enum OnboardingPath {
    case health, care, organisation
}

// MARK: - Coordinator

@Observable
@MainActor
final class OnboardingCoordinator {
    var step: Int = 1
    var path: OnboardingPath = .health
    var userName: String = ""
    var healthGoals: Set<String> = ["Track nutrition", "Ergonomics"]
    var calorieTarget: Int = 2000
    var ruleToggles: [UUID: Bool] = [:]
    var showComingSoon: Bool = false
    var comingSoonMessage: String = ""
    var showProfileCreation: Bool = false

    func next() { if step < 6 { step += 1 } }
    func back() { if step > 1 { step -= 1 } }
}

// MARK: - OnboardingView

struct OnboardingView: View {
    let onComplete: () -> Void

    @Environment(AppState.self) private var appState
    @EnvironmentObject private var glassesManager: GlassesManager

    @State private var coordinator = OnboardingCoordinator()

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                // Progress bar
                OnboardingProgressBar(step: coordinator.step)
                    .padding(.horizontal, 24)
                    .padding(.top, 16)

                // Back button row
                HStack {
                    if coordinator.step > 1 && coordinator.step < 6 {
                        Button {
                            coordinator.back()
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(.primary)
                        }
                    }
                    Spacer()
                }
                .frame(height: 44)
                .padding(.horizontal, 24)

                // Screen content
                Group {
                    switch coordinator.step {
                    case 1: OnboardingScreen1Welcome(coordinator: coordinator)
                    case 2: OnboardingScreen2Who(coordinator: coordinator)
                    case 3: OnboardingScreen3Info(coordinator: coordinator)
                    case 4: OnboardingScreen4Rules(coordinator: coordinator)
                    case 5: OnboardingScreen5Glasses(coordinator: coordinator)
                    default: OnboardingScreen6Ready(coordinator: coordinator, onComplete: onComplete)
                    }
                }
                .environment(coordinator)
            }
        }
        .sheet(isPresented: $coordinator.showProfileCreation) {
            ProfileCreationView(
                onComplete: { profile, _ in
                    Task {
                        try? await appState.createProfile(profile)
                        await appState.setActiveProfile(profile)
                        coordinator.showProfileCreation = false
                        coordinator.step = 4
                    }
                },
                onCancel: {
                    coordinator.showProfileCreation = false
                }
            )
            .environment(appState)
        }
        .alert("Coming Soon", isPresented: $coordinator.showComingSoon) {
            Button("OK") {}
        } message: {
            Text(coordinator.comingSoonMessage)
        }
    }
}

// MARK: - Progress bar

struct OnboardingProgressBar: View {
    let step: Int

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(.systemGray5))
                        .frame(height: 4)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.blue)
                        .frame(width: geo.size.width * CGFloat(step) / 6.0, height: 4)
                        .animation(.spring(response: 0.4), value: step)
                }
            }
            .frame(height: 4)
            Text("\(step) of 6")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Shared card style

struct OnboardingOptionCard<Content: View>: View {
    let isSelected: Bool
    let action: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        Button(action: action) {
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(isSelected ? Color.blue.opacity(0.08) : Color(.secondarySystemBackground))
                        .strokeBorder(isSelected ? Color.blue : Color.clear, lineWidth: 2)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Primary button

struct OnboardingPrimaryButton: View {
    let title: String
    let action: () -> Void
    var disabled: Bool = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(disabled ? Color(.systemGray4) : Color.blue)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .disabled(disabled)
    }
}
