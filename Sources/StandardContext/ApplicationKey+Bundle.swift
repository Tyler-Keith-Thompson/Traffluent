public import Events
public import Foundation

extension ApplicationKey.Value {
    /// The app `bundle` describes, read from its Info.plist.
    ///
    /// - Parameter bundle: The bundle to read, such as an app extension's containing app.
    public init(bundle: Bundle) {
        self.init(
            bundleIdentifier: bundle.bundleIdentifier,
            version: bundle.infoDictionary?["CFBundleShortVersionString"] as? String,
            build: bundle.infoDictionary?["CFBundleVersion"] as? String
        )
    }

    /// The running app, as its main bundle describes it.
    ///
    /// On Linux a process usually has no Info.plist, so each value is `nil`: a server or tool
    /// passes its own to `Enricher.application(_:)`.
    public static var current: ApplicationKey.Value {
        ApplicationKey.Value(bundle: .main)
    }
}
