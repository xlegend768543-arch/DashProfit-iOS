import Foundation
import Observation
import os

@Observable
final class DashStore {
    var settings: DashSettings {
        didSet {
            settings.save()
            invalidateSummaryCache()
        }
    }

    var orders: [LoggedOrder] {
        didSet {
            invalidateSummaryCache()
            scheduleSave()
        }
    }

    var shifts: [LoggedShift] {
        didSet {
            invalidateSummaryCache()
            scheduleSave()
        }
    }

    var dailyMileage: [String: DailyMileageEntry] {
        didSet {
            invalidateSummaryCache()
            scheduleSave()
        }
    }

    var expenses: [LoggedExpense] {
        didSet {
            invalidateSummaryCache()
            scheduleSave()
        }
    }

    /// Shown once at launch: recovered GPS session and/or data-file recovery.
    var startupMessage: String?

    private let legacyOrdersKey = "dashprofit_ios_orders_v1"
    private let legacyShiftsKey = "dashprofit_ios_shifts_v1"
    private let legacyDailyMileageKey = "dashprofit_ios_daily_mileage_v1"
    private let seededKey = "dashprofit_ios_seeded_v1"

    private let storeFileURL: URL
    private static let logger = Logger(subsystem: "com.dashprofit.app", category: "storage")
    private var saveWorkItem: DispatchWorkItem?
    private var cachedTodayBase: (dateKey: String, base: DailySummary)?

