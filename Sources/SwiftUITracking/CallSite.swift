#if canImport(SwiftUI)
import Events
import Trackers

/// Where a tracking modifier was applied, which the events it tracks record as their call site
/// rather than a line inside this module.
struct CallSite {
    let file: String
    let fileID: String
    let function: String
    let line: Int
    let column: Int
}

extension Tracker {
    /// Tracks `event` as if `track` were called at `callSite`.
    func track(_ event: some Event, from callSite: CallSite) {
        track(event, file: callSite.file, fileID: callSite.fileID, function: callSite.function, line: callSite.line, column: callSite.column)
    }
}
#endif
