import Foundation
#if canImport(ActivityKit)
import ActivityKit

struct DashShiftActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var milesToday: Double
        var taxWriteOff: Double
        var netProfit: Double
        var elapsedSeconds: Int
    }

    var irsRate: Double
}
#endif
