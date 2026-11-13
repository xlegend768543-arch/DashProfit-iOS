import Foundation

enum OrderType: String, CaseIterable, Codable, Identifiable {
    case food = "Food"
    case shop = "Shop"
    case stack = "Stack"

    var id: String { rawValue }
}

enum DeadheadOption: Double, CaseIterable, Identifiable {
    case inZone = 1.0
    case edge = 1.5
    case roundTrip = 2.0

    var id: Double { rawValue }

    var label: String {
        switch self {
        case .inZone: return "In Zone"
        case .edge: return "Edge (+50%)"
        case .roundTrip: return "Round Trip"
        }
    }

    var hint: String {
        switch self {
        case .inZone: return "Ends in zone (1.0x mi)"
        case .edge: return "Partial return (+50% mi)"
        case .roundTrip: return "Full round trip (2.0x mi)"
        }
    }
}

enum WaitRiskOption: Int, CaseIterable, Identifiable {
    case fast = 0
    case moderate = 5
    case slow = 10

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .fast: return "Fast"
        case .moderate: return "+5m"
        case .slow: return "+10m"
        }
    }
}

enum OfferVerdict: String, Codable {
    case take
    case maybe
    case pass

    var badgeText: String {
        switch self {
        case .take: return "STRONG TAKE"
        case .maybe: return "BORDERLINE"
        case .pass: return "PASS / DECLINE"
        }
    }
}

enum OrderDecision: String, Codable {
    case take
    case pass

    var label: String {
        self == .take ? "TAKEN" : "PASSED"
    }
}

struct DashSettings: Codable, Equatable {
    var minNetHourly: Double = 22.0
    var minPerMile: Double = 1.75
    var minPayout: Double = 6.50
    var mpg: Double = 28.0
    var gasPrice: Double = 3.65
    var wearPerMile: Double = 0.12
    /// Standard mileage rate. Default left at 0.70 (user-editable); verify the current rate at irs.gov.
    var irsRate: Double = 0.70
    /// Daily net-profit goal in dollars. 0 disables the goal bar.
    var dailyGoal: Double = 150.0
    /// Fraction (0...0.5) of post-deduction income to set aside for income tax.
    var incomeTaxSetAsidePct: Double = 0.10

    init() {}

    private enum CodingKeys: String, CodingKey {
        case minNetHourly, minPerMile, minPayout, mpg, gasPrice, wearPerMile, irsRate, dailyGoal, incomeTaxSetAsidePct
    }

    init(from decoder: Decoder) throws {
        let d = DashSettings()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        minNetHourly = try c.decodeIfPresent(Double.self, forKey: .minNetHourly) ?? d.minNetHourly
        minPerMile = try c.decodeIfPresent(Double.self, forKey: .minPerMile) ?? d.minPerMile
        minPayout = try c.decodeIfPresent(Double.self, forKey: .minPayout) ?? d.minPayout
        mpg = try c.decodeIfPresent(Double.self, forKey: .mpg) ?? d.mpg
        gasPrice = try c.decodeIfPresent(Double.self, forKey: .gasPrice) ?? d.gasPrice
        wearPerMile = try c.decodeIfPresent(Double.self, forKey: .wearPerMile) ?? d.wearPerMile
        irsRate = try c.decodeIfPresent(Double.self, forKey: .irsRate) ?? d.irsRate
        dailyGoal = try c.decodeIfPresent(Double.self, forKey: .dailyGoal) ?? d.dailyGoal
        incomeTaxSetAsidePct = try c.decodeIfPresent(Double.self, forKey: .incomeTaxSetAsidePct) ?? d.incomeTaxSetAsidePct
    }

    var costPerMile: Double {
        let safeMpg = max(1.0, mpg)
        return max(0.0, gasPrice) / safeMpg + max(0.0, wearPerMile)
    }

    // MARK: - Sanitation (single source of truth for defaults + limits)

