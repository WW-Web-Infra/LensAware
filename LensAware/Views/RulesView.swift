import SwiftUI

struct RulesView: View {
    @Environment(AppState.self) private var appState
    @State private var showAddAlert = false

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
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Rules")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAddAlert = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .alert("Coming Soon", isPresented: $showAddAlert) {
                Button("OK") {}
            } message: {
                Text("Custom rule creation will be available in a future update.")
            }
            .task {
                await appState.loadProfiles()
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
}
