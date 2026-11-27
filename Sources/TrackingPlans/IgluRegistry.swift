/// The kind of Iglu registry a tracking plan's schemas are published to, which decides whether a
/// compatible change can be published at the same event version
/// (``TrackingPlan/igluFiles(vendor:registry:carryingForward:)``).
///
/// An event names SchemaVer `N-0-0` of its schema whatever changes at version N. Iglu Server
/// records that a later `N-0-k` supersedes it, so Snowplow validates the event against the newest
/// one; a static repository has no such record, so an event naming `N-0-0` is validated against
/// `N-0-0` alone, and a property added in `N-0-1` fails it.
public enum IgluRegistry: Sendable, Hashable {
    /// Iglu Server 0.11.0 or later, with Snowplow's Enrich 3.8.0 or later: a compatible change at
    /// version N is written as the next addition, `N-0-(k+1)`, listing the earlier ones in
    /// `$supersedes`.
    case server
    /// A static repository, files served over HTTP: it doesn't supersede, so a change at version N
    /// is refused with ``IgluExportError/additionNeedsNewVersion(event:version:)``, and the event
    /// needs a new version instead.
    case staticRepository
}