    /// Non-finite -> default; otherwise clamped to `lo...hi`. 0 stays 0 when `lo` is 0.
    static func clean(_ value: Double, default fallback: Double, min lo: Double = 0, max hi: Double = .greatestFiniteMagnitude) -> Double {
        guard value.isFinite else { return fallback }
        return Swift.min(Swift.max(value, lo), hi)
    }

    /// Parses user text: empty / unparsable / non-finite -> default, "0" stays 0.
    static func number(from text: String?, default fallback: Double) -> Double {
        let trimmed = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let v = Double(trimmed), v.isFinite else { return fallback }
        return v
    }

    var sanitized: DashSettings {
        let d = DashSettings()
        var s = self
        s.minNetHourly = Self.clean(minNetHourly, default: d.minNetHourly)
        s.minPerMile = Self.clean(minPerMile, default: d.minPerMile)
        s.minPayout = Self.clean(minPayout, default: d.minPayout)
        s.mpg = Self.clean(mpg, default: d.mpg, min: 1)
        s.gasPrice = Self.clean(gasPrice, default: d.gasPrice)
        s.wearPerMile = Self.clean(wearPerMile, default: d.wearPerMile)
        s.irsRate = Self.clean(irsRate, default: d.irsRate)
        s.dailyGoal = Self.clean(dailyGoal, default: d.dailyGoal)
        s.incomeTaxSetAsidePct = Self.clean(incomeTaxSetAsidePct, default: d.incomeTaxSetAsidePct, max: 0.5)
        return s
    }

    static let appGroupID = "group.com.dashprofit.app"
    private static let settingsKey = "dashprofit_ios_settings_v1"

    static func loadShared() -> DashSettings {
        if let groupDefaults = UserDefaults(suiteName: appGroupID),
           let data = groupDefaults.data(forKey: settingsKey),
           let decoded = try? JSONDecoder().decode(DashSettings.self, from: data) {
            return decoded.sanitized
        }
        if let data = UserDefaults.standard.data(forKey: settingsKey),
           let decoded = try? JSONDecoder().decode(DashSettings.self, from: data) {
            return decoded.sanitized
        }
        return DashSettings()
    }

    func saveShared() {
        guard let data = try? JSONEncoder().encode(self.sanitized) else { return }
        UserDefaults.standard.set(data, forKey: Self.settingsKey)
        UserDefaults(suiteName: Self.appGroupID)?.set(data, forKey: Self.settingsKey)
    }
}

struct OfferEvaluation: Equatable {
    let payout: Double
    let shownMiles: Double
    let effectiveMiles: Double
    let estMinutes: Int
    let effectiveMinutes: Int
    let costPerMile: Double
    let vehicleCost: Double
    let netProfit: Double
    let grossHourly: Double
    let netHourly: Double
    let grossPerMile: Double
    let effectivePerMile: Double
    let taxDeduction: Double
    let score: Int
    let verdict: OfferVerdict
    let verdictTitle: String
    let reason: String
}

struct LoggedOrder: Codable, Identifiable, Equatable {
    let id: UUID
    let timestamp: Date
    let merchant: String
    let orderType: OrderType
    let deadheadMultiplier: Double
    let waitMinutes: Int
    let decision: OrderDecision
    let payout: Double
    let shownMiles: Double
    let effectiveMiles: Double
    let effectiveMinutes: Int
    let vehicleCost: Double
    let netProfit: Double
    let netHourly: Double
    let effectivePerMile: Double
    let taxDeduction: Double
    let score: Int
    /// Demo data: never counted in miles, gross, net, write-off, set-aside or tax exports.
    var isSample: Bool = false
}

