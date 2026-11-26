public import EventMacros
public import Foundation

/// An order was placed.
@Event(name: "order_completed")
public struct OrderCompleted: Equatable {
    /// The order's identifier.
    public var orderID: UUID
    /// What the order cost.
    public var total: Double
    /// How many items it holds.
    public var itemCount: UInt16
    /// The items' names.
    public var items: [String]
    /// When it was placed.
    public var completedAt: Date
    /// Whether it ships express.
    public var express: Bool

    /// The event for the order `orderID`.
    ///
    /// - Parameters:
    ///   - orderID: The order's identifier.
    ///   - total: What the order cost.
    ///   - itemCount: How many items it holds.
    ///   - items: The items' names.
    ///   - completedAt: When it was placed.
    ///   - express: Whether it ships express.
    public init(orderID: UUID, total: Double, itemCount: UInt16, items: [String], completedAt: Date, express: Bool) {
        self.orderID = orderID
        self.total = total
        self.itemCount = itemCount
        self.items = items
        self.completedAt = completedAt
        self.express = express
    }
}
