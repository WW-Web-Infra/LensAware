import SwiftUI

private struct ActionOption {
    let icon: String
    let label: String
    let description: String
    let type: DatasetType
}

private let actionOptions: [ActionOption] = [
    ActionOption(icon: "speaker.wave.2", label: "Read it aloud",       description: "QR content, text, or descriptions", type: .llmOnly),
    ActionOption(icon: "link",           label: "Look up a URL",        description: "Fetch content from the web",        type: .urlLookup),
    ActionOption(icon: "doc.text",       label: "Search my catalogue",  description: "Upload a JSON dataset",             type: .localJSON),
    ActionOption(icon: "cloud",          label: "Call my API",          description: "Connect to your own backend",       type: .cloudAPI),
]

struct ProfileCreationStep3Action: View {
    let coordinator: ProfileCreationCoordinator

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("What do you want to know?")
                    .font(.title2.bold())
                Text("When detected, what should happen?")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 16)

            ScrollView {
                VStack(spacing: 12) {
                    ForEach(actionOptions, id: \.type) { option in
                        ActionCard(
                            option: option,
                            isSelected: coordinator.datasetType == option.type,
                            coordinator: coordinator
                        ) {
                            coordinator.datasetType = option.type
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }

            OnboardingPrimaryButton(title: "Continue") {
                coordinator.step = 4
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
    }
}

private struct ActionCard: View {
    let option: ActionOption
    let isSelected: Bool
    @Bindable var coordinator: ProfileCreationCoordinator
    let action: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            OnboardingOptionCard(isSelected: isSelected, action: action) {
                HStack(spacing: 14) {
                    Image(systemName: option.icon)
                        .font(.title3)
                        .foregroundStyle(isSelected ? .blue : .secondary)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(option.label)
                            .font(.subheadline.weight(.semibold))
                        Text(option.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.blue)
                    }
                }
            }

            // Expanded config when selected
            if isSelected {
                VStack(alignment: .leading, spacing: 12) {
                    switch option.type {
                    case .urlLookup:
                        TextField("Base URL (optional)", text: $coordinator.baseURL)
                            .textFieldStyle(.roundedBorder)
                            .keyboardType(.URL)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)

                    case .localJSON:
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Accepted format:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(#"[{"id":"001","name":"...","description":"..."}]"#)
                                .font(.caption.monospaced())
                                .padding(8)
                                .background(Color(.systemGray6))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            Button {
                                // File picker stub — coming soon
                            } label: {
                                Label("Upload JSON file", systemImage: "doc.badge.plus")
                                    .font(.subheadline)
                            }
                        }

                    case .cloudAPI:
                        TextField("API endpoint", text: $coordinator.apiEndpoint)
                            .textFieldStyle(.roundedBorder)
                            .keyboardType(.URL)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        TextField("Auth header (optional)", text: $coordinator.authHeader)
                            .textFieldStyle(.roundedBorder)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)

                    default:
                        EmptyView()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(.systemBackground))
                .clipShape(
                    .rect(bottomLeadingRadius: 14, bottomTrailingRadius: 14)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color.blue, lineWidth: 2)
                        .clipShape(.rect(bottomLeadingRadius: 14, bottomTrailingRadius: 14))
                )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}
