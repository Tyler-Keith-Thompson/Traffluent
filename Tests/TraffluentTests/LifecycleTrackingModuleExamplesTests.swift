// The example of LifecycleTracking's landing article
// (Sources/LifecycleTracking/LifecycleTracking.docc/LifecycleTracking.md), verbatim, so the article
// cannot drift from the code.

import Testing
import Traffluent

@Suite("LifecycleTracking module examples", .timeLimit(.minutes(1)))
struct LifecycleTrackingModuleExamplesTests {
    @Test("Overview")
    func overview() async {
        let tracker = Tracker()
        let lifecycle = tracker.trackLifecycle(version: "2.1", versionStore: InMemoryVersionStore(version: "2.0"))
        // tracks ApplicationUpdated(previousVersion: "2.0", version: "2.1"), then ApplicationOpened(fromBackground: false)

        // ... the process's work ...

        await lifecycle.finish()  // tracks ApplicationTerminated
        await tracker.finish()
        var actual: [String] = []
        for await record in tracker.records {
            actual.append(type(of: record.event).name)
        }
        let expected = ["ApplicationUpdated", "ApplicationOpened", "ApplicationTerminated"]

        #expect(actual == expected)
    }
}
