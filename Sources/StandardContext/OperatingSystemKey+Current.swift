public import Events
import Foundation

extension OperatingSystemKey.Value {
    /// The system the app runs on, its version as `ProcessInfo` reports it.
    ///
    /// A Mac Catalyst app, or an iPad app on a Mac, runs on `macOS`, at the Mac's version. On
    /// Linux the version is the kernel's.
    public static var current: OperatingSystemKey.Value {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return OperatingSystemKey.Value(name: name, version: "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)")
    }

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
