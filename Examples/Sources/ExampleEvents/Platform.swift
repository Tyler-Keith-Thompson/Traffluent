#if os(iOS)
    import UIKit
#endif

/// The platform an example app runs on.
public enum Platform: String, Sendable, Equatable, CaseIterable {
    case iPhone
    case iPad
    case macCatalyst
    case mac
    case visionOS
    case watchOS
    case tvOS
    case linux
    case wasm
    case windows
    case android
    /// A platform none of the other cases names.
    case other

    /// The platform this process runs on.
    ///
    /// On iOS, the device's interface idiom tells an iPad from an iPhone, which is why this reads
    /// on the main actor.
    @MainActor
    public static var current: Platform {
        #if targetEnvironment(macCatalyst)
            .macCatalyst
        #elseif os(iOS)
            UIDevice.current.userInterfaceIdiom == .pad ? .iPad : .iPhone
        #elseif os(macOS)
            .mac
        #elseif os(visionOS)
            .visionOS
        #elseif os(watchOS)
            .watchOS
        #elseif os(tvOS)
            .tvOS
        #elseif os(Linux)
            .linux
        #elseif os(WASI)
            .wasm
        #elseif os(Windows)
            .windows
        #elseif os(Android)
            .android
        #else
            .other
        #endif
    }
}
