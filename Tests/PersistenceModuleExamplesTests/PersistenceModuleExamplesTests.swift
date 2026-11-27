// The example of the Persistence module's landing article
// (Sources/Persistence/Persistence.docc/Persistence.md), verbatim, so the article cannot drift from
// the code.

import CBOR
import Foundation
import SystemPackage
import Testing
import Traffluent

@Suite("Persistence module examples", .timeLimit(.minutes(1)))
struct PersistenceModuleExamplesTests {
    @Event(name: "signed_up")
    struct SignedUp {
        var plan: String
        var seats: Int = 1
    }

    @Test("Keeping records in a segment store")
    func segmentStore() async throws {
        let directory = FilePath(NSTemporaryDirectory()).appending("PersistenceModuleExamplesTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: directory.string) }
        let vendor = InMemoryDestination()

        let store = try SegmentStore(directory: directory, byteBound: 1024 * 1024)
        let tracker = Tracker(store: store)
        let delivery = tracker.records.batch().deliver(to: vendor)
        tracker.track(SignedUp(plan: "pro", seats: 3))

        await tracker.finish()
        try await delivery.execute()
        let expectedSeats = [3]
        let expectedPendingRecordCount = 0

        #expect(vendor.events(of: SignedUp.self).map(\.seats) == expectedSeats)
        #expect(store.pendingRecordCount == expectedPendingRecordCount)
    }

    @Test("A record written without seats reads the default")
    func seatsDefault() throws {
        let bytes = CBOR.map([.textString("plan"): .textString("pro")]).encode()
        let expectedSeats = 1

        let actual = try CBORDecoder().decode(SignedUp.self, from: bytes)

        #expect(actual.seats == expectedSeats)
    }
}