    init(storeURL: URL? = nil, skipAutoSeed: Bool = false) {
        self.settings = DashSettings.load()
        if let storeURL {
            self.storeFileURL = storeURL
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            let dir = appSupport.appendingPathComponent("DashProfit", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            self.storeFileURL = dir.appendingPathComponent("dashprofit_store_v2.json")
        }

        var notices: [String] = []
        let loaded = StoreFileLoader.load(from: self.storeFileURL)
        if let message = loaded.message {
            notices.append(message)
        }

        if let blob = loaded.blob {
            self.orders = blob.orders
            self.shifts = blob.shifts
            self.dailyMileage = blob.dailyMileage
            self.expenses = blob.expenses
        } else {
            // No data file yet: migrate legacy UserDefaults storage on first launch
            var loadedOrders: [LoggedOrder] = []
            if let data = UserDefaults.standard.data(forKey: legacyOrdersKey),
               let decoded = try? JSONDecoder().decode([LoggedOrder].self, from: data) {
                loadedOrders = decoded
            }
            var loadedShifts: [LoggedShift] = []
            if let data = UserDefaults.standard.data(forKey: legacyShiftsKey),
               let decoded = try? JSONDecoder().decode([LoggedShift].self, from: data) {
                loadedShifts = decoded
            }
            var loadedDaily: [String: DailyMileageEntry] = [:]
            if let data = UserDefaults.standard.data(forKey: legacyDailyMileageKey),
               let decoded = try? JSONDecoder().decode([String: DailyMileageEntry].self, from: data) {
                loadedDaily = decoded
            }
            self.orders = loadedOrders
            self.shifts = loadedShifts
            self.dailyMileage = loadedDaily
            self.expenses = []
        }

        if !skipAutoSeed && self.orders.isEmpty && !UserDefaults.standard.bool(forKey: seededKey) {
            UserDefaults.standard.set(true, forKey: seededKey)
            loadSampleOrders()
        }

        // Recover interrupted live GPS / shift session if present
        if !skipAutoSeed, let recovered = MileageTrackerService.consumeRecoveredDraft(settings: self.settings) {
            if let shift = recovered.shift {
                self.shifts.insert(shift, at: 0)
            }
            if recovered.extraShiftSeconds > 0 {
                var entry = self.dailyMileage[recovered.dateKey] ?? DailyMileageEntry()
                entry.shiftSeconds += recovered.extraShiftSeconds
                self.dailyMileage[recovered.dateKey] = entry
            }
            if let shift = recovered.shift {
                notices.append(String(format: "Recovered %.2f GPS mi from your last session.", shift.miles))
            }
        }

        self.startupMessage = notices.isEmpty ? nil : notices.joined(separator: "\n\n")
        flushSave()
    }

    // MARK: - Debounced File Persistence

    private func invalidateSummaryCache() {
        cachedTodayBase = nil
    }

    private func scheduleSave() {
        saveWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.flushSave()
        }
        saveWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: item)
    }

    func flushSave() {
        saveWorkItem?.cancel()
        saveWorkItem = nil
        do {
            let data = try JSONEncoder().encode(currentBlob)
            try data.write(to: storeFileURL, options: .atomic)
        } catch {
            Self.logger.error("Saving data file failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private var currentBlob: PersistedStoreBlob {
        PersistedStoreBlob(
            orders: orders,
            shifts: shifts,
            dailyMileage: dailyMileage,
            expenses: expenses
        )
    }

    // MARK: - Backup & Restore

    func makeBackup(now: Date = Date()) -> DashBackup {
        DashBackup(exportedAt: now, settings: settings.sanitized, data: currentBlob)
    }

    /// Replaces all data and settings with the backup. The data being replaced is
    /// first written next to the data file as `<name>.pre-restore.json`.
    func restore(from backup: DashBackup) {
        flushSave()
        let safetyCopy = storeFileURL.deletingPathExtension().appendingPathExtension("pre-restore.json")
        do {
            try JSONEncoder().encode(currentBlob).write(to: safetyCopy, options: .atomic)
        } catch {
            Self.logger.error("Writing pre-restore copy failed: \(error.localizedDescription, privacy: .public)")
        }

        settings = backup.settings.sanitized
        orders = backup.data.orders
        shifts = backup.data.shifts
        dailyMileage = backup.data.dailyMileage
        expenses = backup.data.expenses
        flushSave()
    }

    // MARK: - Today & Period Summaries (Cached Base)

    var todayEntry: DailyMileageEntry {
        dailyMileage[OfferCalculator.localDateKey()] ?? DailyMileageEntry()
    }

    func todaySummary(liveGPSMiles: Double = 0.0, liveShiftSeconds: Int = 0) -> DailySummary {
        let key = OfferCalculator.localDateKey()
        let entry = dailyMileage[key] ?? DailyMileageEntry()
        let base: DailySummary
        if let cached = cachedTodayBase, cached.dateKey == key {
            base = cached.base
        } else {
            let computed = OfferCalculator.dailySummary(
                orders: orders,
                shifts: shifts,
                manualEntries: entry.entries,
                savedGPSMiles: entry.gpsSavedMiles,
                liveGPSMiles: 0.0,
                expenses: expenses,
                shiftHours: Double(entry.shiftSeconds) / 3600.0,
                settings: settings,
                dateKey: key
            )
            cachedTodayBase = (key, computed)
            base = computed
        }

        if liveGPSMiles <= 0 && liveShiftSeconds <= 0 {
            return base
        }

        // Fast path for 1Hz / GPS updates without rescanning arrays
        let s = settings.sanitized
        let gpsMiles = base.gpsMiles + max(0.0, liveGPSMiles)
        let baseMiles = max(gpsMiles, base.tripMiles)
        let totalMiles = baseMiles + base.manualMiles
        let milesSource = (gpsMiles >= base.tripMiles && gpsMiles > 0) ? "gps" : "trips"
        let vehicleCost = totalMiles * s.costPerMile
        let netProfit = base.grossEarnings - vehicleCost - base.otherExpenses
        let taxDeduction = totalMiles * s.irsRate
        let totalDeductions = taxDeduction + base.otherExpenses
        let taxEst = OfferCalculator.computeTaxSetAside(
            grossEarnings: base.grossEarnings,
            taxDeduction: taxDeduction,
            otherExpenses: base.otherExpenses,
            incomeTaxSetAsidePct: s.incomeTaxSetAsidePct
        )
        let totalShiftSeconds = entry.shiftSeconds + max(0, liveShiftSeconds)
        let hoursWorked = totalShiftSeconds > 0 ? Double(totalShiftSeconds) / 3600.0 : base.hoursWorked
        let netPerHour = hoursWorked > 0 ? netProfit / hoursWorked : 0.0
        let goalProgress = s.dailyGoal > 0 ? min(1.0, max(0.0, netProfit / s.dailyGoal)) : 0.0
        let goalRemaining = s.dailyGoal > 0 ? max(0.0, s.dailyGoal - netProfit) : 0.0

        return DailySummary(
            ordersCount: base.ordersCount,
            tripMiles: base.tripMiles,
            gpsMiles: gpsMiles,
            manualMiles: base.manualMiles,
            totalMiles: totalMiles,
            milesSource: milesSource,
            grossEarnings: base.grossEarnings,
            vehicleCost: vehicleCost,
            otherExpenses: base.otherExpenses,
            netProfit: netProfit,
            taxDeduction: taxDeduction,
            totalDeductions: totalDeductions,
            taxSetAside: taxEst.setAside,
            hoursWorked: hoursWorked,
            netPerHour: netPerHour,
            goalProgress: goalProgress,
            goalRemaining: goalRemaining,
            dailyGoal: s.dailyGoal,
            irsRate: s.irsRate
        )
    }

    func summary(for range: PeriodRange, liveGPSMiles: Double = 0.0, liveShiftSeconds: Int = 0) -> DailySummary {
        if range == .today {
            return todaySummary(liveGPSMiles: liveGPSMiles, liveShiftSeconds: liveShiftSeconds)
        }
        return OfferCalculator.periodSummary(
            orders: orders,
            shifts: shifts,
            dailyData: dailyMileage,
            expenses: expenses,
            settings: settings,
            range: range,
            liveGPSMiles: liveGPSMiles,
            liveShiftHours: Double(max(0, liveShiftSeconds)) / 3600.0
        )
    }

    // MARK: - Manual Mileage & Shift Timer Mutations

    func addManualMiles(_ miles: Double, kind: ManualMileKind = .quick) {
        guard miles > 0 else { return }
        let key = OfferCalculator.localDateKey()
        var entry = dailyMileage[key] ?? DailyMileageEntry()
        entry.entries.append(ManualMileEntry(miles: miles, kind: kind))
        dailyMileage[key] = entry
    }

    @discardableResult
    func undoLastManualMile() -> ManualMileEntry? {
        let key = OfferCalculator.localDateKey()
        var entry = dailyMileage[key] ?? DailyMileageEntry()
        guard let removed = entry.entries.popLast() else { return nil }
        if !entry.entries.contains(where: { $0.kind == .odometer }) {
            entry.startOdometer = nil
            entry.endOdometer = nil
        }
        dailyMileage[key] = entry
        return removed
    }

    func deleteManualEntry(id: UUID) {
        let key = OfferCalculator.localDateKey()
        var entry = dailyMileage[key] ?? DailyMileageEntry()
        entry.entries.removeAll { $0.id == id }
        if !entry.entries.contains(where: { $0.kind == .odometer }) {
            entry.startOdometer = nil
            entry.endOdometer = nil
        }
        dailyMileage[key] = entry
    }

    func applyOdometer(start: Double, end: Double) {
        guard start >= 0, end > start else { return }
        let key = OfferCalculator.localDateKey()
        var entry = dailyMileage[key] ?? DailyMileageEntry()
        entry.entries.removeAll { $0.kind == .odometer }
        entry.entries.append(ManualMileEntry(miles: end - start, kind: .odometer))
        entry.startOdometer = start
        entry.endOdometer = end
        dailyMileage[key] = entry
    }

    func addShiftSeconds(_ seconds: Int) {
        guard seconds > 0 else { return }
        let key = OfferCalculator.localDateKey()
        var entry = dailyMileage[key] ?? DailyMileageEntry()
        entry.shiftSeconds += seconds
        dailyMileage[key] = entry
    }

    func resetTodayManualAndGPS() {
        let key = OfferCalculator.localDateKey()
        var entry = dailyMileage[key] ?? DailyMileageEntry()
        entry.entries.removeAll()
        entry.gpsSavedMiles = 0
        entry.startOdometer = nil
        entry.endOdometer = nil
        dailyMileage[key] = entry

        let cal = Calendar.current
        shifts.removeAll { cal.isDateInToday($0.startTime) }
    }

    // MARK: - Expenses

    func addExpense(amount: Double, category: ExpenseCategory, note: String) {
        guard amount > 0 else { return }
        let cleanNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        expenses.insert(LoggedExpense(amount: amount, category: category, note: cleanNote), at: 0)
    }

    func deleteExpense(id: UUID) {
        expenses.removeAll { $0.id == id }
    }

    func clearExpenses() {
        expenses.removeAll()
    }

    // MARK: - Shifts & Orders

    func addShift(_ shift: LoggedShift) {
        shifts.insert(shift, at: 0)
    }

    func clearShifts() {
        shifts.removeAll()
    }

    func logOrder(
        evaluation: OfferEvaluation,
        decision: OrderDecision,
        merchant: String,
        orderType: OrderType,
        deadheadMultiplier: Double,
        waitMinutes: Int
    ) {
        let entry = LoggedOrder(
            evaluation: evaluation,
            merchant: merchant,
            orderType: orderType,
            deadheadMultiplier: deadheadMultiplier,
            waitMinutes: waitMinutes,
            decision: decision
        )
        orders.insert(entry, at: 0)
    }

    /// Re-evaluates an existing order with corrected inputs (keeps its id and time).
    /// Returns false if the inputs don't form a valid offer or the order is gone.
    @discardableResult
    func updateOrder(
        id: UUID,
        payout: Double,
        miles: Double,
        minutes: Int,
        deadheadMultiplier: Double,
        waitMinutes: Int,
        orderType: OrderType,
        merchant: String,
        decision: OrderDecision
    ) -> Bool {
        guard let index = orders.firstIndex(where: { $0.id == id }),
              let evaluation = OfferCalculator.evaluate(
                payout: payout,
                miles: miles,
                minutes: minutes,
                deadheadMultiplier: deadheadMultiplier,
                waitMinutes: waitMinutes,
                settings: settings
              ) else {
            return false
        }
        let original = orders[index]
        orders[index] = LoggedOrder(
            id: original.id,
            timestamp: original.timestamp,
            evaluation: evaluation,
            merchant: merchant,
            orderType: orderType,
            deadheadMultiplier: deadheadMultiplier,
            waitMinutes: waitMinutes,
            decision: decision,
            isSample: original.isSample
        )
        return true
    }

    func deleteOrder(id: UUID) {
        orders.removeAll { $0.id == id }
    }

    func clearOrders() {
        orders.removeAll()
    }

    func removeSampleOrders() {
        orders.removeAll { $0.isSample }
    }

    func loadSampleOrders() {
        let now = Date()
        let samples: [(Double, Double, Int, Double, Int, OrderType, String, OrderDecision, TimeInterval)] = [
            (11.50, 3.1, 17, 1.0, 0, .food, "Chipotle", .take, -10800),
            (18.25, 6.4, 32, 1.0, 5, .shop, "Target (6 items)", .take, -8400),
            (4.50, 5.8, 22, 1.5, 5, .food, "Popeyes", .pass, -6900),
            (14.00, 4.2, 24, 1.0, 0, .stack, "Panera + Starbucks", .take, -5700),
            (9.75, 2.3, 15, 1.0, 0, .food, "Chick-fil-A", .take, -3600),
            (13.00, 9.4, 34, 2.0, 0, .food, "Outback", .pass, -2100),
            (16.50, 4.9, 26, 1.0, 0, .food, "Sushi Bar", .take, -900)
        ]

        var generated: [LoggedOrder] = []
        for s in samples {
            if let eval = OfferCalculator.evaluate(
                payout: s.0,
                miles: s.1,
                minutes: s.2,
                deadheadMultiplier: s.3,
                waitMinutes: s.4,
                settings: settings
            ) {
                generated.append(LoggedOrder(
                    timestamp: now.addingTimeInterval(s.8),
                    evaluation: eval,
                    merchant: s.6,
                    orderType: s.5,
                    deadheadMultiplier: s.3,
                    waitMinutes: s.4,
                    decision: s.7,
                    isSample: true
                ))
            }
        }
        orders.insert(contentsOf: generated, at: 0)
    }

    // MARK: - CSV Exports

    private static func escapeCSV(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }

    static func buildOrdersCSV(orders: [LoggedOrder]) -> String {
        let header = "Date,Decision,Merchant,OrderType,Payout,ShownMiles,EffectiveMiles,EffectiveMinutes,VehicleCost,NetProfit,NetHourly,EffectivePerMile,TaxDeduction,Score,IsSample"
        let formatter = ISO8601DateFormatter()
        let rows = orders.map { o in
            [
                formatter.string(from: o.timestamp),
                o.decision.rawValue,
                escapeCSV(o.merchant),
                o.orderType.rawValue,
                String(format: "%.2f", o.payout),
                String(format: "%.1f", o.shownMiles),
                String(format: "%.1f", o.effectiveMiles),
                "\(o.effectiveMinutes)",
                String(format: "%.2f", o.vehicleCost),
                String(format: "%.2f", o.netProfit),
                String(format: "%.2f", o.netHourly),
                String(format: "%.2f", o.effectivePerMile),
                String(format: "%.2f", o.taxDeduction),
                "\(o.score)",
                o.isSample ? "true" : "false"
            ].joined(separator: ",")
        }
        return ([header] + rows).joined(separator: "\n")
    }

    static func buildMileageLogCSV(
        orders: [LoggedOrder],
        shifts: [LoggedShift],
        dailyMileage: [String: DailyMileageEntry],
        expenses: [LoggedExpense],
        settings: DashSettings
    ) -> String {
        let header = "Date,StartOdometer,EndOdometer,TripEstMiles,GPSMiles,ManualMiles,BusinessMiles,MilesSource,StandardRate,MileageDeduction,OtherExpenses,TotalDeductions,BusinessPurpose"

        var keys = Set<String>()
        for o in orders where !o.isSample && o.decision == .take {
            keys.insert(OfferCalculator.localDateKey(for: o.timestamp))
        }
        for sh in shifts {
            keys.insert(OfferCalculator.localDateKey(for: sh.startTime))
        }
        for k in dailyMileage.keys {
            keys.insert(k)
        }
        for e in expenses {
            keys.insert(OfferCalculator.localDateKey(for: e.timestamp))
        }

        var rows: [String] = []
        for dateKey in keys.sorted() {
            let rec = dailyMileage[dateKey] ?? DailyMileageEntry()
            let sum = OfferCalculator.dailySummary(
                orders: orders,
                shifts: shifts,
                manualEntries: rec.entries,
                savedGPSMiles: rec.gpsSavedMiles,
                liveGPSMiles: 0.0,
                expenses: expenses,
                settings: settings,
                dateKey: dateKey
            )
            if sum.totalMiles <= 0 && sum.otherExpenses <= 0 && sum.grossEarnings <= 0 {
                continue
            }
            let startStr = rec.startOdometer.map { String(format: "%.1f", $0) } ?? ""
            let endStr = rec.endOdometer.map { String(format: "%.1f", $0) } ?? ""
            rows.append([
                dateKey,
                startStr,
                endStr,
                String(format: "%.2f", sum.tripMiles),
                String(format: "%.2f", sum.gpsMiles),
                String(format: "%.2f", sum.manualMiles),
                String(format: "%.2f", sum.totalMiles),
                sum.milesSource,
                String(format: "%.2f", sum.irsRate),
                String(format: "%.2f", sum.taxDeduction),
                String(format: "%.2f", sum.otherExpenses),
                String(format: "%.2f", sum.totalDeductions),
                "DoorDash delivery"
            ].joined(separator: ","))
        }

        return ([header] + rows).joined(separator: "\n")
    }

    static func buildExpensesCSV(expenses: [LoggedExpense]) -> String {
        let header = "Date,Category,Amount,Note"
        let rows = expenses.map { e in
            [
                OfferCalculator.localDateKey(for: e.timestamp),
                escapeCSV(e.category.rawValue),
                String(format: "%.2f", e.amount),
                escapeCSV(e.note)
            ].joined(separator: ",")
        }
        return ([header] + rows).joined(separator: "\n")
    }

    func exportCSV() -> String {
        Self.buildOrdersCSV(orders: orders)
    }

    func exportMileageCSV() -> String {
        Self.buildMileageLogCSV(
            orders: orders,
            shifts: shifts,
            dailyMileage: dailyMileage,
            expenses: expenses,
            settings: settings
        )
    }

    func exportExpensesCSV() -> String {
        Self.buildExpensesCSV(expenses: expenses)
    }
}
