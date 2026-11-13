import SwiftUI
import UIKit

struct InsightsView: View {
    @Bindable var store: DashStore
    @Bindable var mileageTracker: MileageTrackerService

    @State private var selectedPeriod: PeriodRange = .today
    @State private var expenseAmountText = ""
    @State private var expenseCategory: ExpenseCategory = .toll
    @State private var expenseNoteText = ""
    @State private var showClearOrdersConfirmation = false
    @State private var showClearShiftsConfirmation = false
    @State private var showClearExpensesConfirmation = false

    private var nonSampleOrders: [LoggedOrder] {
        store.orders.filter { !$0.isSample }
    }

    private var takenOrders: [LoggedOrder] {
        nonSampleOrders.filter { $0.decision == .take }
    }

    private var totalNetProfit: Double {
        takenOrders.reduce(0) { $0 + $1.netProfit }
    }

    private var avgNetHourly: Double {
        let mins = takenOrders.reduce(0) { $0 + $1.effectiveMinutes }
        return mins > 0 ? (totalNetProfit / Double(mins)) * 60.0 : 0.0
    }

    private var avgPerMile: Double {
        let miles = takenOrders.reduce(0) { $0 + $1.effectiveMiles }
        let payout = takenOrders.reduce(0) { $0 + $1.payout }
        return miles > 0 ? payout / miles : 0.0
    }

    private var acceptRate: Int {
        guard !nonSampleOrders.isEmpty else { return 0 }
        return Int((Double(takenOrders.count) / Double(nonSampleOrders.count) * 100.0).rounded())
    }

    private var patterns: [PatternSummary] {
        OfferCalculator.analyzePatterns(orders: store.orders)
    }

    private var hasSampleOrders: Bool {
        store.orders.contains(where: \.isSample)
    }

