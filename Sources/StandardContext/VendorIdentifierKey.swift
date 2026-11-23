public import Events
public import Foundation
public import Instrumentation
#if canImport(UIKit) && !os(watchOS)
import UIKit
#elseif os(watchOS)
import WatchKit
#endif

/// The `ServiceContext` key of the platform's identifier for vendor, which
/// `Enricher.vendorIdentifier()` sets on every record's context: the one identifier that outlives
/// a session that Traffluent offers, and only because the operating system owns it.
///
/// The system gives the same identifier to every app of one vendor on one device, and a new one
/// once all of them are removed. Traffluent reads it and never stores it, nor makes one up where
/// the system has none: on macOS and Linux, and on a device whose system hasn't one yet (just
/// restarted, still locked), records carry no key. It is a `Sensitive` value, so a destination
/// reads it only through the record it arrived in, and not at all once a delivery redacts it:
///
/// ```swift
/// let vendorID = record.context[VendorIdentifierKey.self].flatMap(record.reveal)  // a UUID
/// ```
public enum VendorIdentifierKey: ServiceContextKey {
    /// The identifier for vendor, sensitive.
    public typealias Value = Sensitive<UUID>
}

extension VendorIdentifierKey {
    /// The system's identifier for vendor: `UIDevice`'s on iOS, iPadOS, tvOS, visionOS and Mac
    /// Catalyst, `WKInterfaceDevice`'s on watchOS, and `nil` on macOS and Linux, which have none,
    /// or while the system hasn't one.
    @MainActor static var identifierForVendor: UUID? {
        #if canImport(UIKit) && !os(watchOS)
        UIDevice.current.identifierForVendor
        #elseif os(watchOS)
        WKInterfaceDevice.current().identifierForVendor
        #else
        nil
        #endif
    }
}
