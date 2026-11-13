import SwiftUI
import UIKit

struct MileageBarView: View {
    @Bindable var store: DashStore
    @Bindable var mileageTracker: MileageTrackerService
    let onUseTrip: (Double) -> Void
    let onStatusMessage: (String) -> Void

    @State private var showManualMileageDrawer = false
    @State private var showResetConfirmation = false
    @State private var customMilesText = ""
    @State private var startOdoText = ""
    @State private var endOdoText = ""

    var body: some View {
        let liveGPS = mileageTracker.isTracking ? mileageTracker.shiftMiles : 0.0
        let liveShiftSeconds = mileageTracker.isShiftTiming ? mileageTracker.liveShiftElapsedSeconds : 0
        let daily = store.todaySummary(liveGPSMiles: liveGPS, liveShiftSeconds: liveShiftSeconds)

        VStack(alignment: .leading, spacing: 10) {
            headerRow(daily: daily)
            kpiRow(daily: daily)

            if daily.dailyGoal > 0 {
                goalProgressBar(daily: daily)
            }

            quickAddRow(daily: daily)

            if showManualMileageDrawer {
                drawerSection(daily: daily)
            }

            if let gpsError = mileageTracker.errorMessage {
                Text(gpsError)
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onChange(of: daily.totalMiles) { _, _ in
            if mileageTracker.isTracking || mileageTracker.isShiftTiming {
                mileageTracker.updateLiveActivity(summary: daily)
            }
        }
        .onChange(of: mileageTracker.isShiftTiming) { _, _ in
            mileageTracker.updateLiveActivity(summary: daily)
        }
        .onChange(of: mileageTracker.isTracking) { _, _ in
            mileageTracker.updateLiveActivity(summary: daily)
        }
        .confirmationDialog(
            "Reset Today's Mileage?",
            isPresented: $showResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset Manual & GPS Miles", role: .destructive) {
                store.resetTodayManualAndGPS()
                startOdoText = ""
                endOdoText = ""
                onStatusMessage("Reset today's manual & GPS mileage")
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This clears today's manual entries, odometer readings, and saved GPS miles. Logged orders stay intact.")
        }
    }

    private func headerRow(daily: DailySummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: mileageTracker.isTracking ? "location.fill" : (mileageTracker.isShiftTiming ? "timer" : "gauge.with.dots.needle.33percent"))
                    .foregroundStyle((mileageTracker.isTracking || mileageTracker.isShiftTiming) ? .green : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(headerTitle)
                        .font(.caption.weight(.bold))
                    Text(String(format: "Trips %.1f • GPS %.1f • Manual %.1f mi",
                                daily.tripMiles,
                                daily.gpsMiles,
                                daily.manualMiles))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            HStack(spacing: 6) {
                if mileageTracker.isTracking && mileageTracker.tripMiles >= 0.1 {
                    Button("Use Trip") {
                        let miles = mileageTracker.tripMiles
                        onUseTrip(miles)
                        mileageTracker.resetTripMiles()
                    }
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(Color.green.opacity(0.18))
                    .foregroundStyle(.green)
                    .clipShape(Capsule())
                    .accessibilityLabel("Use live GPS trip distance")
                }

                Button {
                    mileageTracker.toggleShiftTimer { elapsedSeconds in
                        store.addShiftSeconds(elapsedSeconds)
                        onStatusMessage("Saved shift time (\(elapsedSeconds / 60)m)")
                    }
                } label: {
                    let formatted = mileageTracker.formattedShiftTimer(savedSeconds: store.todayEntry.shiftSeconds)
                    Label(
                        mileageTracker.isShiftTiming ? "Stop Shift \(formatted)" : (store.todayEntry.shiftSeconds > 0 ? "Shift \(formatted)" : "Start Shift"),
                        systemImage: mileageTracker.isShiftTiming ? "pause.circle.fill" : "timer"
                    )
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(mileageTracker.isShiftTiming ? Color.orange.opacity(0.2) : Color(.tertiarySystemGroupedBackground))
                    .foregroundStyle(mileageTracker.isShiftTiming ? .orange : .primary)
                    .clipShape(Capsule())
                }
                .accessibilityLabel(mileageTracker.isShiftTiming ? "Stop shift timer" : "Start shift timer")

                Spacer()

                Button(mileageTracker.isTracking ? "Stop GPS" : "Start GPS") {
                    mileageTracker.toggleShift { shift in
                        store.addShift(shift)
                        let writeOff = shift.miles * daily.irsRate
                        onStatusMessage(String(format: "Saved GPS shift: %.2f mi ($%.2f write-off)", shift.miles, writeOff))
                    }
                }
                .font(.caption.weight(.bold))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(mileageTracker.isTracking ? Color.red.opacity(0.2) : Color.green)
                .foregroundStyle(mileageTracker.isTracking ? .red : .black)
                .clipShape(Capsule())
                .accessibilityLabel(mileageTracker.isTracking ? "Stop GPS mileage tracking" : "Start GPS mileage tracking")
            }
        }
    }

    private var headerTitle: String {
        if mileageTracker.isTracking {
            return "Live GPS Active • \(mileageTracker.formattedElapsed)"
        } else if mileageTracker.isShiftTiming {
            let formatted = mileageTracker.formattedShiftTimer(savedSeconds: store.todayEntry.shiftSeconds)
            return "Shift Timer Running • \(formatted)"
        }
        return "Today's Mileage & Profit"
    }

    private func kpiRow(daily: DailySummary) -> some View {
        let milesSourceLabel = daily.milesSource == "gps" ? "Using GPS miles" : "Using trip est."
        return HStack(spacing: 8) {
            dailyKpiBox(
                label: "Miles Today",
                value: String(format: "%.1f mi", daily.totalMiles),
                sub: milesSourceLabel,
                tint: .primary
            )
            dailyKpiBox(
                label: "Tax Write-Off",
                value: String(format: "$%.2f", daily.totalDeductions),
                sub: daily.taxSetAside > 0 ? String(format: "Set aside ~$%.0f", daily.taxSetAside) : String(format: "IRS $%.2f", daily.taxDeduction),
                tint: .green
            )
            dailyKpiBox(
                label: "Net Profit",
                value: String(format: "%@$%.2f", daily.netProfit < 0 ? "-" : "", abs(daily.netProfit)),
                sub: daily.hoursWorked > 0 ? String(format: "$%.2f/hr net", daily.netPerHour) : "Cash after costs",
                tint: daily.netProfit < 0 ? .red : (daily.netProfit > 0 ? .green : .primary)
            )
        }
    }

    private func goalProgressBar(daily: DailySummary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(String(format: "Daily Net Goal: $%.0f / $%.0f", max(0, daily.netProfit), daily.dailyGoal))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(daily.goalRemaining > 0 ? String(format: "$%.0f to go", daily.goalRemaining) : "Goal Reached!")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(daily.goalRemaining > 0 ? Color.secondary : Color.green)
            }
            ProgressView(value: min(max(daily.goalProgress, 0), 1))
                .tint(daily.goalProgress >= 1 ? .green : .orange)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Daily net goal progress")
        .accessibilityValue(String(format: "%.0f of %.0f dollars", max(0, daily.netProfit), daily.dailyGoal))
    }

