import SwiftUI

private let suggestions = ["QR Scanner", "Museum Artifacts", "Product Lookup", "Floral Detection"]

struct ProfileCreationStep1Name: View {
    @Bindable var coordinator: ProfileCreationCoordinator

    @FocusState private var nameFocused: Bool

    var canContinue: Bool {
        !coordinator.profileName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Name your profile")
                    .font(.title2.bold())
                Text("Give it a clear, descriptive name")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 16)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Profile name", text: $coordinator.profileName)
                            .textFieldStyle(.roundedBorder)
                            .focused($nameFocused)

                        TextField("Description (optional)", text: $coordinator.profileDescription)
                            .textFieldStyle(.roundedBorder)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Suggestions")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        FlowLayoutPCR(spacing: 8) {
                            ForEach(suggestions, id: \.self) { s in
                                Button(s) {
                                    coordinator.profileName = s
                                }
                                .font(.subheadline)
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .background(Color(.secondarySystemBackground))
                                .clipShape(Capsule())
                                .overlay(Capsule().strokeBorder(Color(.systemGray4), lineWidth: 1))
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }

            OnboardingPrimaryButton(title: "Continue", action: {
                nameFocused = false
                coordinator.step = 2
            }, disabled: !canContinue)
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
    }
}

struct FlowLayoutPCR: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0; var y: CGFloat = 0; var rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > maxWidth && x > 0 { y += rowH + spacing; x = 0; rowH = 0 }
            x += s.width + spacing; rowH = max(rowH, s.height)
        }
        return CGSize(width: maxWidth, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX; var y = bounds.minY; var rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX && x > bounds.minX { y += rowH + spacing; x = bounds.minX; rowH = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing; rowH = max(rowH, s.height)
        }
    }
}
