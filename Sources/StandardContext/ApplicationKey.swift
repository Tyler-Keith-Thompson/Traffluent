public import Foundation
public import Instrumentation

/// The `ServiceContext` key of the app an event was tracked in: its bundle identifier, version and
/// build, which `Enricher.application(_:)` sets on every record's context.
///
/// A destination reads it from each record's context:
///
/// ```swift
/// let version = record.context[ApplicationKey.self]?.version  // "2.4.1"
/// ```
public enum ApplicationKey: ServiceContextKey {
    /// An app's bundle identifier, version and build, each `nil` where its bundle doesn't say.
    public struct Value: Hashable, Sendable {
        /// The bundle's identifier (`CFBundleIdentifier`), such as `com.example.shop`.
        public var bundleIdentifier: String?
        /// The version users see (`CFBundleShortVersionString`), such as `2.4.1`.
        public var version: String?
        /// The build number (`CFBundleVersion`), such as `418`.
        public var build: String?

        /// An app with the given bundle identifier, version and build.
        ///
        /// - Parameters:
        ///   - bundleIdentifier: The app's bundle identifier.
        ///   - version: The version users see.
        ///   - build: The build number.
        public init(bundleIdentifier: String?, version: String?, build: String?) {
            self.bundleIdentifier = bundleIdentifier
            self.version = version
            self.build = build
        }

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
        public static var current: Value {
            Value(bundle: .main)
        }
    }
}
