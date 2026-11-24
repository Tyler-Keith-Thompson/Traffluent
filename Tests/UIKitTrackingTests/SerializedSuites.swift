// Every suite here shows windows in the test host's one scene, and some set its tracker, which
// every window in it inherits. Nested in one serialized suite, they run one at a time, so no
// suite's view reads another's tracker.
#if canImport(UIKit) && !os(watchOS)
import Testing

@Suite(.serialized)
enum SerializedSuites {}
#endif
