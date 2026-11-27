public import Foundation

/// Why a tracking plan couldn't be written as an Iglu registry
/// (``TrackingPlan/igluFiles(vendor:registry:carryingForward:)``,
/// ``TrackingPlan/writeIgluRegistry(to:vendor:registry:)``).
public enum IgluExportError: Error, Sendable, Hashable {
    /// The vendor isn't one Iglu takes in reverse domain notation: labels of ASCII letters,
    /// digits, `-` and `_`, joined by `.`, none of them empty (`com.acme`).
    case invalidVendor
    /// An event's schema has no Iglu name: its name holds a character other than an ASCII letter,
    /// digit, `-` or `_` (a space, a `.`, a letter outside ASCII), or its version is below 1, which
    /// no SchemaVer has. Rename the event with `@Event(name:)`, raising its version, to export it.
    case invalidSchemaKey(event: String, version: Int)
    /// A property of the event is constrained by more than one pattern, which its schema writes as
    /// `allOf`, a keyword Snowplow's validation doesn't support. Constrain the property with one
    /// pattern.
    case allOf(event: String, version: Int)
    /// The event differs from the newest schema of its version the registry holds in a way a
    /// payload that schema accepts may fail: a property added as required, retyped or made
    /// required, a default value removed, a constraint tightened (``TrackingPlanDifference/isBreaking``).
    /// Iglu publishes a breaking change only as a new MODEL: raise the event's version.
    case breakingChange(event: String, version: Int)
    /// The event changed compatibly at a version the registry already holds, which a static
    /// repository can't publish: it doesn't supersede, so events naming `N-0-0` would be validated
    /// against `N-0-0` alone and fail on what changed. Raise the event's version, or publish to
    /// Iglu Server (``IgluRegistry/server``).
    case additionNeedsNewVersion(event: String, version: Int)
    /// A file of the registry couldn't be read, written, or its directory made, or one already
    /// there isn't a schema the plan wrote (`CocoaError.fileReadCorruptFile`, its path in the
    /// error's `filePath`). Nothing is rewritten; files written before it stay.
    case fileSystem(CocoaError)
}
