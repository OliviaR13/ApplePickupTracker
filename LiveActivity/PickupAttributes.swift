import ActivityKit
import Foundation

struct PickupAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var status: PickupStatus
        var lastUpdated: Date
        var storeName: String
    }
    var orderNumber: String
    var productName: String
}
