public import Foundation

/// An order a shopper placed: what their cart held when they did.
public struct Order: Identifiable, Hashable, Sendable {
    /// The order's identifier.
    public var id: UUID
    /// The cart's lines.
    public var lines: [Cart.Line]
    /// What the order cost, in cents, after any discount.
    public var totalInCents: Int
    /// Whether it ships express.
    public var expressShipping: Bool
    /// When it was placed.
    public var placedAt: Date

    /// The order `id` of `lines`, costing `totalInCents`, placed at `placedAt`.
    ///
    /// - Parameters:
    ///   - id: The order's identifier.
    ///   - lines: The cart's lines.
    ///   - totalInCents: What the order cost, in cents, after any discount.
    ///   - expressShipping: Whether it ships express.
    ///   - placedAt: When it was placed.
    public init(id: UUID, lines: [Cart.Line], totalInCents: Int, expressShipping: Bool, placedAt: Date) {
        self.id = id
        self.lines = lines
        self.totalInCents = totalInCents
        self.expressShipping = expressShipping
        self.placedAt = placedAt
    }
}
