import XCTest
@testable import DashProfit

final class DashProfitTests: XCTestCase {
    func testVoiceParserCases() {
        let noPayout = VoiceInputService.parseSpokenOffer("4.2 miles 21 minutes")
        XCTAssertNil(noPayout.payout)
        XCTAssertEqual(noPayout.miles ?? -1, 4.2, accuracy: 0.001)
        XCTAssertEqual(noPayout.minutes, 21)

        let standard = VoiceInputService.parseSpokenOffer("$13.50, 4.2 miles, 21 minutes")
        XCTAssertEqual(standard.payout ?? -1, 13.50, accuracy: 0.001)
        XCTAssertEqual(standard.miles ?? -1, 4.2, accuracy: 0.001)
        XCTAssertEqual(standard.minutes, 21)

        let roundTrip = VoiceInputService.parseSpokenOffer("12 dollars 5 miles 20 min round trip")
        XCTAssertEqual(roundTrip.payout ?? -1, 12.0, accuracy: 0.001)
        XCTAssertEqual(roundTrip.miles ?? -1, 5.0, accuracy: 0.001)
        XCTAssertEqual(roundTrip.minutes, 20)
        XCTAssertEqual(roundTrip.deadhead, .roundTrip)

        let dollarsCents = VoiceInputService.parseSpokenOffer("13 dollars 50 cents 4 miles 20 minutes")
        XCTAssertEqual(dollarsCents.payout ?? -1, 13.50, accuracy: 0.001)
        XCTAssertEqual(dollarsCents.miles ?? -1, 4.0, accuracy: 0.001)
        XCTAssertEqual(dollarsCents.minutes, 20)

        let shopOutOfZone = VoiceInputService.parseSpokenOffer("$8.75 3.1 mi 15 min shop and deliver out of zone")
        XCTAssertEqual(shopOutOfZone.payout ?? -1, 8.75, accuracy: 0.001)
        XCTAssertEqual(shopOutOfZone.miles ?? -1, 3.1, accuracy: 0.001)
        XCTAssertEqual(shopOutOfZone.minutes, 15)
        XCTAssertEqual(shopOutOfZone.deadhead, .edge)
        XCTAssertEqual(shopOutOfZone.orderType, .shop)
    }

    func testZeroSettingsPreserved() {
        var s = DashSettings()
        s.wearPerMile = 0
        s.gasPrice = 0
        s.irsRate = 0
        s.minPayout = 0
        s.dailyGoal = 0
        s.incomeTaxSetAsidePct = 0
        s.mpg = 0

        let clean = s.sanitized
        XCTAssertEqual(clean.wearPerMile, 0.0)
        XCTAssertEqual(clean.gasPrice, 0.0)
        XCTAssertEqual(clean.irsRate, 0.0)
        XCTAssertEqual(clean.minPayout, 0.0)
        XCTAssertEqual(clean.dailyGoal, 0.0)
        XCTAssertEqual(clean.incomeTaxSetAsidePct, 0.0)
        XCTAssertEqual(clean.mpg, 1.0)
        XCTAssertEqual(clean.costPerMile, 0.0)

        XCTAssertEqual(DashSettings.number(from: "0", default: 10), 0.0)
        XCTAssertEqual(DashSettings.number(from: "", default: 10), 10.0)
    }

    func testDailySummaryNoDoubleCountingAndExcludesSample() {
        let now = Date()
        let dateKey = OfferCalculator.localDateKey(for: now)
        let real = LoggedOrder(
            id: UUID(),
            timestamp: now,
            merchant: "Chipotle",
            orderType: .food,
            deadheadMultiplier: 1.0,
            waitMinutes: 0,
            decision: .take,
            payout: 20.0,
            shownMiles: 5.0,
            effectiveMiles: 6.0,
            effectiveMinutes: 30,
            vehicleCost: 2.0,
            netProfit: 18.0,
            netHourly: 36.0,
            effectivePerMile: 3.33,
            taxDeduction: 4.2,
            score: 85,
            isSample: false
        )
        let sample = LoggedOrder(
            id: UUID(),
            timestamp: now,
            merchant: "Sample Pizza",
            orderType: .food,
            deadheadMultiplier: 1.0,
            waitMinutes: 0,
            decision: .take,
            payout: 200.0,
            shownMiles: 50.0,
            effectiveMiles: 50.0,
            effectiveMinutes: 60,
            vehicleCost: 12.0,
            netProfit: 188.0,
            netHourly: 188.0,
            effectivePerMile: 4.0,
            taxDeduction: 35.0,
            score: 99,
            isSample: true
        )

        let manual = [ManualMileEntry(miles: 2.0, kind: .quick)]
        let settings = DashSettings()

        let gpsDominant = OfferCalculator.dailySummary(
            orders: [real, sample],
            shifts: [],
            manualEntries: manual,
            savedGPSMiles: 10.0,
            settings: settings,
            dateKey: dateKey
        )
        XCTAssertEqual(gpsDominant.totalMiles, 12.0, accuracy: 0.001)
        XCTAssertEqual(gpsDominant.milesSource, "gps")
        XCTAssertEqual(gpsDominant.grossEarnings, 20.0, accuracy: 0.001)
        XCTAssertEqual(gpsDominant.ordersCount, 1)

        let tripDominant = OfferCalculator.dailySummary(
            orders: [real, sample],
            shifts: [],
            manualEntries: manual,
            savedGPSMiles: 3.0,
            settings: settings,
            dateKey: dateKey
        )
        XCTAssertEqual(tripDominant.totalMiles, 8.0, accuracy: 0.001)
        XCTAssertEqual(tripDominant.milesSource, "trips")
    }

