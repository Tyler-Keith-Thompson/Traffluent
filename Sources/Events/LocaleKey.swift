public import Foundation
public import Instrumentation

/// The `ServiceContext` key of the locale an event was tracked in, which `Enricher.locale(_:)`
/// (module `StandardContext`) sets on every record's context.
///
/// A destination reads its identifier, language and region from each record's context:
///
/// ```swift
/// let locale = record.context[LocaleKey.self]
/// locale?.identifier                  // "fr_CA"
/// locale?.language.languageCode       // fr
/// locale?.region                      // CA
/// ```
///
/// A store keeps the locale's identifier beside its record, so a record recovered after a relaunch
/// carries `Locale(identifier:)` of the identifier it was tracked with. A preference the
/// identifier doesn't spell, such as a first weekday the user picked in Settings, isn't kept.
public enum LocaleKey: ServiceContextKey {
    /// The locale.
    public typealias Value = Locale
}
