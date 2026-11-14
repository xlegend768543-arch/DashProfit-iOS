import Foundation

// MARK: - Building orders from an evaluation

extension LoggedOrder {
    static let defaultMerchantName = "DoorDash Order"

    /// Single place that turns an `OfferEvaluation` into a stored order
    /// (used by logging, editing and sample data).
    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        evaluation e: OfferEvaluation,
        merchant: String,
        orderType: OrderType,
        deadheadMultiplier: Double,
        waitMinutes: Int,
        decision: OrderDecision,
        isSample: Bool = false
    ) {
        let cleanMerchant = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        self.init(
            id: id,
            timestamp: timestamp,
            merchant: cleanMerchant.isEmpty ? Self.defaultMerchantName : cleanMerchant,
            orderType: orderType,
            deadheadMultiplier: deadheadMultiplier,
            waitMinutes: waitMinutes,
            decision: decision,
            payout: e.payout,
            shownMiles: e.shownMiles,
            effectiveMiles: e.effectiveMiles,
            effectiveMinutes: e.effectiveMinutes,
            vehicleCost: e.vehicleCost,
            netProfit: e.netProfit,
            netHourly: e.netHourly,
            effectivePerMile: e.effectivePerMile,
            taxDeduction: e.taxDeduction,
            score: e.score,
            isSample: isSample
        )
    }

    /// The offer's estimated minutes, without the wait-risk padding.
    var estimatedMinutes: Int {
        max(1, effectiveMinutes - max(0, waitMinutes))
    }
}

// MARK: - Merchant history

struct MerchantHistory: Equatable {
    let takenCount: Int
    let passedCount: Int
    /// Net $/hr across taken orders (0 when none were taken).
    let netHourly: Double
    /// Payout per effective mile across taken orders (0 when none were taken).
    let avgPerMile: Double
}

// MARK: - Pattern analysis

extension OfferCalculator {
    /// Lowercased, trimmed, single-spaced, with any "(...)" note removed,
    /// so "Target (6 items)" and "target" match.
    static func normalizedMerchant(_ name: String) -> String {
        var s = name.lowercased()
        while let open = s.firstIndex(of: "("),
              let close = s[open...].firstIndex(of: ")") {
            s.removeSubrange(open...close)
        }
        return s.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Your real (non-sample) history with a merchant, or nil if there is none.
    static func merchantHistory(for merchant: String, in orders: [LoggedOrder]) -> MerchantHistory? {
        let key = normalizedMerchant(merchant)
        guard !key.isEmpty, key != normalizedMerchant(LoggedOrder.defaultMerchantName) else { return nil }

        let matches = orders.filter { !$0.isSample && normalizedMerchant($0.merchant) == key }
        guard !matches.isEmpty else { return nil }

        let taken = matches.filter { $0.decision == .take }
        let net = taken.reduce(0.0) { $0 + $1.netProfit }
        let minutes = taken.reduce(0) { $0 + $1.effectiveMinutes }
        let miles = taken.reduce(0.0) { $0 + $1.effectiveMiles }
        let payout = taken.reduce(0.0) { $0 + $1.payout }

        return MerchantHistory(
            takenCount: taken.count,
            passedCount: matches.count - taken.count,
            netHourly: minutes > 0 ? net / Double(minutes) * 60.0 : 0.0,
            avgPerMile: miles > 0 ? payout / miles : 0.0
        )
    }

    /// Groups real taken orders into buckets and returns per-bucket net $/hr and $/mi,
    /// best first. Returns [] until at least 2 real orders were taken.
    static func bucketSummaries(
        orders: [LoggedOrder],
        bucketsFor: (LoggedOrder) -> [(id: String, label: String)]
    ) -> [PatternSummary] {
        let taken = orders.filter { $0.decision == .take && !$0.isSample }
        guard taken.count >= 2 else { return [] }

        struct Bucket {
            let label: String
            var count = 0
            var netProfit = 0.0
            var minutes = 0
            var miles = 0.0
            var payout = 0.0
        }

        var map: [String: Bucket] = [:]
        for order in taken {
            for key in bucketsFor(order) {
                var b = map[key.id] ?? Bucket(label: key.label)
                b.count += 1
                b.netProfit += order.netProfit
                b.minutes += order.effectiveMinutes
                b.miles += order.effectiveMiles
                b.payout += order.payout
                map[key.id] = b
            }
        }

        return map
            .map { id, b in
                PatternSummary(
                    id: id,
                    label: b.label,
                    count: b.count,
                    netHourly: (b.netProfit / Double(max(1, b.minutes))) * 60.0,
                    avgPerMile: b.payout / max(0.1, b.miles)
                )
            }
            .sorted { ($0.netHourly, $1.id) > ($1.netHourly, $0.id) }
    }

    /// Distance, order type and payout-size buckets.
    static func analyzePatterns(orders: [LoggedOrder]) -> [PatternSummary] {
        bucketSummaries(orders: orders) { order in
            var keys: [(id: String, label: String)] = []
            if order.shownMiles < 3 {
                keys.append(("dist-short", "Short (< 3 mi)"))
            } else if order.shownMiles <= 7 {
                keys.append(("dist-med", "Medium (3–7 mi)"))
            } else {
                keys.append(("dist-long", "Long (7+ mi)"))
            }

            switch order.orderType {
            case .food: keys.append(("type-food", "Food Delivery"))
            case .shop: keys.append(("type-shop", "Shop & Pay"))
            case .stack: keys.append(("type-stack", "Stacked (2+)"))
            }

            if order.payout < 8 {
                keys.append(("pay-low", "Small (< $8)"))
            } else if order.payout <= 15 {
                keys.append(("pay-mid", "Sweet Spot ($8–$15)"))
            } else {
                keys.append(("pay-high", "High Payout ($15+)"))
            }
            return keys
        }
    }

    static func dayPart(forHour hour: Int) -> (id: String, label: String) {
        switch hour {
        case 5..<10: return ("part-1-breakfast", "Breakfast (5–10a)")
        case 10..<14: return ("part-2-lunch", "Lunch (10a–2p)")
        case 14..<17: return ("part-3-afternoon", "Afternoon (2–5p)")
        case 17..<21: return ("part-4-dinner", "Dinner (5–9p)")
        default: return ("part-5-late", "Late Night (9p–5a)")
        }
    }

    /// Time-of-day buckets, best first.
    static func dayPartPatterns(orders: [LoggedOrder], calendar: Calendar = .current) -> [PatternSummary] {
        bucketSummaries(orders: orders) { order in
            [dayPart(forHour: calendar.component(.hour, from: order.timestamp))]
        }
    }

    /// Day-of-week buckets, best first.
    static func weekdayPatterns(orders: [LoggedOrder], calendar: Calendar = .current) -> [PatternSummary] {
        let names = calendar.weekdaySymbols
        return bucketSummaries(orders: orders) { order in
            let weekday = calendar.component(.weekday, from: order.timestamp)
            let label = names.indices.contains(weekday - 1) ? names[weekday - 1] : "Day \(weekday)"
            return [("weekday-\(weekday)", label)]
        }
    }
}