extension LoggedOrder {
    private enum CodingKeys: String, CodingKey {
        case id, timestamp, merchant, orderType, deadheadMultiplier, waitMinutes, decision, payout
        case shownMiles, effectiveMiles, effectiveMinutes, vehicleCost, netProfit, netHourly
        case effectivePerMile, taxDeduction, score, isSample
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try c.decode(UUID.self, forKey: .id),
            timestamp: try c.decode(Date.self, forKey: .timestamp),
            merchant: try c.decode(String.self, forKey: .merchant),
            orderType: try c.decode(OrderType.self, forKey: .orderType),
            deadheadMultiplier: try c.decode(Double.self, forKey: .deadheadMultiplier),
            waitMinutes: try c.decode(Int.self, forKey: .waitMinutes),
            decision: try c.decode(OrderDecision.self, forKey: .decision),
            payout: try c.decode(Double.self, forKey: .payout),
            shownMiles: try c.decode(Double.self, forKey: .shownMiles),
            effectiveMiles: try c.decode(Double.self, forKey: .effectiveMiles),
            effectiveMinutes: try c.decode(Int.self, forKey: .effectiveMinutes),
            vehicleCost: try c.decode(Double.self, forKey: .vehicleCost),
            netProfit: try c.decode(Double.self, forKey: .netProfit),
            netHourly: try c.decode(Double.self, forKey: .netHourly),
            effectivePerMile: try c.decode(Double.self, forKey: .effectivePerMile),
            taxDeduction: try c.decode(Double.self, forKey: .taxDeduction),
            score: try c.decode(Int.self, forKey: .score),
            isSample: try c.decodeIfPresent(Bool.self, forKey: .isSample) ?? false
        )
    }
}

struct PatternSummary: Identifiable {
    let id: String
    let label: String
    let count: Int
    let netHourly: Double
    let avgPerMile: Double
}

enum OfferCalculator {
    static func evaluate(
        payout: Double,
        miles: Double,
        minutes: Int,
        deadheadMultiplier: Double,
        waitMinutes: Int,
        settings: DashSettings
    ) -> OfferEvaluation? {
        guard payout > 0, miles >= 0, minutes > 0 else { return nil }

        let effectiveMiles = max(0.1, miles * max(1.0, deadheadMultiplier))
        let effectiveMinutes = max(1, minutes + max(0, waitMinutes))
        let costPerMile = settings.costPerMile
        let vehicleCost = effectiveMiles * costPerMile
        let netProfit = payout - vehicleCost

        let grossHourly = (payout / Double(effectiveMinutes)) * 60.0
        let netHourly = (netProfit / Double(effectiveMinutes)) * 60.0
        let grossPerMile = miles > 0 ? payout / miles : payout
        let effectivePerMile = payout / effectiveMiles
        let taxDeduction = effectiveMiles * max(0.0, settings.irsRate)

        let hourlyRatio = netHourly / max(1.0, settings.minNetHourly)
        let mileRatio = effectivePerMile / max(0.1, settings.minPerMile)
        let payoutPenalty = payout < settings.minPayout ? 18.0 : 0.0
        let rawScore = (hourlyRatio * 55.0 + mileRatio * 45.0) - payoutPenalty
        let score = max(0, min(100, Int(rawScore.rounded())))

        let meetsHourly = netHourly >= settings.minNetHourly
        let meetsMile = effectivePerMile >= settings.minPerMile
        let meetsPayout = payout >= settings.minPayout

        let verdict: OfferVerdict
        let verdictTitle: String

        if meetsHourly && meetsMile && meetsPayout {
            verdict = .take
            verdictTitle = score >= 90 ? "High-efficiency order" : "Meets all profit rules"
        } else if netHourly >= settings.minNetHourly * 0.85 &&
                    effectivePerMile >= settings.minPerMile * 0.85 &&
                    payout >= settings.minPayout * 0.85 {
            verdict = .maybe
            verdictTitle = "Take only if slow or heading home"
        } else {
            verdict = .pass
            if !meetsPayout {
                verdictTitle = String(format: "Below $%.2f minimum", settings.minPayout)
            } else if !meetsMile {
                verdictTitle = "Too many miles for the pay"
            } else {
                verdictTitle = "Too slow for your hourly goal"
            }
        }

        var notes: [String] = []
        if deadheadMultiplier > 1.0 {
            notes.append(String(format: "%.1f eff. mi", effectiveMiles))
        }
        if waitMinutes > 0 {
            notes.append("+\(waitMinutes)m wait")
        }
        let prefix = notes.isEmpty ? "" : "Includes \(notes.joined(separator: ", ")) • "
        let reason = String(format: "%@Nets $%.2f after $%.2f car cost.", prefix, netProfit, vehicleCost)

        return OfferEvaluation(
            payout: payout,
            shownMiles: miles,
            effectiveMiles: effectiveMiles,
            estMinutes: minutes,
            effectiveMinutes: effectiveMinutes,
            costPerMile: costPerMile,
            vehicleCost: vehicleCost,
            netProfit: netProfit,
            grossHourly: grossHourly,
            netHourly: netHourly,
            grossPerMile: grossPerMile,
            effectivePerMile: effectivePerMile,
            taxDeduction: taxDeduction,
            score: score,
            verdict: verdict,
            verdictTitle: verdictTitle,
            reason: reason
        )
    }

