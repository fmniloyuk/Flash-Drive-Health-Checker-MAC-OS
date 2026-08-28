import FlashScopeCore
import SwiftUI

struct HealthStatusBadge: View {
    let classification: HealthClassification

    var body: some View {
        Label(classification.rawValue, systemImage: icon)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(color.opacity(0.12), in: Capsule())
            .foregroundStyle(color)
            .accessibilityLabel("Health status: \(classification.rawValue)")
    }

    private var icon: String {
        switch classification {
        case .healthy: "checkmark.seal.fill"
        case .limitedByConnection: "arrow.triangle.2.circlepath.circle.fill"
        case .attentionRecommended: "exclamationmark.triangle.fill"
        case .critical: "exclamationmark.octagon.fill"
        case .inconclusive: "questionmark.diamond.fill"
        }
    }

    private var color: Color {
        switch classification {
        case .healthy: .green
        case .limitedByConnection: .teal
        case .attentionRecommended: .orange
        case .critical: .red
        case .inconclusive: .secondary
        }
    }
}

struct SeverityLabel: View {
    let severity: FindingSeverity

    var body: some View {
        Label(name, systemImage: icon)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .accessibilityLabel("Severity: \(name)")
    }

    private var name: String {
        switch severity { case .info: "Info"; case .low: "Low"; case .medium: "Medium"; case .high: "High"; case .critical: "Critical" }
    }
    private var icon: String {
        switch severity { case .info: "info.circle"; case .low: "circle"; case .medium: "exclamationmark.triangle"; case .high: "exclamationmark.triangle.fill"; case .critical: "exclamationmark.octagon.fill" }
    }
    private var color: Color {
        switch severity { case .info: .secondary; case .low: .teal; case .medium: .orange; case .high, .critical: .red }
    }
}
