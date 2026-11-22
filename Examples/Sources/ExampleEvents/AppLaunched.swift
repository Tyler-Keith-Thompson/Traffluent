public import Events

/// The example app started, on `platform`.
public struct AppLaunched: Event, Equatable {
    /// Where the app runs.
    public var platform: Platform

    /// The event for an app starting on `platform`.
    ///
    /// - Parameter platform: Where the app runs.
    public init(platform: Platform) {
        self.platform = platform
    }
}
