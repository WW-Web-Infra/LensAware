import SwiftUI

// MARK: - Coordinator

@Observable
@MainActor
final class ProfileCreationCoordinator {
    var step: Int = 1
    var profileName: String = ""
    var profileDescription: String = ""
    var triggerType: TriggerType = .visionAI
    var datasetType: DatasetType = .llmOnly
    var baseURL: String = ""
    var apiEndpoint: String = ""
    var authHeader: String = ""
    var imageFormat: String = "base64_json"
    var imageField: String = ""
    var responseKey: String = ""
    var catalogueFilename: String = ""
    var tone: ToneType = .coach

    var isCreating: Bool = false
    var showDuplicateError: Bool = false

    func defaultTone(for trigger: TriggerType) -> ToneType {
        trigger == .qrCode ? .alert : .coach
    }

    func defaultDatasetType(for trigger: TriggerType) -> DatasetType {
        .llmOnly
    }

    func defaultActionType(for trigger: TriggerType) -> ActionType {
        switch trigger {
        case .qrCode:         return .decodeQR
        case .textOCR:        return .runOCR
        default:              return .callVisionAPI
        }
    }

    func buildDatasetConfigJSON() -> String? {
        switch datasetType {
        case .urlLookup where !baseURL.isEmpty:
            let d = ["base_url": baseURL]
            return (try? JSONEncoder().encode(d)).flatMap { String(data: $0, encoding: .utf8) }
        case .cloudAPI where !apiEndpoint.isEmpty:
            var d: [String: String] = ["endpoint": apiEndpoint]
            if !authHeader.isEmpty  { d["auth_header"]   = authHeader }
            if !responseKey.isEmpty { d["response_key"]  = responseKey }
            if imageFormat != "base64_json" { d["image_format"] = imageFormat }
            let field = imageField.trimmingCharacters(in: .whitespaces)
            if !field.isEmpty && field != "image" { d["image_field"] = field }
            return (try? JSONEncoder().encode(d)).flatMap { String(data: $0, encoding: .utf8) }
        case .localJSON where !catalogueFilename.isEmpty:
            let d = ["filename": catalogueFilename]
            return (try? JSONEncoder().encode(d)).flatMap { String(data: $0, encoding: .utf8) }
        default:
            return nil
        }
    }
}

// MARK: - ProfileCreationView

struct ProfileCreationView: View {
    let onComplete: (LensProfile, Rule) -> Void
    let onCancel: () -> Void

    @Environment(AppState.self) private var appState
    @State private var coordinator = ProfileCreationCoordinator()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Step progress
                HStack(spacing: 4) {
                    ForEach(1...4, id: \.self) { i in
                        Capsule()
                            .fill(i <= coordinator.step ? Color.blue : Color(.systemGray5))
                            .frame(height: 4)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)

                Group {
                    switch coordinator.step {
                    case 1: ProfileCreationStep1Name(coordinator: coordinator)
                    case 2: ProfileCreationStep2Trigger(coordinator: coordinator)
                    case 3: ProfileCreationStep3Action(coordinator: coordinator)
                    default: ProfileCreationStep4Tone(coordinator: coordinator)
                    }
                }
                .environment(coordinator)
            }
            .navigationTitle("New Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel", action: onCancel)
                }
                if coordinator.step > 1 {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            coordinator.step -= 1
                        } label: {
                            Image(systemName: "chevron.left")
                        }
                    }
                }
            }
        }
        .alert("Duplicate Name", isPresented: $coordinator.showDuplicateError) {
            Button("OK") {}
        } message: {
            Text("A profile with this name already exists. Please choose a different name.")
        }
        .environment(coordinator)
        // Pass create action down via environment — screens call this directly
        .onReceive(NotificationCenter.default.publisher(for: .profileCreationConfirmed)) { _ in
            Task { await submitProfile() }
        }
    }

    private func submitProfile() async {
        coordinator.isCreating = true
        let tenantId = appState.activeProfile?.tenantId ?? "default_tenant"
        let profileId = UUID()
        let configJSON = coordinator.buildDatasetConfigJSON()

        let profile = LensProfile(
            id: profileId,
            tenantId: tenantId,
            name: coordinator.profileName.trimmingCharacters(in: .whitespaces),
            description: coordinator.profileDescription.trimmingCharacters(in: .whitespaces),
            triggerType: coordinator.triggerType,
            datasetType: coordinator.datasetType,
            datasetConfigJSON: configJSON,
            tone: coordinator.tone,
            isActive: false,
            isSystem: false,
            createdAt: Date(),
            rules: []
        )
        let rule = Rule(
            id: UUID(),
            profileId: profileId,
            tenantId: tenantId,
            trigger: coordinator.triggerType.rawValue,
            actionType: coordinator.defaultActionType(for: coordinator.triggerType),
            actionConfigJSON: configJSON,
            responseTemplate: nil,
            priority: 0,
            isActive: true
        )
        do {
            try await appState.createProfile(LensProfile(
                id: profile.id, tenantId: profile.tenantId, name: profile.name,
                description: profile.description, triggerType: profile.triggerType,
                datasetType: profile.datasetType, datasetConfigJSON: profile.datasetConfigJSON,
                tone: profile.tone, isActive: profile.isActive, isSystem: profile.isSystem,
                createdAt: profile.createdAt, rules: [rule]
            ))
            onComplete(profile, rule)
        } catch ProfileCreationError.duplicateName {
            coordinator.showDuplicateError = true
            coordinator.step = 1
        } catch {
            // ignore other errors
        }
        coordinator.isCreating = false
    }
}

extension Notification.Name {
    static let profileCreationConfirmed = Notification.Name("profileCreationConfirmed")
}
