import SwiftUI

struct VerdictCardView: View {
    let evaluation: OfferEvaluation?

    private var verdictColor: Color {
        switch evaluation?.verdict {
        case .take: return .green
        case .maybe: return .orange
        case .pass: return .red
        case nil: return .secondary
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(evaluation?.verdict.badgeText ?? "ENTER OFFER")
                        .font(.caption2.weight(.heavy))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(verdictColor.opacity(0.18))
                        .foregroundStyle(verdictColor)
                        .clipShape(Capsule())

                    Text(evaluation?.verdictTitle ?? "Ready to analyze")
                        .font(.title3.weight(.bold))
                }
                Spacer()
                VStack(spacing: 2) {
                    Text(evaluation.map { "\($0.score)" } ?? "--")
                        .font(.title2.weight(.heavy))
                    Text("SCORE")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                .frame(minWidth: 58, minHeight: 58)
                .padding(.horizontal, 6)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(verdictColor.opacity(0.35), lineWidth: 1)
                )
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                evaluation.map { "\($0.verdict.badgeText): \($0.verdictTitle), score \($0.score) out of 100" }
                    ?? "Enter offer to evaluate"
            )

            Text(evaluation?.reason ?? "Enter payout, miles, and estimated time to calculate true net profit.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                metricTile(
                    label: "Net $/Hr",
                    value: evaluation.map { String(format: "$%.2f", $0.netHourly) } ?? "--",
                    sub: evaluation.map { String(format: "Gross: $%.2f", $0.grossHourly) } ?? "Gross: --"
                )
                metricTile(
                    label: "Eff. $/Mi",
                    value: evaluation.map { String(format: "$%.2f", $0.effectivePerMile) } ?? "--",
                    sub: evaluation.map { String(format: "Shown: $%.2f", $0.grossPerMile) } ?? "Shown: --"
                )
                metricTile(
                    label: "Net Profit",
                    value: evaluation.map { String(format: "$%.2f", $0.netProfit) } ?? "--",
                    sub: evaluation.map { String(format: "Cost: $%.2f", $0.vehicleCost) } ?? "Cost: --"
                )
                metricTile(
                    label: "Tax Write-Off",
                    value: evaluation.map { String(format: "$%.2f", $0.taxDeduction) } ?? "--",
                    sub: evaluation.map { String(format: "Eff. mi: %.1f", $0.effectiveMiles) } ?? "Eff. mi: --"
                )
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(verdictColor.opacity(evaluation == nil ? 0.15 : 0.55), lineWidth: 1.5)
                )
        )
    }

    private func metricTile(label: String, value: String, sub: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(sub)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(.tertiarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value), \(sub)")
    }
}