    var body: some View {
        let liveGPS = mileageTracker.isTracking ? mileageTracker.shiftMiles : 0.0
        let liveShift = mileageTracker.isShiftTiming ? mileageTracker.liveShiftElapsedSeconds : 0
        let summary = store.summary(for: selectedPeriod, liveGPSMiles: liveGPS, liveShiftSeconds: liveShift)
        let milesSourceLabel = summary.milesSource == "gps" ? "Using GPS miles" : "Using trip estimates"

        NavigationStack {
            List {
                // Section 1: Mileage, Tax & Net Profit
                Section {
                    Picker("Period", selection: $selectedPeriod) {
                        ForEach(PeriodRange.allCases) { range in
                            Text(range.rawValue).tag(range)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        kpiBox(
                            "Business Miles",
                            String(format: "%.1f mi", summary.totalMiles),
                            sub: milesSourceLabel
                        )
                        kpiBox(
                            "Tax Write-Off",
                            String(format: "$%.2f", summary.totalDeductions),
                            sub: String(format: "IRS $%.2f + Exp $%.2f", summary.taxDeduction, summary.otherExpenses),
                            tint: .green
                        )
                        kpiBox(
                            "Net Profit (cash)",
                            String(format: "%@$%.2f", summary.netProfit < 0 ? "-" : "", abs(summary.netProfit)),
                            sub: summary.hoursWorked > 0
                                ? String(format: "$%.2f/hr (%.1fh)", summary.netPerHour, summary.hoursWorked)
                                : "After car & expenses",
                            tint: summary.netProfit < 0 ? .red : (summary.netProfit > 0 ? .green : .primary)
                        )
                        kpiBox(
                            "Est. Tax Set-Aside",
                            String(format: "$%.2f", summary.taxSetAside),
                            sub: String(format: "Gross $%.0f • Car -$%.2f", summary.grossEarnings, summary.vehicleCost)
                        )
                    }
                    .padding(.vertical, 4)

                    Text(String(format: "Trips (%d): %.1f mi • GPS: %.1f mi • Manual: %.1f mi • %@",
                                summary.ordersCount, summary.tripMiles, summary.gpsMiles, summary.manualMiles, milesSourceLabel))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if selectedPeriod == .today {
                        HStack(spacing: 8) {
                            Text("Quick add:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button("+1 mi") { store.addManualMiles(1.0, kind: .quick) }
                                .buttonStyle(.bordered)
                                .controlSize(.mini)
                            Button("+5 mi") { store.addManualMiles(5.0, kind: .quick) }
                                .buttonStyle(.bordered)
                                .controlSize(.mini)
                            Spacer()
                        }
                    }
                } header: {
                    HStack {
                        Text("Mileage, Tax & Net Profit")
                        Spacer()
                        Text(String(format: "@ $%.2f/mi", summary.irsRate))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("Tax Write-Off is your estimated Schedule C deduction (standard mileage + logged expenses), not a dollar-for-dollar tax credit. Verify rates at irs.gov.")
                        .font(.caption2)
                }

                // Section 2: Other Deductible Expenses
                Section {
                    VStack(spacing: 8) {
                        HStack(spacing: 8) {
                            TextField("Amount ($)", text: $expenseAmountText)
                                .keyboardType(.decimalPad)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(Color(.tertiarySystemGroupedBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 8))

                            Picker("Category", selection: $expenseCategory) {
                                ForEach(ExpenseCategory.allCases) { category in
                                    Text(category.rawValue).tag(category)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color(.tertiarySystemGroupedBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }

                        HStack(spacing: 8) {
                            TextField("Note (optional)", text: $expenseNoteText)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(Color(.tertiarySystemGroupedBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 8))

                            Button("Add Expense") {
                                if let amount = Double(expenseAmountText), amount > 0 {
                                    store.addExpense(amount: amount, category: expenseCategory, note: expenseNoteText)
                                    expenseAmountText = ""
                                    expenseNoteText = ""
                                    dismissKeyboard()
                                }
                            }
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background((Double(expenseAmountText) ?? 0) > 0 ? Color.green : Color.green.opacity(0.35))
                            .foregroundStyle(.black)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .disabled((Double(expenseAmountText) ?? 0) <= 0)
                        }
                    }
                    .padding(.vertical, 4)

                    if store.expenses.isEmpty {
                        Text("No extra business expenses logged yet (tolls, parking, phone mounts, hot bags).")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(store.expenses) { expense in
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 6) {
                                        Text(expense.category.rawValue)
                                            .font(.caption2.weight(.bold))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.green.opacity(0.18))
                                            .foregroundStyle(.green)
                                            .clipShape(Capsule())
                                        if !expense.note.isEmpty {
                                            Text(expense.note)
                                                .font(.subheadline.weight(.medium))
                                                .lineLimit(1)
                                        }
                                    }
                                    Text(expense.timestamp.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(String(format: "$%.2f", expense.amount))
                                    .font(.subheadline.weight(.bold))
                            }
                        }
                        .onDelete { offsets in
                            let ids = offsets.map { store.expenses[$0].id }
                            ids.forEach { store.deleteExpense(id: $0) }
                        }
                    }
                } header: {
                    HStack {
                        Text("Other Deductible Expenses")
                        Spacer()
                        if !store.expenses.isEmpty {
                            Button("Clear", role: .destructive) {
                                showClearExpensesConfirmation = true
                            }
                            .font(.caption.weight(.semibold))
                        }
                    }
                }

                // Section 3: All-Time Performance (Real Orders)
                Section {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        kpiBox("True Net $/Hr", String(format: "$%.2f", avgNetHourly))
                        kpiBox("Total Net Profit", String(format: "$%.2f", totalNetProfit))
                        kpiBox("Avg $/Mile", String(format: "$%.2f", avgPerMile))
                        kpiBox("Accept Rate", "\(acceptRate)%")
                    }
                    .padding(.vertical, 4)
                } header: {
                    HStack {
                        Text("All-Time Performance (Real Orders)")
                        Spacer()
                        if hasSampleOrders {
                            Button("Remove Samples") {
                                store.removeSampleOrders()
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                        } else {
                            Button("Load Sample") {
                                store.loadSampleOrders()
                            }
                            .font(.caption.weight(.semibold))
                        }
                    }
                }

                // Section 4: Most Profitable Order Patterns
                Section("Most Profitable Order Patterns") {
                    if patterns.isEmpty {
                        Text("Log at least 2 real taken orders to see which order types and distances earn you the most.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        let maxHr = max(1.0, patterns.map(\.netHourly).max() ?? 1.0)
                        ForEach(patterns) { pattern in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("\(pattern.label) (\(pattern.count))")
                                        .font(.subheadline.weight(.semibold))
                                    Spacer()
                                    Text(String(format: "$%.2f/hr • $%.2f/mi", pattern.netHourly, pattern.avgPerMile))
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(.green)
                                }
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        Capsule().fill(Color(.tertiarySystemFill))
                                        Capsule()
                                            .fill(Color.green)
                                            .frame(width: max(12, geo.size.width * min(1.0, pattern.netHourly / maxHr)))
                                    }
                                }
                                .frame(height: 8)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                // Section 5: GPS Shift Mileage
                Section {
                    if store.shifts.isEmpty {
                        Text("Tap Start GPS on the Evaluate tab to track your shift miles automatically via GPS.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(store.shifts) { shift in
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(shift.startTime.formatted(date: .abbreviated, time: .shortened))
                                        .font(.subheadline.weight(.semibold))
                                    Text(String(format: "%.2f mi • Car cost: $%.2f", shift.miles, shift.vehicleCost))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(String(format: "$%.2f tax", shift.taxDeduction))
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text("GPS Shift Mileage")
                        Spacer()
                        if !store.shifts.isEmpty {
                            Button("Clear", role: .destructive) {
                                showClearShiftsConfirmation = true
                            }
                            .font(.caption.weight(.semibold))
                        }
                    }
                }

                // Section 6: Order Log
                Section {
                    if store.orders.isEmpty {
                        Text("No orders logged yet.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(store.orders) { order in
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 6) {
                                        Text(order.decision.label)
                                            .font(.caption2.weight(.heavy))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(order.decision == .take ? Color.green.opacity(0.2) : Color.red.opacity(0.2))
                                            .foregroundStyle(order.decision == .take ? .green : .red)
                                            .clipShape(RoundedRectangle(cornerRadius: 5))
                                        if order.isSample {
                                            Text("SAMPLE")
                                                .font(.caption2.weight(.heavy))
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Color.orange.opacity(0.2))
                                                .foregroundStyle(.orange)
                                                .clipShape(Capsule())
                                        }
                                        Text(order.merchant)
                                            .font(.subheadline.weight(.semibold))
                                    }
                                    Text(String(format: "%@ • $%.2f • %.1f mi • %dm",
                                                order.timestamp.formatted(date: .omitted, time: .shortened),
                                                order.payout,
                                                order.shownMiles,
                                                order.effectiveMinutes))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(String(format: "$%.2f/hr", order.netHourly))
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(.green)
                            }
                        }
                        .onDelete { offsets in
                            let ids = offsets.map { store.orders[$0].id }
                            ids.forEach { store.deleteOrder(id: $0) }
                        }
                    }
                } header: {
                    HStack {
                        Text("Order Log")
                        Spacer()
                        if !store.orders.isEmpty {
                            Button("Clear All", role: .destructive) {
                                showClearOrdersConfirmation = true
                            }
                            .font(.caption.weight(.semibold))
                        }
                    }
                }
            }
            .navigationTitle("Insights")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        ShareLink("Export Orders CSV", item: store.exportCSV(), preview: SharePreview("DashProfit Orders CSV"))
                        ShareLink("Export IRS Mileage Log CSV", item: store.exportMileageCSV(), preview: SharePreview("DashProfit IRS Mileage Log CSV"))
                        ShareLink("Export Expenses CSV", item: store.exportExpensesCSV(), preview: SharePreview("DashProfit Expenses CSV"))
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Export CSV reports")
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { dismissKeyboard() }
                }
            }
            .confirmationDialog(
                "Clear All Logged Orders?",
                isPresented: $showClearOrdersConfirmation,
                titleVisibility: .visible
            ) {
                Button("Clear All Orders", role: .destructive) {
                    store.clearOrders()
                }
                Button("Cancel", role: .cancel) {}
            }
            .confirmationDialog(
                "Clear All GPS Shifts?",
                isPresented: $showClearShiftsConfirmation,
                titleVisibility: .visible
            ) {
                Button("Clear GPS Shifts", role: .destructive) {
                    store.clearShifts()
                }
                Button("Cancel", role: .cancel) {}
            }
            .confirmationDialog(
                "Clear All Expenses?",
                isPresented: $showClearExpensesConfirmation,
                titleVisibility: .visible
            ) {
                Button("Clear Expenses", role: .destructive) {
                    store.clearExpenses()
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    private func kpiBox(_ title: String, _ value: String, sub: String? = nil, tint: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            if let sub {
                Text(sub)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(.tertiarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value)\(sub.map { ", \($0)" } ?? "")")
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
