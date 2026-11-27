// Named after Heap's own words: its server-side API reference sends a project "in an EU
// datacenter" to another host, and every other project to heapanalytics.com.
/// The data center a Heap project's data resides in, which decides the track endpoint its events
/// are posted to.
///
/// A project's data center is set when the project is made, and Heap's docs say to send a project
/// in the EU data center to its own host, not to `heapanalytics.com`.
public enum HeapRegion: Sendable, Hashable {
    /// Heap's default data center, in the United States: `https://heapanalytics.com`.
    case us
    /// Heap's EU data center: `https://c.eu.heap-api.com`.
    case eu
}
