public import Instrumentation

/// The `ServiceContext` key of the operating system an event was tracked on: its name and version,
/// which `Enricher.operatingSystem(_:)` (module `StandardContext`) sets on every record's context.
///
/// A destination reads it from each record's context:
///
/// ```swift
/// let system = record.context[OperatingSystemKey.self]  // iOS 26.1.0
/// ```
///
/// A store keeps it beside its record, so a record recovered after a relaunch carries the system
/// version it was tracked on, not the one after an update.
public enum OperatingSystemKey: ServiceContextKey {
    /// An operating system's name and version.
    public struct Value: Hashable, Sendable {
        /// The system's name: `macOS`, `iOS`, `tvOS`, `watchOS`, `visionOS` or `Linux`.
        public var name: String
        /// The system's version, major, minor and patch, such as `26.1.0`.
        public var version: String

        /// An operating system of the given name and version.
        ///
        /// - Parameters:
        ///   - name: The system's name.
        ///   - version: The system's version.
        public init(name: String, version: String) {
            self.name = name
            self.version = version
        }
    }
}
