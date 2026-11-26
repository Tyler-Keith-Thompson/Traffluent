public import EventMacros

/// Someone tapped the banner of the promotion `campaign`.
///
/// It measures a marketing campaign, so it is collected for advertising: the tracker delivers it
/// only once the shopper allows marketing, holds it while they haven't decided, and drops it when
/// they refuse.
@Event(name: "promotion_tapped", consent: .advertising)
public struct PromotionTapped: Equatable {
    /// The promotion's campaign, such as `spring-sale`.
    public var campaign: String

    /// The event for a tap on the banner of `campaign`.
    ///
    /// - Parameter campaign: The promotion's campaign.
    public init(campaign: String) {
        self.campaign = campaign
    }
}
