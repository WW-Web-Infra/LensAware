import SwiftUI

struct RuleRow: View {
    let rule: Rule

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: actionIcon(rule.actionType))
                .font(.title3)
                .foregroundStyle(.blue)
                .frame(width: 36, height: 36)
                .background(Color.blue.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(rule.trigger.replacingOccurrences(of: "_", with: " ").capitalized)
                    .font(.subheadline.weight(.semibold))
                Text(rule.actionType.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if !rule.isActive {
                Text("Off")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.15))
                    .clipShape(Capsule())
            }
        }
        .padding(.vertical, 4)
    }

    private func actionIcon(_ type: ActionType) -> String {
        switch type {
        case .callVisionAPI: return "eye.fill"
        case .decodeQR:      return "qrcode"
        case .runOCR:        return "text.viewfinder"
        case .lookupLocal:   return "folder.fill"
        case .fetchURL:      return "globe"
        }
    }
}
