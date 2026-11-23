import Foundation
public import Instrumentation

/// The `ServiceContext` key of the operating system an event was tracked on: its name and version,
/// which `Enricher.operatingSystem(_:)` sets on every record's context.
///
/// A destination reads it from each record's context:
///
/// ```swift
/// let system = record.context[OperatingSystemKey.self]  // iOS 26.1.0
/// ```
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

        /// The system the app runs on, its version as `ProcessInfo` reports it.
        ///
        /// A Mac Catalyst app, or an iPad app on a Mac, runs on `macOS`, at the Mac's version. On
        /// Linux the version is the kernel's.
        public static var current: Value {
            let version = ProcessInfo.processInfo.operatingSystemVersion
            return Value(name: name, version: "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)")
        }
    }
}

extension OperatingSystemKey.Value {
    /// The name of the system this build runs on.
    fileprivate static var name: String {
        #if os(macOS) || targetEnvironment(macCatalyst)
        "macOS"
        #elseif os(iOS)
        ProcessInfo.processInfo.isiOSAppOnMac ? "macOS" : "iOS"
        #elseif os(tvOS)
        "tvOS"
        #elseif os(watchOS)
        "watchOS"
        #elseif os(visionOS)
        "visionOS"
        #else
        "Linux"
        #endif
    }
}
