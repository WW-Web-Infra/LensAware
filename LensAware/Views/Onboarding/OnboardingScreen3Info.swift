import SwiftUI

private let allGoals = [
    "Track nutrition",
    "Ergonomics",
    "Mindful eating",
    "Weight management",
    "Energy levels"
]

struct OnboardingScreen3Info: View {
    @Bindable var coordinator: OnboardingCoordinator

    @Environment(AppState.self) private var appState
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("A bit about you")
                    .font(.title.bold())
                Text("Helps personalise your responses")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Name
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Your name")
                            .font(.subheadline.weight(.semibold))
                        TextField("Your name", text: $coordinator.userName)
                            .textFieldStyle(.roundedBorder)
                            .focused($nameFocused)
                    }

                    // Health goals
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Health goals")
                            .font(.subheadline.weight(.semibold))
                        FlowLayout(spacing: 8) {
                            ForEach(allGoals, id: \.self) { goal in
                                GoalPill(
                                    title: goal,
                                    isSelected: coordinator.healthGoals.contains(goal)
                                ) {
                                    if coordinator.healthGoals.contains(goal) {
                                        coordinator.healthGoals.remove(goal)
                                    } else {
                                        coordinator.healthGoals.insert(goal)
                                    }
                                }
                            }
                        }
                    }

                    // Calorie target
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Daily calorie target")
                            .font(.subheadline.weight(.semibold))
                        HStack {
                            Text("\(coordinator.calorieTarget) kcal")
                                .font(.title3.monospacedDigit())
                                .frame(minWidth: 100, alignment: .leading)
                            Spacer()
                            Stepper("", value: $coordinator.calorieTarget, in: 1200...4000, step: 100)
                                .labelsHidden()
                        }
                        .padding(12)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }

            OnboardingPrimaryButton(
                title: "Continue",
                action: {
                    nameFocused = false
                    appState.userName = coordinator.userName.trimmingCharacters(in: .whitespaces)
                    Task {
                        await appState.saveHealthSettings(
                            calorieTarget: coordinator.calorieTarget,
                            goals: coordinator.healthGoals
                        )
                    }
                    coordinator.next()
                },
                disabled: coordinator.userName.trimmingCharacters(in: .whitespaces).isEmpty
            )
            .padding(.horizontal, 24)
            .padding(.bottom, 48)
        }
    }
}

// MARK: - Goal pill

private struct GoalPill: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(isSelected ? Color.blue : Color(.secondarySystemBackground))
                .foregroundStyle(isSelected ? .white : .primary)
                .clipShape(Capsule())
                .overlay(
                    Capsule().strokeBorder(isSelected ? Color.clear : Color(.systemGray4), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Simple flow layout

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxWidth = bounds.width
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