    private func quickAddRow(daily: DailySummary) -> some View {
        HStack(spacing: 6) {
            Text("Add mi:")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach([0.5, 1.0, 5.0], id: \.self) { amt in
                Button(amt == 0.5 ? "+0.5" : String(format: "+%.0f", amt)) {
                    store.addManualMiles(amt, kind: .quick)
                }
                .font(.caption2.weight(.bold))
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Color(.tertiarySystemGroupedBackground))
                .foregroundStyle(.primary)
                .clipShape(Capsule())
            }

            if !store.todayEntry.entries.isEmpty {
                Button("Undo") {
                    if let removed = store.undoLastManualMile() {
                        onStatusMessage(String(format: "Removed %.1f manual mi", removed.miles))
                    }
                }
                .font(.caption2.weight(.bold))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.orange.opacity(0.16))
                .foregroundStyle(.orange)
                .clipShape(Capsule())
            }

            Spacer()

            Button(showManualMileageDrawer ? "Hide" : "Odo / Log") {
                if !showManualMileageDrawer {
                    let entry = store.todayEntry
                    if let s = entry.startOdometer { startOdoText = String(format: "%.1f", s) }
                    if let e = entry.endOdometer { endOdoText = String(format: "%.1f", e) }
                }
                withAnimation(.easeInOut(duration: 0.2)) {
                    showManualMileageDrawer.toggle()
                }
            }
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Color.green.opacity(0.15))
            .foregroundStyle(.green)
            .clipShape(Capsule())
        }
    }

    private func drawerSection(daily: DailySummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            HStack(spacing: 8) {
                TextField("Custom miles (e.g. 2.5)", text: $customMilesText)
                    .keyboardType(.decimalPad)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color(.tertiarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                Button("Add") {
                    if let val = Double(customMilesText), val > 0 {
                        store.addManualMiles(val, kind: .custom)
                        customMilesText = ""
                        dismissKeyboard()
                    }
                }
                .font(.caption.weight(.bold))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.green)
                .foregroundStyle(.black)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            HStack(spacing: 8) {
                TextField("Start Odo", text: $startOdoText)
                    .keyboardType(.decimalPad)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color(.tertiarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                TextField("End Odo", text: $endOdoText)
                    .keyboardType(.decimalPad)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color(.tertiarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                Button("Apply") {
                    if let s = Double(startOdoText), let e = Double(endOdoText), s >= 0, e > s {
                        store.applyOdometer(start: s, end: e)
                        dismissKeyboard()
                        onStatusMessage(String(format: "Applied odometer: %.1f mi", e - s))
                    } else {
                        onStatusMessage("End odometer must be greater than start.")
                    }
                }
                .font(.caption.weight(.bold))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.tertiarySystemGroupedBackground))
                .foregroundStyle(.green)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            if !store.todayEntry.entries.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Today's Manual Entries")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(store.todayEntry.entries.reversed()) { entry in
                        HStack {
                            Text(entry.timestamp.formatted(date: .omitted, time: .shortened))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(entry.kind.rawValue.capitalized)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(String(format: "%.1f mi", entry.miles))
                                .font(.caption2.weight(.bold))
                            Button {
                                store.deleteManualEntry(id: entry.id)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.caption2)
                                    .foregroundStyle(.red)
                            }
                            .accessibilityLabel("Delete manual entry")
                        }
                        .padding(.vertical, 2)
                    }
                }
                .padding(8)
                .background(Color(.tertiarySystemGroupedBackground).opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            HStack(alignment: .top) {
                Text(String(format: "IRS rate: $%.2f/mi • Estimates only; verify at irs.gov & keep a log.", daily.irsRate))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Reset Manual/GPS", role: .destructive) {
                    showResetConfirmation = true
                }
                .font(.caption2.weight(.semibold))
            }
        }
    }

    private func dailyKpiBox(label: String, value: String, sub: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(sub)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(Color(.tertiarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value), \(sub)")
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
