public import Events

extension Enricher {
    /// An enricher that sets every record's ``ApplicationKey`` to `application`.
    ///
    /// ```swift
    /// let tracker = Tracker(enrichers: [.application()])
    /// ```
    ///
    /// The app's values are read once, when this is called, never per event: they can't change
    /// while the app runs.
    ///
    /// - Parameter application: The app to stamp records with; by default the running app, as its
    ///   main bundle describes it. A server or tool, whose process has no Info.plist, passes its own.
    /// - Returns: The enricher, which runs on the tracker's worker like any other.
    public static func application(_ application: ApplicationKey.Value = .current) -> Enricher {
        Enricher { context in
            context[ApplicationKey.self] = application
        }
    }
}
