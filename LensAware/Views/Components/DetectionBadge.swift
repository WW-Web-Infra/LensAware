import SwiftUI

struct DetectionBadge: View {
    let item: DetectionItem

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(tint.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(timeAgo)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private var icon: String {
        switch item {
        case .meal:      return "fork.knife"
        case .ergonomic: return "figure.seated.seatbelt"
        case .qrScan:    return "qrcode"
        }
    }

    private var tint: Color {
        switch item {
        case .meal:      return .green
        case .ergonomic: return .orange
        case .qrScan:    return .blue
        }
    }

    private var title: String {
        switch item {
        case .meal(let m):
            return "\(m.mealType.capitalized) — \(Int(m.totalCalories)) kcal"
        case .ergonomic(let e):
            return "Posture: \(e.assessment.replacingOccurrences(of: "_", with: " "))"
        case .qrScan(let q):
            return q.url ?? q.rawValue
        }
    }

    private var subtitle: String {
        switch item {
        case .meal(let m):
            return "Mindful score: \(m.mindfulScore)/10"
        case .ergonomic(let e):
            return e.recommendation
        case .qrScan(let q):
            return q.url != nil ? "URL detected" : "Text QR code"
        }
    }

    private var timeAgo: String {
        let diff = Date().timeIntervalSince(item.timestamp)
        if diff < 60    { return "Just now" }
        if diff < 3600  { return "\(Int(diff / 60))m ago" }
        return "\(Int(diff / 3600))h ago"
    }
}
