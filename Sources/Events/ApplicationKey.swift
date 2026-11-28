public import Instrumentation

/// The `ServiceContext` key of the app an event was tracked in: its bundle identifier, version and
/// build, which `Enricher.application(_:)` (module `StandardContext`) sets on every record's
/// context.
///
/// A destination reads it from each record's context:
///
/// ```swift
/// let version = record.context[ApplicationKey.self]?.version  // "2.4.1"
/// ```
///
/// A store keeps it beside its record, so a record recovered after a relaunch carries the app it
/// was tracked in, not the one that delivers it.
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
    }
}
