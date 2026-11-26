public import EventMacros

/// Someone signed up for `plan`, with their email address, and `referrer` if one sent them.
@Event(name: "signed_up", consent: .functional)
public struct SignedUp {
    /// The plan signed up for.
    public var plan: String
    /// The new account's email address, as a sensitive value. Optional, so a record a destination
    /// redacted still matches the tracking plan.
    public var email: Sensitive<String>?
    /// Who referred them, if anyone.
    public var referrer: String?

    /// The event for a sign-up to `plan`.
    ///
    /// - Parameters:
    ///   - plan: The plan signed up for.
    ///   - email: The new account's email address.
    ///   - referrer: Who referred them, if anyone.
    public init(plan: String, email: Sensitive<String>, referrer: String?) {
        self.plan = plan
        self.email = email
        self.referrer = referrer
    }
}
