// Named after Customer.io's own: its docs call its data centers US and EU, and its keys carry
// them (`pk_us_`, `pk_eu_`).
/// The region of a Customer.io workspace, which decides the Pipelines API endpoint its events are
/// posted to.
///
/// A workspace's region is set when it is made, and its keys belong to that region's data center.
public enum CustomerIORegion: Sendable, Hashable {
    /// Customer.io's US data center: `https://cdp.customer.io`.
    case us
    /// Customer.io's EU data center: `https://cdp-eu.customer.io`.
    case eu
}
