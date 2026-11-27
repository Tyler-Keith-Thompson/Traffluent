// The example of the "Persisting Records" article
// (Sources/Traffluent/Traffluent.docc/PersistingRecords.md), verbatim, so the article cannot drift
// from the code.

import Foundation
import SystemPackage
import Testing
import Traffluent

@Suite("Persisting records examples", .timeLimit(.minutes(1)))
struct PersistingRecordsExamplesTests {
    @Event(name: "signed_up")
    struct SignedUp {
        var plan: String
    }

    @Test("Persistence")
    func persistence() async throws {
        // The article's store uses the default directory; this one uses a scratch directory so the
        // test leaves nothing behind.
        let directory = FilePath(NSTemporaryDirectory()).appending("PersistingRecordsExamplesTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: directory.string) }
        let store = try SegmentStore(directory: directory)
        let tracker = Tracker(store: store)
        let delivery = tracker.records.batch().deliver(to: ConsoleDestination())
        tracker.track(SignedUp(plan: "pro"))
        await tracker.finish()
        try await delivery.execute()  // prints: SignedUp SignedUp(plan: "pro")
    }
}
