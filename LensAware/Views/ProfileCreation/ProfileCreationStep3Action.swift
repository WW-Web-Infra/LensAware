import SwiftUI

private struct ActionOption {
    let icon: String
    let label: String
    let description: String
    let type: DatasetType
    var disabledFor: [TriggerType] = []
}

private let actionOptions: [ActionOption] = [
    ActionOption(icon: "speaker.wave.2", label: "Read it aloud",      description: "QR content, text, or descriptions", type: .llmOnly),
    ActionOption(icon: "link",           label: "Look up a URL",       description: "Fetch content from the web",        type: .urlLookup),
    ActionOption(icon: "doc.text",       label: "Search my catalogue", description: "Upload a JSON dataset",             type: .localJSON),
    ActionOption(icon: "cloud",          label: "Call my API",         description: "Connect to your own backend",       type: .cloudAPI,
                 disabledFor: [.qrCode]),
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
                        let disabled = option.disabledFor.contains(coordinator.triggerType)
                        ActionCard(
                            option: option,
                            isSelected: coordinator.datasetType == option.type,
                            isDisabled: disabled,
                            coordinator: coordinator
                        ) {
                            if !disabled { coordinator.datasetType = option.type }
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
    let isDisabled: Bool
    @Bindable var coordinator: ProfileCreationCoordinator
    let action: () -> Void

    @State private var showFilePicker = false

    var body: some View {
        VStack(spacing: 0) {
            OnboardingOptionCard(isSelected: isSelected && !isDisabled, action: action) {
                HStack(spacing: 14) {
                    Image(systemName: option.icon)
                        .font(.title3)
                        .foregroundStyle(isDisabled ? AnyShapeStyle(.tertiary) : (isSelected ? AnyShapeStyle(Color.blue) : AnyShapeStyle(.secondary)))
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(option.label)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(isDisabled ? .tertiary : .primary)
                        Text(isDisabled ? "Not available for this trigger" : option.description)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    if isSelected && !isDisabled {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.blue)
                    }
                }
            }
            .allowsHitTesting(!isDisabled)

            if isSelected && !isDisabled {
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
                            if coordinator.catalogueFilename.isEmpty {
                                Button {
                                    showFilePicker = true
                                } label: {
                                    Label("Upload JSON file", systemImage: "doc.badge.plus")
                                        .font(.subheadline)
                                }
                            } else {
                                HStack {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                    Text(coordinator.catalogueFilename)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Button {
                                        coordinator.catalogueFilename = ""
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(.secondary)
                                    }
                                }
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
                        TextField("Response path (e.g. results[0].name)", text: $coordinator.responseKey)
                            .textFieldStyle(.roundedBorder)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        if coordinator.triggerType == .visionAI {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Image format")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Picker("Image format", selection: $coordinator.imageFormat) {
                                    Text("Base64 JSON").tag("base64_json")
                                    Text("Multipart").tag("multipart")
                                }
                                .pickerStyle(.segmented)
                                TextField("Image field name (default: image)", text: $coordinator.imageField)
                                    .textFieldStyle(.roundedBorder)
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)
                            }
                        }

                    default:
                        EmptyView()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(.systemBackground))
                .clipShape(.rect(bottomLeadingRadius: 14, bottomTrailingRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color.blue, lineWidth: 2)
                        .clipShape(.rect(bottomLeadingRadius: 14, bottomTrailingRadius: 14))
                )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            guard let url = try? result.get().first else { return }
            importCatalogueFile(url)
        }
    }

    private func importCatalogueFile(_ sourceURL: URL) {
        let fm = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let cataloguesDir = docs.appendingPathComponent("catalogues", isDirectory: true)
        try? fm.createDirectory(at: cataloguesDir, withIntermediateDirectories: true)

        let filename = UUID().uuidString
        let dest = cataloguesDir.appendingPathComponent("\(filename).json")

        _ = sourceURL.startAccessingSecurityScopedResource()
        defer { sourceURL.stopAccessingSecurityScopedResource() }

        try? fm.copyItem(at: sourceURL, to: dest)
        coordinator.catalogueFilename = filename
    }
}
