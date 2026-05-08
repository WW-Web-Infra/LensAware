import SwiftUI

private struct ToneOption {
    let type: ToneType
    let label: String
    let example: String
}

private let toneOptions: [ToneOption] = [
    ToneOption(type: .coach, label: "Coach", example: "Chicken salad. 420 calories. 35g protein. Good choice."),
    ToneOption(type: .alert, label: "Alert", example: "420 calories."),
]

struct ProfileCreationStep4Tone: View {
    let coordinator: ProfileCreationCoordinator

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("How should it sound?")
                    .font(.title2.bold())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 16)

            ScrollView {
                VStack(spacing: 12) {
                    ForEach(toneOptions, id: \.type) { option in
                        OnboardingOptionCard(isSelected: coordinator.tone == option.type) {
                            coordinator.tone = option.type
                        } content: {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(option.label)
                                        .font(.subheadline.weight(.semibold))
                                    Spacer()
                                    if coordinator.tone == option.type {
                                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.blue)
                                    }
                                }
                                Text("\"\(option.example)\"")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .italic()
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }

            OnboardingPrimaryButton(
                title: coordinator.isCreating ? "Creating…" : "Create profile",
                action: {
                    NotificationCenter.default.post(name: .profileCreationConfirmed, object: nil)
                },
                disabled: coordinator.isCreating
            )
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
    }
}
