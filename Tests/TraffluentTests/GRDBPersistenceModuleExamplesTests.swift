// The example of the GRDBPersistence module's landing article
// (Sources/GRDBPersistence/GRDBPersistence.docc/GRDBPersistence.md), verbatim, so the article
// cannot drift from the code. GRDB builds on Apple platforms only.

#if canImport(GRDB)
    import EventMacros
    import Foundation
    import GRDB
    import GRDBPersistence
    import Testing
    import Traffluent

    @Suite("GRDBPersistence module examples", .timeLimit(.minutes(1)))
    struct GRDBPersistenceModuleExamplesTests {
        @Event
        struct SignedUp {
            var plan: String
        }

        @Test("Keeping records in the app's database")
        func databaseStore() async throws {
            let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("GRDBPersistenceModuleExamplesTests-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let databasePath = directory.appendingPathComponent("app.sqlite").path
            let vendor = InMemoryDestination()

            let database = try DatabaseQueue(path: databasePath)
            let store = try DatabaseStore(events: [SignedUp.self], database: database, table: "analyticsRecord")
            let tracker = Tracker(store: store)
            let delivery = tracker.records.batch().deliver(to: vendor)
            tracker.track(SignedUp(plan: "pro"))

            await tracker.finish()
            try await delivery.execute()
            let tableExists = try await database.read { try $0.tableExists("analyticsRecord") }
            let expectedPlans = ["pro"]
            let expectedPendingRecordCount = 0

            #expect(vendor.events(of: SignedUp.self).map(\.plan) == expectedPlans)
            #expect(tableExists)
            #expect(store.pendingRecordCount == expectedPendingRecordCount)
        }
    }
#endif
