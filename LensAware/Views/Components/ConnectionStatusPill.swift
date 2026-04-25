import SwiftUI

struct ConnectionStatusPill: View {
    let isConnected: Bool
    let isSearching: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                if isSearching {
                    ProgressView()
                        .scaleEffect(0.6)
                        .tint(.orange)
                        .frame(width: 8, height: 8)
                } else {
                    Circle()
                        .fill(isConnected ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                }
                Text(isConnected ? "Glasses Connected" : isSearching ? "Connecting…" : "Not Connected")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
