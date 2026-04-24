import SwiftUI

struct OnboardingScreen1Welcome: View {
    let coordinator: OnboardingCoordinator

    @State private var showComingSoon = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Image(systemName: "eyeglasses")
                .font(.system(size: 72))
                .foregroundStyle(.blue)
                .padding(.bottom, 32)

            Text("Welcome to LensAware")
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)

            Text("Your glasses now see, understand,\nand respond. Set up in 2 minutes.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 12)
                .padding(.horizontal, 32)

            Spacer()

            VStack(spacing: 12) {
                OnboardingPrimaryButton(title: "Get started") {
                    coordinator.next()
                }

                Button("I already have an account") {
                    showComingSoon = true
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 48)
        }
        .alert("Coming Soon", isPresented: $showComingSoon) {
            Button("OK") {}
        } message: {
            Text("Account sign-in will be available in a future update.")
        }
    }
}
