/// A marketing campaign the catalog shows a banner for, with the coupon it gives.
public struct Promotion: Hashable, Sendable {
    /// The campaign's identifier, such as `spring-sale`: what its events name it by.
    public var campaign: String
    /// The banner's text.
    public var title: String
    /// The coupon code the banner puts in the cart.
    public var couponCode: String
    /// How much the coupon takes off the cart's total, in percent.
    public var percentOff: Int

    /// A promotion of `campaign`, whose banner reads `title` and gives `couponCode`.
    ///
    /// - Parameters:
    ///   - campaign: The campaign's identifier.
    ///   - title: The banner's text.
    ///   - couponCode: The coupon code the banner puts in the cart.
    ///   - percentOff: How much the coupon takes off the total, in percent.
    public init(campaign: String, title: String, couponCode: String, percentOff: Int) {
        self.campaign = campaign
        self.title = title
        self.couponCode = couponCode
        self.percentOff = percentOff
    }
}

extension Promotion {
    /// The promotion the catalog shows this season.
    public static let springSale = Promotion(campaign: "spring-sale", title: "Spring sale: 10% off everything", couponCode: "SPRING", percentOff: 10)
}