    func testTaxSetAsideAndExpenses() {
        let est = OfferCalculator.computeTaxSetAside(
            grossEarnings: 100.0,
            taxDeduction: 40.0,
            otherExpenses: 10.0,
            incomeTaxSetAsidePct: 0.25
        )
        let expectedSE = 50.0 * 0.9235 * 0.153
        let expectedIncome = (50.0 - expectedSE / 2.0) * 0.25
        XCTAssertEqual(est.seBase, 50.0, accuracy: 0.0001)
        XCTAssertEqual(est.seTax, expectedSE, accuracy: 0.0001)
        XCTAssertEqual(est.incomeTax, expectedIncome, accuracy: 0.0001)
        XCTAssertEqual(est.setAside, expectedSE + expectedIncome, accuracy: 0.0001)
    }

    func testGpsSegmentFilter() {
        XCTAssertTrue(
            MileageTrackerService.isValidSegment(
                deltaMeters: 2500.0,
                deltaSeconds: 120.0,
                horizontalAccuracy: 20.0
            )
        )
        XCTAssertFalse(
            MileageTrackerService.isValidSegment(
                deltaMeters: 5000.0,
                deltaSeconds: 10.0,
                horizontalAccuracy: 20.0
            )
        )
    }

    func testCsvBuilders() {
        let now = Date()
        let dateKey = OfferCalculator.localDateKey(for: now)
        let realOrder = LoggedOrder(
            id: UUID(),
            timestamp: now,
            merchant: "Chipotle, Downtown",
            orderType: .food,
            deadheadMultiplier: 1.0,
            waitMinutes: 0,
            decision: .take,
            payout: 14.0,
            shownMiles: 4.0,
            effectiveMiles: 4.0,
            effectiveMinutes: 20,
            vehicleCost: 1.0,
            netProfit: 13.0,
            netHourly: 39.0,
            effectivePerMile: 3.5,
            taxDeduction: 2.8,
            score: 90,
            isSample: false
        )
        let sampleOrder = LoggedOrder(
            id: UUID(),
            timestamp: now,
            merchant: "Sample Burger",
            orderType: .food,
            deadheadMultiplier: 1.0,
            waitMinutes: 0,
            decision: .take,
            payout: 99.0,
            shownMiles: 20.0,
            effectiveMiles: 20.0,
            effectiveMinutes: 30,
            vehicleCost: 5.0,
            netProfit: 94.0,
            netHourly: 188.0,
            effectivePerMile: 4.95,
            taxDeduction: 14.0,
            score: 99,
            isSample: true
        )

        let expense = LoggedExpense(
            timestamp: now,
            amount: 5.50,
            category: .toll,
            note: "Bridge, Northbound"
        )
        let mileage = [
            dateKey: DailyMileageEntry(
                entries: [ManualMileEntry(timestamp: now, miles: 3.0, kind: .odometer)],
                gpsSavedMiles: 6.0,
                startOdometer: 1000.0,
                endOdometer: 1003.0
            )
        ]

        let ordersCSV = DashStore.buildOrdersCSV(orders: [realOrder, sampleOrder])
        XCTAssertTrue(ordersCSV.contains("IsSample"))
        XCTAssertTrue(ordersCSV.contains("\"Chipotle, Downtown\""))

        let expensesCSV = DashStore.buildExpensesCSV(expenses: [expense])
        XCTAssertTrue(expensesCSV.contains("Date,Category,Amount,Note"))
        XCTAssertTrue(expensesCSV.contains("\"Bridge, Northbound\""))

        let mileageCSV = DashStore.buildMileageLogCSV(
            orders: [realOrder, sampleOrder],
            shifts: [],
            dailyMileage: mileage,
            expenses: [expense],
            settings: DashSettings()
        )
        XCTAssertTrue(mileageCSV.contains("StartOdometer,EndOdometer,TripEstMiles,GPSMiles,ManualMiles,BusinessMiles"))
        // Sample order's 20 trip miles must be excluded; only realOrder (4.0), GPS (6.0), manual (3.0) -> BusinessMiles = 9.00
        XCTAssertTrue(mileageCSV.contains(",4.00,6.00,3.00,9.00,gps,"))
    }
}
