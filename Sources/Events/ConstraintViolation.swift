/// A property of an event whose value breaks one of the constraints declared on it: the
/// property's name and the keyword it breaks.
///
/// An event returns the first it finds from ``Event/constraintViolation()``, and a tracker rejects
/// the event, reporting it.
public struct ConstraintViolation: Sendable, Hashable, CustomStringConvertible {
    /// The property's name, as the event's schema lists it.
    public var property: String
    /// The keyword its value breaks.
    public var keyword: ValidationKeyword

    /// The violation of `keyword` by `property`.
    ///
    /// - Parameters:
    ///   - property: The property's name.
    ///   - keyword: The keyword its value breaks.
    public init(property: String, keyword: ValidationKeyword) {
        self.property = property
        self.keyword = keyword
    }

    /// `"<property>" breaks <keyword>`.
    public var description: String {
        "\"\(property)\" breaks \(keyword)"
    }
}
