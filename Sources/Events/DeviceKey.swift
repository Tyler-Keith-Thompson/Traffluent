public import Instrumentation

/// The `ServiceContext` key of the device an event was tracked on: its model and form factor, which
/// `Enricher.device(_:)` (module `StandardContext`) sets on every record's context.
///
/// A destination reads it from each record's context:
///
/// ```swift
/// let model = record.context[DeviceKey.self]?.model  // "iPhone17,1"
/// ```
///
/// A store keeps it beside its record, so a record recovered after a relaunch carries the device
/// it was tracked on.
public enum DeviceKey: ServiceContextKey {
    /// A device's model and form factor.
    public struct Value: Hashable, Sendable {
        /// The kind of device: what it is held, worn or set up as.
        public enum FormFactor: Hashable, Sendable, CaseIterable {
            /// An iPhone or iPod touch.
            case phone
            /// An iPad.
            case pad
            /// A Mac, running a Mac app, a Mac Catalyst app or an iPad app.
            case mac
            /// An Apple TV.
            case tv
            /// An Apple Watch.
            case watch
            /// An Apple Vision Pro.
            case vision
        }

        /// The model identifier, such as `iPhone17,1` or `Mac15,3`; in a simulator, the simulated
        /// device's.
        public var model: String
        /// The kind of device.
        public var formFactor: FormFactor

        /// A device of the given model and form factor.
        ///
        /// - Parameters:
        ///   - model: The model identifier.
        ///   - formFactor: The kind of device.
        public init(model: String, formFactor: FormFactor) {
            self.model = model
            self.formFactor = formFactor
        }
    }
}