    static func analyzePatterns(orders: [LoggedOrder]) -> [PatternSummary] {
        let taken = orders.filter { $0.decision == .take && !$0.isSample }
        guard taken.count >= 2 else { return [] }

        struct Bucket {
            let id: String
            let label: String
            var count = 0
            var netProfit = 0.0
            var minutes = 0
            var miles = 0.0
            var payout = 0.0
        }

        var map: [String: Bucket] = [:]
        func add(_ id: String, _ label: String, _ order: LoggedOrder) {
            var b = map[id] ?? Bucket(id: id, label: label)
            b.count += 1
            b.netProfit += order.netProfit
            b.minutes += order.effectiveMinutes
            b.miles += order.effectiveMiles
            b.payout += order.payout
            map[id] = b
        }

        for order in taken {
            if order.shownMiles < 3 {
                add("dist-short", "Short (< 3 mi)", order)
            } else if order.shownMiles <= 7 {
                add("dist-med", "Medium (3–7 mi)", order)
            } else {
                add("dist-long", "Long (7+ mi)", order)
            }

            switch order.orderType {
            case .food: add("type-food", "Food Delivery", order)
            case .shop: add("type-shop", "Shop & Pay", order)
            case .stack: add("type-stack", "Stacked (2+)", order)
            }

            if order.payout < 8 {
                add("pay-low", "Small (< $8)", order)
            } else if order.payout <= 15 {
                add("pay-mid", "Sweet Spot ($8–$15)", order)
            } else {
                add("pay-high", "High Payout ($15+)", order)
            }
        }

        return map.values
            .map { b in
                PatternSummary(
                    id: b.id,
                    label: b.label,
                    count: b.count,
                    netHourly: (b.netProfit / Double(max(1, b.minutes))) * 60.0,
                    avgPerMile: b.payout / max(0.1, b.miles)
                )
            }
            .sorted { $0.netHourly > $1.netHourly }
    }

    static func localDateKey(for date: Date = Date()) -> String {
        let comps = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", comps.year ?? 2026, comps.month ?? 1, comps.day ?? 1)
    }

    static func computeTaxSetAside(
        grossEarnings: Double,
        taxDeduction: Double,
        otherExpenses: Double,
        incomeTaxSetAsidePct: Double
    ) -> (seBase: Double, seTax: Double, incomeTax: Double, setAside: Double) {
        let seBase = max(0.0, grossEarnings - taxDeduction - otherExpenses)
        let seTax = seBase * 0.9235 * 0.153
        let pct = DashSettings.clean(incomeTaxSetAsidePct, default: 0.10, min: 0, max: 0.5)
        let incomeTax = max(0.0, seBase - seTax / 2.0) * pct
        return (seBase, seTax, incomeTax, seTax + incomeTax)
    }

