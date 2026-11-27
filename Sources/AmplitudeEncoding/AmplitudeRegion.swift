// Named after the server zones of Amplitude's own SDKs (`ServerZone.US`, `ServerZone.EU`).
/// The data center an Amplitude project's data resides in, which decides the HTTP V2 endpoint its
/// events are posted to.
///
/// A project's data residency is set when the project is made, and an event posted to the other
/// data center's endpoint doesn't reach it.
public enum AmplitudeRegion: Sendable, Hashable {
    /// Amplitude's default data center, in the United States: `https://api2.amplitude.com`.
    case us
    /// Amplitude's EU data center: `https://api.eu.amplitude.com`.
    case eu
}
