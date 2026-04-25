import SwiftUI

struct OnboardingScreen2Who: View {
    let coordinator: OnboardingCoordinator

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Who is this for?")
                    .font(.title.bold())
                Text("This sets up the right rules and responses")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 8)

            Spacer()

            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(Color.green.opacity(0.15))
                        .frame(width: 48, height: 48)
                    Image(systemName: "figure.run")
                        .foregroundStyle(.green)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Myself — health")
                        .font(.subheadline.weight(.semibold))
                    Text("Food, ergonomics, mindful eating")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.blue)
            }
            .padding(16)
            .background(Color.blue.opacity(0.08))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.blue.opacity(0.4), lineWidth: 1.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 24)

            Spacer()

            OnboardingPrimaryButton(title: "Continue") {
                coordinator.next()
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 48)
        }
        .onAppear { coordinator.path = .health }
    }
}
