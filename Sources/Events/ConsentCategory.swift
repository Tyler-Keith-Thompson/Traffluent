/// The purpose an event is collected for, which the user consents to or refuses: analytics,
/// advertising and the like.
///
/// Each event type names its category (``Event/consentCategory``), and a tracker given a consent
/// delivers, holds or drops each event by its category's status. Categories beyond the ones here
/// are declared as static members:
///
/// ```swift
/// extension ConsentCategory {
///     static let crashReports = ConsentCategory("crash-reports")
/// }
/// ```
public struct ConsentCategory: Sendable, Hashable, CustomStringConvertible {
    /// The category's name, which tells it apart from every other category.
    public let name: String

    /// The category called `name`.
    ///
    /// - Parameter name: The category's name; two categories with the same name are the same
    ///   category.
    public init(_ name: String) {
        self.name = name
    }

    /// The category's name.
    public var description: String {
        name
    }

    /// Measuring how the product is used: the category of every event that names no other.
    public static let analytics = ConsentCategory("analytics")
    /// Advertising: attribution, retargeting and ad measurement.
    public static let advertising = ConsentCategory("advertising")
    /// Features the user asked for that remember or report something, such as a chat widget.
    public static let functional = ConsentCategory("functional")
    /// Tailoring content or recommendations to the user.
    public static let personalization = ConsentCategory("personalization")
}
