// Named after Segment's own: its docs call the regions US (Oregon, the default) and EU (Dublin).
/// The region of a Segment workspace, which decides the batch endpoint its sources' events are
/// posted to.
///
/// A workspace's region is set when it is made. Segment rejects events sent to the other region's
/// endpoint, and an EU source's events sent to the US endpoint may be answered without an error
/// and never appear.
public enum SegmentRegion: Sendable, Hashable {
    /// Segment's default region, in Oregon: `https://api.segment.io`.
    case us
    /// Segment's EU region, in Dublin: `https://events.eu1.segmentapis.com`.
    case eu
}
