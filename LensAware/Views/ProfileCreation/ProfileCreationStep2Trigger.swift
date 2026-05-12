import SwiftUI

private struct TriggerOption {
    let icon: String
    let label: String
    let description: String
    let type: TriggerType
    var comingSoon: Bool = false
}

private let triggerOptions: [TriggerOption] = [
    TriggerOption(icon: "eye",             label: "Full scene",    description: "AI understands what you see",  type: .visionAI),
    TriggerOption(icon: "qrcode",          label: "QR codes",      description: "Instant, works offline",       type: .qrCode),
    TriggerOption(icon: "text.viewfinder", label: "Text and signs",description: "Read and translate text",      type: .textOCR),
    TriggerOption(icon: "figure.stand",    label: "Objects",       description: "Identify specific items",      type: .objectDetection),
]

struct ProfileCreationStep2Trigger: View {
    let coordinator: ProfileCreationCoordinator

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("What should the glasses look for?")
                    .font(.title2.bold())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 16)

            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(triggerOptions, id: \.type) { option in
                        TriggerCard(
                            option: option,
                            isSelected: coordinator.triggerType == option.type
                        ) {
                            coordinator.triggerType = option.type
                            coordinator.datasetType = coordinator.defaultDatasetType(for: option.type)
                            coordinator.tone        = coordinator.defaultTone(for: option.type)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }

            OnboardingPrimaryButton(title: "Continue") {
                coordinator.step = 3
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
    }
}

private struct TriggerCard: View {
    let option: TriggerOption
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: option.icon)
                        .font(.title2)
                        .foregroundStyle(isSelected ? .blue : .primary)
                    Spacer()
                    if option.comingSoon {
                        Text("Soon")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.orange)
                            .clipShape(Capsule())
                    }
                }
                Text(option.label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(option.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.blue.opacity(0.08) : Color(.secondarySystemBackground))
                    .strokeBorder(isSelected ? Color.blue : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}
