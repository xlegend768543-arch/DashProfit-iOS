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

    // MARK: - Helpers

    private func makeOrder(
        merchant: String = "Chipotle",
        payout: Double = 12.0,
        miles: Double = 4.0,
        minutes: Int = 20,
        decision: OrderDecision = .take,
        timestamp: Date = Date(),
        isSample: Bool = false
    ) -> LoggedOrder {
        let eval = OfferCalculator.evaluate(
            payout: payout,
            miles: miles,
            minutes: minutes,
            deadheadMultiplier: 1.0,
            waitMinutes: 0,
            settings: DashSettings()
        )!
        return LoggedOrder(
            timestamp: timestamp,
            evaluation: eval,
            merchant: merchant,
            orderType: .food,
            deadheadMultiplier: 1.0,
            waitMinutes: 0,
            decision: decision,
            isSample: isSample
        )
    }

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DashProfitTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }

    // MARK: - Order construction

    func testOrderFromEvaluationDefaultsMerchantAndKeepsEstimatedMinutes() {
        let eval = OfferCalculator.evaluate(
            payout: 10, miles: 3, minutes: 18, deadheadMultiplier: 1.5, waitMinutes: 5, settings: DashSettings()
        )!
        let order = LoggedOrder(
            evaluation: eval, merchant: "   ", orderType: .shop,
            deadheadMultiplier: 1.5, waitMinutes: 5, decision: .pass
        )
        XCTAssertEqual(order.merchant, LoggedOrder.defaultMerchantName)
        XCTAssertEqual(order.effectiveMinutes, 23)
        XCTAssertEqual(order.estimatedMinutes, 18)
        XCTAssertEqual(order.netProfit, eval.netProfit, accuracy: 0.0001)
        XCTAssertFalse(order.isSample)
    }

    // MARK: - Merchant history

    func testMerchantHistoryNormalizesNamesAndSkipsSamples() {
        let orders = [
            makeOrder(merchant: "Target (6 items)", payout: 18, minutes: 30),
            makeOrder(merchant: "target", payout: 12, minutes: 30),
            makeOrder(merchant: "TARGET ", decision: .pass),
            makeOrder(merchant: "Target", payout: 500, isSample: true),
            makeOrder(merchant: "Chipotle")
        ]
        let h = OfferCalculator.merchantHistory(for: "  Target ", in: orders)
        XCTAssertEqual(h?.takenCount, 2)
        XCTAssertEqual(h?.passedCount, 1)
        let taken = orders.prefix(2)
        let expectedHourly = taken.reduce(0) { $0 + $1.netProfit } / 60.0 * 60.0
        XCTAssertEqual(h?.netHourly ?? -1, expectedHourly, accuracy: 0.0001)

        XCTAssertNil(OfferCalculator.merchantHistory(for: "", in: orders))
        XCTAssertNil(OfferCalculator.merchantHistory(for: "Popeyes", in: orders))
        XCTAssertNil(OfferCalculator.merchantHistory(for: LoggedOrder.defaultMerchantName,
                                                     in: [makeOrder(merchant: "")]))
    }

    func testMerchantHistoryWithOnlyPasses() {
        let h = OfferCalculator.merchantHistory(for: "Popeyes", in: [makeOrder(merchant: "Popeyes", decision: .pass)])
        XCTAssertEqual(h?.takenCount, 0)
        XCTAssertEqual(h?.passedCount, 1)
        XCTAssertEqual(h?.netHourly, 0)
    }

    // MARK: - Time patterns

    func testDayPartAndWeekdayPatterns() {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = Locale(identifier: "en_US_POSIX")
        cal.timeZone = TimeZone(identifier: "UTC")!
        // 2026-11-13 is a Friday; 2026-11-14 a Saturday.
        func date(_ day: Int, _ hour: Int) -> Date {
            cal.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour))!
        }
        let orders = [
            makeOrder(payout: 20, minutes: 20, timestamp: date(13, 12)), // Fri lunch, strong
            makeOrder(payout: 8, minutes: 30, timestamp: date(14, 18)),  // Sat dinner, weak
            makeOrder(payout: 9, minutes: 30, timestamp: date(14, 19)),  // Sat dinner, weak
            makeOrder(payout: 50, minutes: 10, timestamp: date(14, 23), isSample: true)
        ]

        let parts = OfferCalculator.dayPartPatterns(orders: orders, calendar: cal)
        XCTAssertEqual(parts.map(\.id), ["part-2-lunch", "part-4-dinner"])
        XCTAssertEqual(parts.last?.count, 2)

        let days = OfferCalculator.weekdayPatterns(orders: orders, calendar: cal)
        XCTAssertEqual(days.map(\.label), ["Friday", "Saturday"])

        XCTAssertEqual(OfferCalculator.dayPart(forHour: 3).id, "part-5-late")
        XCTAssertEqual(OfferCalculator.dayPart(forHour: 21).id, "part-5-late")
        XCTAssertEqual(OfferCalculator.dayPart(forHour: 5).id, "part-1-breakfast")
    }

    func testPatternsNeedTwoRealTakenOrders() {
        XCTAssertTrue(OfferCalculator.analyzePatterns(orders: [makeOrder()]).isEmpty)
        XCTAssertTrue(OfferCalculator.dayPartPatterns(orders: [makeOrder(), makeOrder(isSample: true)]).isEmpty)
        XCTAssertFalse(OfferCalculator.analyzePatterns(orders: [makeOrder(), makeOrder()]).isEmpty)
    }

    // MARK: - Data file safety

    func testBlobDecodesWhenKeysAreMissing() throws {
        let json = #"{"orders": [], "shifts": []}"#.data(using: .utf8)!
        let blob = try JSONDecoder().decode(PersistedStoreBlob.self, from: json)
        XCTAssertTrue(blob.expenses.isEmpty)
        XCTAssertTrue(blob.dailyMileage.isEmpty)
    }

    func testLoaderKeepsBackupOfGoodFile() throws {
        let dir = try makeTempDir()
        let url = dir.appendingPathComponent("store.json")
        let blob = PersistedStoreBlob(orders: [makeOrder()])
        try JSONEncoder().encode(blob).write(to: url)

        let result = StoreFileLoader.load(from: url)
        XCTAssertEqual(result.blob, blob)
        XCTAssertNil(result.message)
        XCTAssertTrue(FileManager.default.fileExists(atPath: StoreFileLoader.backupURL(for: url).path))
    }

    func testLoaderQuarantinesDamagedFileAndUsesBackup() throws {
        let dir = try makeTempDir()
        let url = dir.appendingPathComponent("store.json")
        let good = PersistedStoreBlob(orders: [makeOrder(merchant: "Good")])
        try JSONEncoder().encode(good).write(to: StoreFileLoader.backupURL(for: url))
        try Data("{ not json".utf8).write(to: url)

        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let result = StoreFileLoader.load(from: url, now: now)

        XCTAssertEqual(result.blob, good)
        XCTAssertNotNil(result.message)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        let quarantined = StoreFileLoader.quarantineURL(for: url, now: now)
        XCTAssertEqual(try Data(contentsOf: quarantined), Data("{ not json".utf8))
    }

    func testLoaderWithDamagedFileAndNoBackupStartsEmptyNotLegacy() throws {
        let dir = try makeTempDir()
        let url = dir.appendingPathComponent("store.json")
        try Data("garbage".utf8).write(to: url)

        let result = StoreFileLoader.load(from: url)
        XCTAssertEqual(result.blob, PersistedStoreBlob())
        XCTAssertNotNil(result.message)
    }

    func testLoaderWithNoFilesReturnsNil() throws {
        let dir = try makeTempDir()
        let result = StoreFileLoader.load(from: dir.appendingPathComponent("store.json"))
        XCTAssertNil(result.blob)
        XCTAssertNil(result.message)
    }

    func testStoreDoesNotOverwriteDamagedFile() throws {
        let dir = try makeTempDir()
        let url = dir.appendingPathComponent("store.json")
        try Data("garbage".utf8).write(to: url)

        let store = DashStore(storeURL: url, skipAutoSeed: true)
        XCTAssertNotNil(store.startupMessage)
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertTrue(names.contains { $0.contains("corrupt-") })
    }

    // MARK: - Backup & restore

    func testBackupRoundTripAndRestore() throws {
        let dir = try makeTempDir()
        let source = DashStore(storeURL: dir.appendingPathComponent("a.json"), skipAutoSeed: true)
        source.logOrder(
            evaluation: OfferCalculator.evaluate(payout: 15, miles: 4, minutes: 20, deadheadMultiplier: 1,
                                                 waitMinutes: 0, settings: source.settings)!,
            decision: .take, merchant: "Sushi", orderType: .food, deadheadMultiplier: 1, waitMinutes: 0
        )
        source.addExpense(amount: 3.5, category: .toll, note: "Bridge")

        let data = try source.makeBackup().encoded()
        let decoded = try DashBackup.decode(from: data)
        XCTAssertEqual(decoded.data.orders.map(\.merchant), ["Sushi"])
        XCTAssertEqual(decoded.data.expenses.count, 1)

        let targetURL = dir.appendingPathComponent("b.json")
        let target = DashStore(storeURL: targetURL, skipAutoSeed: true)
        target.restore(from: decoded)
        XCTAssertEqual(target.orders.map(\.merchant), ["Sushi"])
        XCTAssertEqual(target.expenses.first?.note, "Bridge")
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: targetURL.deletingPathExtension().appendingPathExtension("pre-restore.json").path))
    }

    func testBackupFromNewerVersionIsRejected() throws {
        var backup = DashBackup(exportedAt: Date(), settings: DashSettings(), data: PersistedStoreBlob())
        backup.version = DashBackup.currentVersion + 1
        XCTAssertThrowsError(try DashBackup.decode(from: try backup.encoded()))
    }

    // MARK: - Editing

    func testUpdateOrderRecalculatesAndKeepsIdentity() throws {
        let dir = try makeTempDir()
        let store = DashStore(storeURL: dir.appendingPathComponent("s.json"), skipAutoSeed: true)
        store.logOrder(
            evaluation: OfferCalculator.evaluate(payout: 10, miles: 4, minutes: 20, deadheadMultiplier: 1,
                                                 waitMinutes: 0, settings: store.settings)!,
            decision: .take, merchant: "Wendys", orderType: .food, deadheadMultiplier: 1, waitMinutes: 0
        )
        let original = store.orders[0]

        XCTAssertTrue(store.updateOrder(
            id: original.id, payout: 14, miles: 4, minutes: 20, deadheadMultiplier: 1,
            waitMinutes: 5, orderType: .stack, merchant: "Wendy's", decision: .pass
        ))
        let updated = store.orders[0]
        XCTAssertEqual(updated.id, original.id)
        XCTAssertEqual(updated.timestamp, original.timestamp)
        XCTAssertEqual(updated.payout, 14)
        XCTAssertEqual(updated.effectiveMinutes, 25)
        XCTAssertEqual(updated.estimatedMinutes, 20)
        XCTAssertEqual(updated.decision, .pass)
        XCTAssertEqual(updated.merchant, "Wendy's")
        XCTAssertGreaterThan(updated.netProfit, original.netProfit)

        XCTAssertFalse(store.updateOrder(
            id: original.id, payout: 0, miles: 4, minutes: 20, deadheadMultiplier: 1,
            waitMinutes: 0, orderType: .food, merchant: "", decision: .take
        ))
        XCTAssertEqual(store.orders[0], updated)
    }
}
