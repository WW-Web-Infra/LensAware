import SwiftUI

struct RulesView: View {
    @Environment(AppState.self) private var appState
    @State private var showProfileCreation = false
    @State private var deleteError: String?
    @State private var showDeleteError = false

    var body: some View {
        NavigationStack {
            Group {
                if appState.allProfiles.isEmpty {
                    ContentUnavailableView(
                        "No Profiles",
                        systemImage: "list.bullet.clipboard",
                        description: Text("Profiles will load after setup.")
                    )
                } else {
                    List {
                        ForEach(appState.allProfiles) { profile in
                            Section(header: profileHeader(profile)) {
                                if profile.rules.isEmpty {
                                    Text("No rules")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else {
                                    ForEach(profile.rules) { rule in
                                        RuleRow(rule: rule)
                                    }
                                }
                            }
                        }
                        .onDelete(perform: deleteProfiles)
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Rules")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showProfileCreation = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .task {
                await appState.loadProfiles()
            }
            .sheet(isPresented: $showProfileCreation) {
                ProfileCreationView(
                    onComplete: { profile, _ in
                        showProfileCreation = false
                        Task {
                            await appState.loadProfiles()
                            // Show success toast
                        }
                    },
                    onCancel: { showProfileCreation = false }
                )
                .environment(appState)
            }
            .alert("Cannot Delete", isPresented: $showDeleteError) {
                Button("OK") {}
            } message: {
                Text(deleteError ?? "This profile cannot be deleted.")
            }
        }
    }

    private func profileHeader(_ profile: LensProfile) -> some View {
        HStack {
            Text(profile.name)
            Spacer()
            if profile.isActive {
                Text("Active")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.blue)
                    .clipShape(Capsule())
            }
            if profile.isSystem {
                Text("System")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func deleteProfiles(at offsets: IndexSet) {
        for index in offsets {
            let profile = appState.allProfiles[index]
            Task {
                do {
                    try await appState.deleteProfile(profile)
                } catch DatabaseError.systemProfileCannotBeDeleted {
                    deleteError = "'\(profile.name)' is a built-in profile and cannot be deleted."
                    showDeleteError = true
                } catch {
                    deleteError = error.localizedDescription
                    showDeleteError = true
                }
            }
        }
    }
}
