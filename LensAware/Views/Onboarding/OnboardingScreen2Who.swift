import SwiftUI

struct OnboardingScreen2Who: View {
    let coordinator: OnboardingCoordinator

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Who is this for?")
                    .font(.title.bold())
                Text("This sets up the right rules and responses")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 8)

            ScrollView {
                VStack(spacing: 12) {
                    // Health card
                    OnboardingOptionCard(isSelected: coordinator.path == .health) {
                        coordinator.path = .health
                    } content: {
                        HStack(spacing: 14) {
                            ZStack {
                                Circle().fill(Color.green.opacity(0.15))
                                    .frame(width: 48, height: 48)
                                Image(systemName: "figure.run")
                                    .foregroundStyle(.green)
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Myself — health")
                                    .font(.subheadline.weight(.semibold))
                                Text("Food, ergonomics, mindful eating")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if coordinator.path == .health {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.blue)
                            }
                        }
                    }

                    // Care card
                    OnboardingOptionCard(isSelected: coordinator.path == .care) {
                        coordinator.showComingSoon = true
                        coordinator.comingSoonMessage = "Care profile coming soon. We'll notify you when it's ready."
                    } content: {
                        HStack(spacing: 14) {
                            ZStack {
                                Circle().fill(Color.pink.opacity(0.15))
                                    .frame(width: 48, height: 48)
                                Image(systemName: "figure.and.child.holdinghands")
                                    .foregroundStyle(.pink)
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 8) {
                                    Text("Someone I care for")
                                        .font(.subheadline.weight(.semibold))
                                    Text("Coming soon")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 8).padding(.vertical, 3)
                                        .background(Color.orange)
                                        .clipShape(Capsule())
                                }
                                Text("Dementia, medication, reminders")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }

                    // Organisation card
                    OnboardingOptionCard(isSelected: coordinator.path == .organisation) {
                        coordinator.path = .organisation
                    } content: {
                        HStack(spacing: 14) {
                            ZStack {
                                Circle().fill(Color.blue.opacity(0.15))
                                    .frame(width: 48, height: 48)
                                Image(systemName: "building.2")
                                    .foregroundStyle(.blue)
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text("My organisation")
                                    .font(.subheadline.weight(.semibold))
                                Text("Custom dataset and rules")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if coordinator.path == .organisation {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }

            Spacer()

            OnboardingPrimaryButton(title: "Continue") {
                if coordinator.path == .organisation {
                    coordinator.showProfileCreation = true
                } else {
                    coordinator.next()
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 48)
        }
    }
}
