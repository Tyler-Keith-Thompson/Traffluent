// Named after Mixpanel's own data residency names: its docs and SDKs call them US (the default),
// EU and India (mixpanel-go's `EuResidency()` and `InResidency()`; the ingestion API's `api`,
// `api-eu` and `api-in` servers).
/// The data residency of a Mixpanel project, which decides the `/track` endpoint its events are
/// posted to.
///
/// A project's data residency is set when the project is made, and Mixpanel ingests nothing for a
/// project from another residency's endpoint.
public enum MixpanelRegion: Sendable, Hashable {
    /// Mixpanel's default data residency, in the United States: `https://api.mixpanel.com`.
    case us
    /// Mixpanel's EU data residency: `https://api-eu.mixpanel.com`.
    case eu
    /// Mixpanel's India data residency: `https://api-in.mixpanel.com`.
    case india
}
