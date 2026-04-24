import SwiftUI

struct OnboardingScreen4Rules: View {
    let coordinator: OnboardingCoordinator

    @Environment(AppState.self) private var appState

    private var profile: LensProfile? {
        appState.allProfiles.first(where: { $0.name == "Health" })
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Turn on your rules")
                    .font(.title.bold())
                Text("You can change these any time")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 8)

            ScrollView {
                VStack(spacing: 12) {
                    if let rules = profile?.rules, !rules.isEmpty {
                        ForEach(rules) { rule in
                            RuleToggleRow(
                                rule: rule,
                                isOn: Binding(
                                    get: { coordinator.ruleToggles[rule.id] ?? rule.isActive },
                                    set: { coordinator.ruleToggles[rule.id] = $0 }
                                )
                            )
                        }
                    } else {
                        Text("No rules found. They will load after setup.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }
            .onAppear {
                // Initialise toggles from current rule state
                if let rules = profile?.rules {
                    for rule in rules where coordinator.ruleToggles[rule.id] == nil {
                        coordinator.ruleToggles[rule.id] = rule.isActive
                    }
                }
            }

            OnboardingPrimaryButton(title: "Continue") {
                // Persist toggled states
                if let rules = profile?.rules {
                    for rule in rules {
                        if let toggled = coordinator.ruleToggles[rule.id] {
                            var updated = rule
                            updated.isActive = toggled
                            Task { await appState.saveRuleToggle(updated) }
                        }
                    }
                }
                coordinator.next()
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 48)
        }
    }
}

// MARK: - Rule toggle row

private struct RuleToggleRow: View {
    let rule: Rule
    @Binding var isOn: Bool

    var body: some View {
        let info = ruleDisplayInfo(for: rule)
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(info.color.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: info.icon)
                    .foregroundStyle(info.color)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(info.name)
                    .font(.subheadline.weight(.semibold))
                Text(info.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
        }
        .padding(14)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func ruleDisplayInfo(for rule: Rule) -> (icon: String, color: Color, name: String, description: String) {
        switch rule.trigger {
        case "food_detected":
            return ("fork.knife", .green, "Food & Nutrition", "See food → hear nutrition")
        case "screen_detected":
            return ("display", .orange, "Screen Ergonomics", "Monitor posture alerts")
        case "meal_context":
            return ("leaf", .purple, "Mindful Eating", "Dining context analysis")
        default:
            return ("sparkles", .blue, rule.trigger.replacingOccurrences(of: "_", with: " ").capitalized, "Custom rule")
        }
    }
}
