public import Events
import Foundation

extension DeviceKey.Value {
    /// The device the app runs on, or `nil` off Apple platforms, where a server's machine is
    /// no user's device.
    ///
    /// The model comes from the kernel (`hw.machine`, or `hw.model` on a Mac), not from UIKit,
    /// so it reads from any thread.
    public static var current: DeviceKey.Value? {
        #if os(macOS) || targetEnvironment(macCatalyst)
        DeviceKey.Value(model: hardwareModel, formFactor: .mac)
        #elseif os(iOS)
        ProcessInfo.processInfo.isiOSAppOnMac
            ? DeviceKey.Value(model: hardwareModel, formFactor: .mac)
            : DeviceKey.Value(model: machine, formFactor: FormFactor(iOSModel: machine))
        #elseif os(tvOS)
        DeviceKey.Value(model: machine, formFactor: .tv)
        #elseif os(watchOS)
        DeviceKey.Value(model: machine, formFactor: .watch)
        #elseif os(visionOS)
        DeviceKey.Value(model: machine, formFactor: .vision)
        #else
        nil
        #endif
    }
}

extension DeviceKey.Value.FormFactor {
    /// The form factor of a device an iOS app runs on, from its model identifier: an iPad's starts
    /// `iPad` and an Apple Vision Pro's `RealityDevice` (an iPad app runs there); any other is a
    /// phone's.
    ///
    /// - Parameter model: The model identifier, such as `iPad16,3`.
    package init(iOSModel model: String) {
        if model.hasPrefix("iPad") {
            self = .pad
        } else if model.hasPrefix("RealityDevice") {
            self = .vision
        } else {
            self = .phone
        }
    }
}

#if canImport(Darwin)
import Darwin

extension DeviceKey.Value {
    /// The model identifier of the device (`hw.machine`, such as `iPhone17,1`), or in a simulator
    /// of the simulated device, where the kernel's is the Mac's processor (`arm64`).
    fileprivate static var machine: String {
        #if targetEnvironment(simulator)
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
            return simulated
        }
        #endif
        var system = utsname()
        uname(&system)
        return withUnsafeBytes(of: &system.machine) { bytes in
            String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        }
    }

    /// A Mac's model identifier (`hw.model`, such as `Mac15,3`); `hw.machine` on a Mac is its
    /// processor.
    fileprivate static var hardwareModel: String {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 else { return machine }
        var bytes = [UInt8](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &bytes, &size, nil, 0) == 0 else { return machine }
        return String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
    }
}
#endif
