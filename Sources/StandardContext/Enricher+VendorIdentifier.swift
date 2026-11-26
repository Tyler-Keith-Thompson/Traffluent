import Foundation
public import Events

extension Enricher {
    /// An enricher that sets every record's ``VendorIdentifierKey`` to the platform's identifier for
    /// vendor, where it has one.
    ///
    /// ```swift
    /// let tracker = Tracker(enrichers: [.sessions(), .vendorIdentifier()])
    /// ```
    ///
    /// Nothing carries the identifier until the app adds this enricher, and the app owns that
    /// decision, the user's consent to it included. The identifier is read once, from `UIDevice`
    /// or `WKInterfaceDevice` on the main actor, when this is called, and held in the enricher's
    /// memory only: neither the tracker nor its store writes it to disk (a store keeps no
    /// record's context). Where the system has none (macOS, Linux, a device not yet unlocked
    /// since it restarted) the enricher sets nothing; it never makes one up.
    ///
    /// - Returns: The enricher, which runs on the tracker's worker like any other.
    @MainActor
    public static func vendorIdentifier() -> Enricher {
        vendorIdentifier(VendorIdentifierKey.identifierForVendor)
    }

    /// An enricher that sets every record's ``VendorIdentifierKey`` to `identifier`, or sets
    /// nothing for `nil`.
    ///
    /// - Parameter identifier: The system's identifier for vendor.
    /// - Returns: The enricher.
    package static func vendorIdentifier(_ identifier: UUID?) -> Enricher {
        guard let identifier else {
            return Enricher { _ in }
        }
        let value = Sensitive(identifier)
        return Enricher { context in
            context[VendorIdentifierKey.self] = value
        }
    }
}
