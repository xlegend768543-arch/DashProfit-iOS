import ActivityKit
import SwiftUI
import WidgetKit

struct DashShiftLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DashShiftActivityAttributes.self) { context in
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("DashProfit Live Shift", systemImage: "car.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.green)
                    Spacer()
                    Text(formatElapsed(context.state.elapsedSeconds))
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 12) {
                    metricBlock(
                        title: "Miles Today",
                        value: String(format: "%.1f mi", context.state.milesToday),
                        tint: .primary
                    )
                    metricBlock(
                        title: "Tax Write-Off",
                        value: String(format: "$%.2f", context.state.taxWriteOff),
                        tint: .green
                    )
                    metricBlock(
                        title: "Net Profit",
                        value: formatCurrency(context.state.netProfit),
                        tint: context.state.netProfit >= 0 ? .green : .red
                    )
                }
            }
            .padding(14)
            .activityBackgroundTint(Color.black.opacity(0.85))
            .activitySystemActionForegroundColor(.green)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Miles")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(String(format: "%.1f mi", context.state.milesToday))
                            .font(.headline.weight(.bold))
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Net Profit")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(formatCurrency(context.state.netProfit))
                            .font(.headline.weight(.bold))
                            .foregroundStyle(context.state.netProfit >= 0 ? .green : .red)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text(String(format: "Write-Off: $%.2f (@ $%.2f/mi)", context.state.taxWriteOff, context.attributes.irsRate))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.green)
                        Spacer()
                        Text(formatElapsed(context.state.elapsedSeconds))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            } compactLeading: {
                HStack(spacing: 4) {
                    Image(systemName: "car.fill")
                        .foregroundStyle(.green)
                    Text(String(format: "%.1fm", context.state.milesToday))
                        .font(.caption2.weight(.bold))
                }
            } compactTrailing: {
                Text(String(format: "$%.0f", context.state.netProfit))
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(context.state.netProfit >= 0 ? .green : .red)
            } minimal: {
                Image(systemName: "car.fill")
                    .foregroundStyle(.green)
            }
            .keylineTint(.green)
        }
    }

    private func metricBlock(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func formatElapsed(_ seconds: Int) -> String {
        let hrs = seconds / 3600
        let mins = (seconds % 3600) / 60
        return String(format: "%d:%02d", hrs, mins)
    }

    private func formatCurrency(_ value: Double) -> String {
        String(format: "%@$%.2f", value < 0 ? "-" : "", abs(value))
    }
}
