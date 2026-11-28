public import Foundation
public import Events

extension Enricher {
    /// An enricher that sets every record's ``/Events/LocaleKey`` to `locale`.
    ///
    /// ```swift
    /// let tracker = Tracker(enrichers: [.locale()])
    /// ```
    ///
    /// The locale is read once, when this is called, never per event: a change of language
    /// relaunches an app, and a later change of region reaches records from the next launch on.
    ///
    /// - Parameter locale: The locale to stamp records with; by default the user's, `Locale.current`.
    /// - Returns: The enricher, which runs on the tracker's worker like any other.
    public static func locale(_ locale: Locale = .current) -> Enricher {
        Enricher { context in
            context[LocaleKey.self] = locale
        }
    }
}
