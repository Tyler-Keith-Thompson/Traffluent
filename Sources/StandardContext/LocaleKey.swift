public import Foundation
public import Instrumentation

/// The `ServiceContext` key of the locale an event was tracked in, which `Enricher.locale(_:)` sets
/// on every record's context.
///
/// A destination reads its identifier, language and region from each record's context:
///
/// ```swift
/// let locale = record.context[LocaleKey.self]
/// locale?.identifier                  // "fr_CA"
/// locale?.language.languageCode       // fr
/// locale?.region                      // CA
/// ```
public enum LocaleKey: ServiceContextKey {
    /// The locale.
    public typealias Value = Locale
}
