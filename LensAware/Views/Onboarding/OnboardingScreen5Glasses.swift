import SwiftUI

struct OnboardingScreen5Glasses: View {
    let coordinator: OnboardingCoordinator

    @EnvironmentObject private var glassesManager: GlassesManager
    @State private var skipped = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Pair your glasses")
                    .font(.title.bold())
                Text("One-time setup · takes 30 seconds")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 8)

            ScrollView {
                VStack(spacing: 16) {
                    // Instructions card
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(instructions.enumerated()), id: \.offset) { idx, text in
                            HStack(alignment: .top, spacing: 12) {
                                Text("\(idx + 1)")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 26, height: 26)
                                    .background(Color.blue)
                                    .clipShape(Circle())
                                Text(text)
                                    .font(.subheadline)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                    // Detected glasses status
                    glassesStatusCard
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }

            VStack(spacing: 12) {
                connectButton

                Button("Continue without glasses") {
                    skipped = true
                    coordinator.next()
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)

                if skipped {
                    Text("You can pair later from Settings")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 48)
        }
    }

    private let instructions = [
        "Open Meta AI app on your phone",
        "Make sure glasses are paired and connected",
        "Come back here and tap Connect"
    ]

    @ViewBuilder
    private var glassesStatusCard: some View {
        if let deviceId = glassesManager.connectedDeviceID {
            HStack(spacing: 10) {
                Circle().fill(Color.green).frame(width: 8, height: 8)
                Text(deviceId)
                    .font(.subheadline)
                Spacer()
                Text("Ready to connect")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
            .padding(14)
            .background(Color.green.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.green.opacity(0.3), lineWidth: 1))
        }
    }

    @ViewBuilder
    private var connectButton: some View {
        switch glassesManager.connectionState {
        case .connected:
            HStack {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("Connected")
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.green.opacity(0.15))
            .foregroundStyle(.green)
            .clipShape(RoundedRectangle(cornerRadius: 14))

            OnboardingPrimaryButton(title: "Continue") {
                coordinator.next()
            }

        case .searching:
            HStack {
                ProgressView().tint(.white)
                Text("Connecting…")
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.blue)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))

        case .error:
            VStack(spacing: 8) {
                HStack {
                    Image(systemName: "xmark.circle").foregroundStyle(.red)
                    Text("Connection failed")
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.red.opacity(0.1))
                .foregroundStyle(.red)
                .clipShape(RoundedRectangle(cornerRadius: 14))

                OnboardingPrimaryButton(title: "Try again") {
                    glassesManager.reconnect()
                }
            }

        default:
            OnboardingPrimaryButton(title: "Connect glasses") {
                glassesManager.startConnection()
            }
        }
    }
}
