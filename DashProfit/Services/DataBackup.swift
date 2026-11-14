import Foundation

/// On-disk shape of the app's data file. Missing keys decode as empty so that
/// a file written by an older version never counts as "damaged".
struct PersistedStoreBlob: Codable, Equatable {
    var orders: [LoggedOrder] = []
    var shifts: [LoggedShift] = []
    var dailyMileage: [String: DailyMileageEntry] = [:]
    var expenses: [LoggedExpense] = []

    init(
        orders: [LoggedOrder] = [],
        shifts: [LoggedShift] = [],
        dailyMileage: [String: DailyMileageEntry] = [:],
        expenses: [LoggedExpense] = []
    ) {
        self.orders = orders
        self.shifts = shifts
        self.dailyMileage = dailyMileage
        self.expenses = expenses
    }

    private enum CodingKeys: String, CodingKey {
        case orders, shifts, dailyMileage, expenses
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        orders = try c.decodeIfPresent([LoggedOrder].self, forKey: .orders) ?? []
        shifts = try c.decodeIfPresent([LoggedShift].self, forKey: .shifts) ?? []
        dailyMileage = try c.decodeIfPresent([String: DailyMileageEntry].self, forKey: .dailyMileage) ?? [:]
        expenses = try c.decodeIfPresent([LoggedExpense].self, forKey: .expenses) ?? []
    }
}

/// Loads the data file without ever throwing data away:
/// - a readable file is copied to `<name>.bak.json` (last good copy);
/// - an unreadable file is moved aside to `<name>.corrupt-<timestamp>.json`
///   and the last good copy is used instead.
enum StoreFileLoader {
    struct Result {
        /// nil only when there is no data file at all (first launch / legacy migration).
        var blob: PersistedStoreBlob?
        /// Something the user should be told about, if anything.
        var message: String?
    }

    static func backupURL(for url: URL) -> URL {
        url.deletingPathExtension().appendingPathExtension("bak.json")
    }

    static func quarantineURL(for url: URL, now: Date) -> URL {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        return url.deletingPathExtension().appendingPathExtension("corrupt-\(f.string(from: now)).json")
    }

    static func decode(_ data: Data) -> PersistedStoreBlob? {
        try? JSONDecoder().decode(PersistedStoreBlob.self, from: data)
    }

    static func load(from url: URL, fileManager: FileManager = .default, now: Date = Date()) -> Result {
        let backup = backupURL(for: url)
        let backupBlob = (try? Data(contentsOf: backup)).flatMap(decode)

        guard fileManager.fileExists(atPath: url.path) else {
            if let backupBlob {
                return Result(blob: backupBlob, message: "Your data file was missing, so DashProfit restored the last good copy.")
            }
            return Result(blob: nil, message: nil)
        }

        if let data = try? Data(contentsOf: url), let blob = decode(data) {
            try? data.write(to: backup, options: .atomic)
            return Result(blob: blob, message: nil)
        }

        // Damaged: keep the bytes, never overwrite them.
        let quarantine = quarantineURL(for: url, now: now)
        let kept = (try? fileManager.moveItem(at: url, to: quarantine)) != nil
        let keptNote = kept ? " The damaged file was kept as \(quarantine.lastPathComponent)." : ""

        if let backupBlob {
            return Result(
                blob: backupBlob,
                message: "Your data file couldn't be read, so DashProfit restored the last good copy from your previous launch.\(keptNote)"
            )
        }
        return Result(
            blob: PersistedStoreBlob(),
            message: "Your data file couldn't be read and no backup copy was found. Starting empty.\(keptNote) Restore a backup from Rules & Car if you have one."
        )
    }
}

/// A full, portable backup (data + settings) that can be saved to Files / iCloud Drive.
struct DashBackup: Codable, Equatable {
    static let currentVersion = 1

    var version: Int = currentVersion
    var exportedAt: Date
    var settings: DashSettings
    var data: PersistedStoreBlob

    static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }

    static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    func encoded() throws -> Data {
        try Self.encoder().encode(self)
    }

    static func decode(from data: Data) throws -> DashBackup {
        let backup = try decoder().decode(DashBackup.self, from: data)
        guard backup.version <= currentVersion else {
            throw CocoaError(.fileReadCorruptFile, userInfo: [
                NSLocalizedDescriptionKey: "This backup was made by a newer version of DashProfit."
            ])
        }
        return backup
    }

    var suggestedFilename: String {
        "DashProfit-Backup-\(OfferCalculator.localDateKey(for: exportedAt))"
    }

    var summaryText: String {
        let realOrders = data.orders.filter { !$0.isSample }.count
        return "\(realOrders) orders, \(data.shifts.count) GPS shifts, \(data.expenses.count) expenses, \(data.dailyMileage.count) mileage days"
    }
}

#if canImport(SwiftUI)
import SwiftUI
import UniformTypeIdentifiers

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let contents = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        data = contents
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
#endif
