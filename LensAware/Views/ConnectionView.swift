import SwiftUI

struct ConnectionView: View {
    @EnvironmentObject private var glassesManager: GlassesManager
    let onConnected: () -> Void

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: "eyeglasses")
                .font(.system(size: 80))
                .foregroundStyle(.blue)

            VStack(spacing: 8) {
                Text("LensAware")
                    .font(.largeTitle.bold())
                Text("Connect your Meta Ray-Ban glasses\nto start health monitoring.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            statusView

            connectButton

            Spacer()
        }
        .padding(32)
        .onChange(of: glassesManager.connectionState) { _, state in
            if case .connected = state {
                onConnected()
            }
        }
    }

    @ViewBuilder
    private var statusView: some View {
        switch glassesManager.connectionState {
        case .disconnected:
            EmptyView()
        case .searching:
            HStack(spacing: 8) {
                ProgressView()
                Text("Opening Meta AI app…")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        case .connected:
            Label("Glasses connected", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .error(let message):
            Text(message)
                .font(.footnote)
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
        }
    }

    private var connectButton: some View {
        Button {
            glassesManager.startConnection()
        } label: {
            Label("Connect Glasses", systemImage: "link")
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .disabled({
            if case .searching = glassesManager.connectionState { return true }
            if case .connected = glassesManager.connectionState { return true }
            return false
        }())
    }
}
