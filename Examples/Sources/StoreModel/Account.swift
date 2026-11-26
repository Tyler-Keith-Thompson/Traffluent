import Events
import StoreEvents
import Trackers

/// A shopper's store account.
public struct Account: Hashable, Sendable {
    /// The plans an account can have.
    public enum Plan: String, CaseIterable, Hashable, Sendable {
        /// Free shipping on orders over $50.
        case basic
        /// Free express shipping on every order.
        case plus
    }

    /// The account's email address.
    public var email: String
    /// The account's plan.
    public var plan: Plan

    /// An account of `email`, on `plan`.
    ///
    /// - Parameters:
    ///   - email: The account's email address.
    ///   - plan: The account's plan.
    public init(email: String, plan: Plan) {
        self.email = email
        self.plan = plan
    }

    /// Signs a shopper up for `plan` with `email`, and tracks `SignedUp` through
    /// `Tracker.current`.
    ///
    /// The email address goes in the event as a `Sensitive` value: a destination reads it only
    /// through the record, and one given `redactingSensitiveValues()` never does.
    ///
    /// - Parameters:
    ///   - email: The shopper's email address.
    ///   - plan: The plan they chose.
    /// - Returns: The new account.
    public static func signUp(email: String, plan: Plan) -> Account {
        Tracker.current.track(SignedUp(plan: plan.rawValue, email: Sensitive(email), referrer: nil))
        return Account(email: email, plan: plan)
    }
}