    static func periodStartDateKey(range: PeriodRange, now: Date = Date()) -> String {
        let cal = Calendar.current
        switch range {
        case .today:
            return localDateKey(for: now)
        case .week:
            if let weekInterval = cal.dateInterval(of: .weekOfYear, for: now) {
                return localDateKey(for: weekInterval.start)
            }
            return localDateKey(for: now)
        case .month:
            let comps = cal.dateComponents([.year, .month], from: now)
            if let start = cal.date(from: comps) {
                return localDateKey(for: start)
            }
            return localDateKey(for: now)
        case .ytd:
            let yr = cal.component(.year, from: now)
            return String(format: "%04d-01-01", yr)
        }
    }

    static func dailySummary(
        orders: [LoggedOrder],
        shifts: [LoggedShift],
        manualEntries: [ManualMileEntry],
        savedGPSMiles: Double = 0.0,
        liveGPSMiles: Double = 0.0,
        expenses: [LoggedExpense] = [],
        shiftHours: Double = 0.0,
        settings: DashSettings,
        dateKey: String = localDateKey()
    ) -> DailySummary {
        let s = settings.sanitized
        let todaysTaken = orders.filter {
            !$0.isSample && $0.decision == .take && localDateKey(for: $0.timestamp) == dateKey
        }
        let todaysShifts = shifts.filter { localDateKey(for: $0.startTime) == dateKey }
        let todaysExpenses = expenses.filter { localDateKey(for: $0.timestamp) == dateKey }

        let tripMiles = todaysTaken.reduce(0.0) { $0 + max(0.0, $1.effectiveMiles) }
        let grossEarnings = todaysTaken.reduce(0.0) { $0 + max(0.0, $1.payout) }
        let orderMinutes = todaysTaken.reduce(0) { $0 + max(0, $1.effectiveMinutes) }

        let shiftGPSMiles = todaysShifts.reduce(0.0) { $0 + max(0.0, $1.miles) }
        let gpsMiles = max(0.0, shiftGPSMiles + savedGPSMiles + liveGPSMiles)
        let manualMiles = manualEntries.reduce(0.0) { $0 + max(0.0, $1.miles) }

        // Prevent double counting: use max(gps, trips) + manual
        let baseMiles = max(gpsMiles, tripMiles)
        let totalMiles = baseMiles + manualMiles
        let milesSource = (gpsMiles >= tripMiles && gpsMiles > 0) ? "gps" : "trips"

        let otherExpenses = todaysExpenses.reduce(0.0) { $0 + max(0.0, $1.amount) }
        let vehicleCost = totalMiles * s.costPerMile
        let netProfit = grossEarnings - vehicleCost - otherExpenses
        let taxDeduction = totalMiles * s.irsRate
        let totalDeductions = taxDeduction + otherExpenses

        let taxEst = computeTaxSetAside(
            grossEarnings: grossEarnings,
            taxDeduction: taxDeduction,
            otherExpenses: otherExpenses,
            incomeTaxSetAsidePct: s.incomeTaxSetAsidePct
        )

        let hoursWorked = shiftHours > 0 ? shiftHours : Double(orderMinutes) / 60.0
        let netPerHour = hoursWorked > 0 ? netProfit / hoursWorked : 0.0
        let goalProgress = s.dailyGoal > 0 ? min(1.0, max(0.0, netProfit / s.dailyGoal)) : 0.0
        let goalRemaining = s.dailyGoal > 0 ? max(0.0, s.dailyGoal - netProfit) : 0.0

        return DailySummary(
            ordersCount: todaysTaken.count,
            tripMiles: tripMiles,
            gpsMiles: gpsMiles,
            manualMiles: manualMiles,
            totalMiles: totalMiles,
            milesSource: milesSource,
            grossEarnings: grossEarnings,
            vehicleCost: vehicleCost,
            otherExpenses: otherExpenses,
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

    static func periodSummary(
        orders: [LoggedOrder],
        shifts: [LoggedShift],
        dailyData: [String: DailyMileageEntry],
        expenses: [LoggedExpense],
        settings: DashSettings,
        range: PeriodRange,
        now: Date = Date(),
        liveGPSMiles: Double = 0.0,
        liveShiftHours: Double = 0.0
    ) -> DailySummary {
        let s = settings.sanitized
        let todayKey = localDateKey(for: now)
        let startKey = periodStartDateKey(range: range, now: now)

        var keys = Set<String>([todayKey])
        for o in orders where !o.isSample && o.decision == .take {
            let k = localDateKey(for: o.timestamp)
            if k >= startKey && k <= todayKey { keys.insert(k) }
        }
        for sh in shifts {
            let k = localDateKey(for: sh.startTime)
            if k >= startKey && k <= todayKey { keys.insert(k) }
        }
        for k in dailyData.keys where k >= startKey && k <= todayKey {
            keys.insert(k)
        }
        for exp in expenses {
            let k = localDateKey(for: exp.timestamp)
            if k >= startKey && k <= todayKey { keys.insert(k) }
        }

        var ordersCount = 0
        var tripMiles = 0.0
        var gpsMiles = 0.0
        var manualMiles = 0.0
        var totalMiles = 0.0
        var grossEarnings = 0.0
        var vehicleCost = 0.0
        var otherExpenses = 0.0
        var netProfit = 0.0
        var taxDeduction = 0.0
        var totalDeductions = 0.0
        var hoursWorked = 0.0

        for k in keys {
            let rec = dailyData[k] ?? DailyMileageEntry()
            let isToday = (k == todayKey)
            let dayShiftHours = Double(rec.shiftSeconds) / 3600.0 + (isToday ? max(0.0, liveShiftHours) : 0.0)
            let daySum = dailySummary(
                orders: orders,
                shifts: shifts,
                manualEntries: rec.entries,
                savedGPSMiles: rec.gpsSavedMiles,
                liveGPSMiles: isToday ? liveGPSMiles : 0.0,
                expenses: expenses,
                shiftHours: dayShiftHours,
                settings: s,
                dateKey: k
            )
            ordersCount += daySum.ordersCount
            tripMiles += daySum.tripMiles
            gpsMiles += daySum.gpsMiles
            manualMiles += daySum.manualMiles
            totalMiles += daySum.totalMiles
            grossEarnings += daySum.grossEarnings
            vehicleCost += daySum.vehicleCost
            otherExpenses += daySum.otherExpenses
            netProfit += daySum.netProfit
            taxDeduction += daySum.taxDeduction
            totalDeductions += daySum.totalDeductions
            hoursWorked += daySum.hoursWorked
        }

        let taxEst = computeTaxSetAside(
            grossEarnings: grossEarnings,
            taxDeduction: taxDeduction,
            otherExpenses: otherExpenses,
            incomeTaxSetAsidePct: s.incomeTaxSetAsidePct
        )
        let milesSource = (gpsMiles >= tripMiles && gpsMiles > 0) ? "gps" : "trips"
        let netPerHour = hoursWorked > 0 ? netProfit / hoursWorked : 0.0
        let goalProgress = s.dailyGoal > 0 ? min(1.0, max(0.0, netProfit / s.dailyGoal)) : 0.0
        let goalRemaining = s.dailyGoal > 0 ? max(0.0, s.dailyGoal - netProfit) : 0.0

        return DailySummary(
            ordersCount: ordersCount,
            tripMiles: tripMiles,
            gpsMiles: gpsMiles,
            manualMiles: manualMiles,
            totalMiles: totalMiles,
            milesSource: milesSource,
            grossEarnings: grossEarnings,
            vehicleCost: vehicleCost,
            otherExpenses: otherExpenses,
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
}

enum ManualMileKind: String, Codable {
    case quick, custom, odometer
}

struct ManualMileEntry: Codable, Identifiable, Equatable {
    let id: UUID
    let timestamp: Date
    let miles: Double
    let kind: ManualMileKind

    init(id: UUID = UUID(), timestamp: Date = Date(), miles: Double, kind: ManualMileKind) {
        self.id = id
        self.timestamp = timestamp
        self.miles = miles
        self.kind = kind
    }
}

struct DailyMileageEntry: Codable, Equatable {
    var entries: [ManualMileEntry] = []
    var gpsSavedMiles: Double = 0
    var startOdometer: Double?
    var endOdometer: Double?
    var shiftSeconds: Int = 0

    var manualMiles: Double {
        entries.reduce(0.0) { $0 + max(0.0, $1.miles) }
    }

    init(
        entries: [ManualMileEntry] = [],
        gpsSavedMiles: Double = 0,
        startOdometer: Double? = nil,
        endOdometer: Double? = nil,
        shiftSeconds: Int = 0
    ) {
        self.entries = entries
        self.gpsSavedMiles = gpsSavedMiles
        self.startOdometer = startOdometer
        self.endOdometer = endOdometer
        self.shiftSeconds = shiftSeconds
    }

    private enum CodingKeys: String, CodingKey {
        case entries, manualMiles, gpsSavedMiles, startOdometer, endOdometer, shiftSeconds
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let decodedEntries = try c.decodeIfPresent([ManualMileEntry].self, forKey: .entries)
        let legacyMiles = try c.decodeIfPresent(Double.self, forKey: .manualMiles) ?? 0.0
        if let decodedEntries {
            self.entries = decodedEntries
        } else if legacyMiles > 0 {
            self.entries = [ManualMileEntry(miles: legacyMiles, kind: .custom)]
        } else {
            self.entries = []
        }
        self.gpsSavedMiles = try c.decodeIfPresent(Double.self, forKey: .gpsSavedMiles) ?? 0.0
        self.startOdometer = try c.decodeIfPresent(Double.self, forKey: .startOdometer)
        self.endOdometer = try c.decodeIfPresent(Double.self, forKey: .endOdometer)
        self.shiftSeconds = try c.decodeIfPresent(Int.self, forKey: .shiftSeconds) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(entries, forKey: .entries)
        try c.encode(gpsSavedMiles, forKey: .gpsSavedMiles)
        try c.encodeIfPresent(startOdometer, forKey: .startOdometer)
        try c.encodeIfPresent(endOdometer, forKey: .endOdometer)
        try c.encode(shiftSeconds, forKey: .shiftSeconds)
    }
}

enum ExpenseCategory: String, CaseIterable, Codable, Identifiable {
    case toll = "Toll"
    case parking = "Parking"
    case phoneMount = "Phone/Mount"
    case supplies = "Hot Bag/Supplies"
    case other = "Other"

    var id: String { rawValue }
}

struct LoggedExpense: Codable, Identifiable, Equatable {
    let id: UUID
    let timestamp: Date
    let amount: Double
    let category: ExpenseCategory
    let note: String

    init(id: UUID = UUID(), timestamp: Date = Date(), amount: Double, category: ExpenseCategory, note: String) {
        self.id = id
        self.timestamp = timestamp
        self.amount = amount
        self.category = category
        self.note = note
    }
}

enum PeriodRange: String, CaseIterable, Identifiable {
    case today = "Today"
    case week = "Week"
    case month = "Month"
    case ytd = "YTD"

    var id: String { rawValue }
}

struct DailySummary: Equatable {
    let ordersCount: Int
    let tripMiles: Double
    let gpsMiles: Double
    let manualMiles: Double
    let totalMiles: Double
    let milesSource: String
    let grossEarnings: Double
    let vehicleCost: Double
    let otherExpenses: Double
    let netProfit: Double
    let taxDeduction: Double
    let totalDeductions: Double
    let taxSetAside: Double
    let hoursWorked: Double
    let netPerHour: Double
    let goalProgress: Double
    let goalRemaining: Double
    let dailyGoal: Double
    let irsRate: Double
}
