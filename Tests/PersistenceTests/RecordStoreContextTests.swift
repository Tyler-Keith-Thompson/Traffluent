import Destinations
import Events
import Foundation
import Instrumentation
import Persistence
import PropertyBased
import StandardContext
import Testing
import Trackers
import TraffluentTestSupport

#if canImport(GRDB)
import GRDB
#endif

// The context keys a store keeps beside a record, so a record recovered after a relaunch reaches
// destinations as it was tracked (TRAF-145): its sample rate, screen and standard context, besides
// its session (RecordStoreSessionTests). Run against each kind of store (StoreKind); a second
// store opened on a copy of the directory is the next launch.

@Suite("RecordStore: context", .timeLimit(.minutes(1)))
struct RecordStoreContextTests {
    struct Tapped: Event, Equatable {
        var number: Int
    }

    enum AccountKey: ServiceContextKey {
        typealias Value = String
    }

    @Test("A record a sampler kept at a rate is recovered on the next launch with that rate as its SampleRateKey", arguments: StoreKind.all)
    func recoveredWithSampleRate(kind: StoreKind) async throws {
        let path = StoreKind.temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let expected = try SampleRate(0.25)
        let tracker = Tracker(
            store: try kind.open(at: path, events: [Tapped.self]).store,
            samplers: [.events(of: Tapped.self, rate: expected)],
            samplingSeed: 7
        )
        for number in 0 ..< 40 {
            tracker.track(Tapped(number: number))
        }
        await tracker.finish()
        var keptNumbers: [Int] = []
        for await record in tracker.records {
            keptNumbers.append(try #require(record.event as? Tapped).number)
        }
        let copy = path + "-copy"
        defer { try? FileManager.default.removeItem(atPath: copy) }
        try FileManager.default.copyItem(atPath: path, toPath: copy)

        let recovered = try kind.open(at: copy, events: [Tapped.self]).store.takeRecoveredRecords()

        let actualNumbers = recovered.compactMap { ($0.event as? Tapped)?.number }
        let actual = recovered.map { $0.context[SampleRateKey.self] }
        #expect(!keptNumbers.isEmpty)
        #expect(keptNumbers.count < 40)
        #expect(actualNumbers == keptNumbers)
        #expect(actual == Array(repeating: expected, count: keptNumbers.count))
    }

    @Test("A tracker on the next launch delivers every recovered record, not sampled again, weighted by the rate it was kept at rather than its own samplers' rate or the product of the two", arguments: StoreKind.all)
    func recoveredKeepsItsRateThroughTheNextTracker(kind: StoreKind) async throws {
        let path = StoreKind.temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let expectedRate = try SampleRate(0.25)
        let laterRate = try SampleRate(0.5)
        let earlier = Tracker(store: try kind.open(at: path, events: [Tapped.self]).store, samplers: [.events(of: Tapped.self, rate: expectedRate)], samplingSeed: 7)
        for number in 0 ..< 40 {
            earlier.track(Tapped(number: number))
        }
        await earlier.finish()
        var expectedNumbers: [Int] = []
        for await record in earlier.records {
            expectedNumbers.append(try #require(record.event as? Tapped).number)
        }
        let copy = path + "-copy"
        defer { try? FileManager.default.removeItem(atPath: copy) }
        try FileManager.default.copyItem(atPath: path, toPath: copy)
        let sut = Tracker(store: try kind.open(at: copy, events: [Tapped.self]).store, samplers: [.events(of: Tapped.self, rate: laterRate)], samplingSeed: 7)
        let destination = InMemoryDestination.unbounded()

        sut.track(Tapped(number: 100))
        await sut.finish()
        try await sut.records.batch(strategy: .count(100)).deliver(to: destination).execute()

        let recovered = destination.records.filter { ($0.event as? Tapped).map { $0.number < 100 } ?? false }
        let actualNumbers = recovered.compactMap { ($0.event as? Tapped)?.number }
        let actualRates = recovered.map { $0.context[SampleRateKey.self] }
        #expect(!expectedNumbers.isEmpty)
        #expect(expectedNumbers.count < 40)
        #expect(actualNumbers == expectedNumbers)
        #expect(actualRates == Array(repeating: expectedRate, count: expectedNumbers.count))
    }

    @Test("A record is recovered with its session, sample rate, screen, app, device, operating system, locale and network, and nothing else", arguments: StoreKind.all)
    func recoveredWithEveryKeptKey(kind: StoreKind) throws {
        let path = StoreKind.temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let expectedSession = UUID(uuidString: "019A2B3C-4D5E-7F60-8172-839405A6B7C8")!
        let expectedRate = try SampleRate(0.1)
        let expectedScreen = "Checkout"
        let expectedApplication = ApplicationKey.Value(bundleIdentifier: "com.example.shop", version: "2.4.1", build: "418")
        let expectedDevice = DeviceKey.Value(model: "iPhone17,1", formFactor: .phone)
        let expectedSystem = OperatingSystemKey.Value(name: "iOS", version: "26.1.0")
        let expectedLocale = Locale(identifier: "fr_CA")
        let expectedNetwork = NetworkKey.Value.cellular
        var context = ServiceContext.topLevel
        context[SessionKey.self] = expectedSession
        context[SampleRateKey.self] = expectedRate
        context[ScreenKey.self] = expectedScreen
        context[ApplicationKey.self] = expectedApplication
        context[DeviceKey.self] = expectedDevice
        context[OperatingSystemKey.self] = expectedSystem
        context[LocaleKey.self] = expectedLocale
        context[NetworkKey.self] = expectedNetwork
        context[VendorIdentifierKey.self] = Sensitive(UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF")!)
        context[AccountKey.self] = "account-42"
        let store = try kind.open(at: path, events: [Tapped.self]).store
        _ = store.append(EventRecord(event: Tapped(number: 1), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil, context: context))
        let copy = path + "-copy"
        defer { try? FileManager.default.removeItem(atPath: copy) }
        try FileManager.default.copyItem(atPath: path, toPath: copy)

        let actual = try #require(try kind.open(at: copy, events: [Tapped.self]).store.takeRecoveredRecords().first)

        #expect(actual.context[SessionKey.self] == expectedSession)
        #expect(actual.context[SampleRateKey.self] == expectedRate)
        #expect(actual.context[ScreenKey.self] == expectedScreen)
        #expect(actual.context[ApplicationKey.self] == expectedApplication)
        #expect(actual.context[DeviceKey.self] == expectedDevice)
        #expect(actual.context[OperatingSystemKey.self] == expectedSystem)
        #expect(actual.context[LocaleKey.self] == expectedLocale)
        #expect(actual.context[NetworkKey.self] == expectedNetwork)
        #expect(actual.context[VendorIdentifierKey.self] == nil)
        #expect(actual.context[AccountKey.self] == nil)
        #expect(actual.context.count == 8)
    }

    @Test("A record whose context holds one kept key alone is recovered with that key and no other", arguments: StoreKind.all, ["sampleRate", "screen", "application", "device", "operatingSystem", "locale", "network"])
    func recoveredWithOneKey(kind: StoreKind, key: String) throws {
        let path = StoreKind.temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        var context = ServiceContext.topLevel
        switch key {
        case "sampleRate": context[SampleRateKey.self] = try SampleRate(0.5)
        case "screen": context[ScreenKey.self] = "Cart"
        case "application": context[ApplicationKey.self] = ApplicationKey.Value(bundleIdentifier: nil, version: "1.0", build: nil)
        case "device": context[DeviceKey.self] = DeviceKey.Value(model: "Mac15,3", formFactor: .mac)
        case "operatingSystem": context[OperatingSystemKey.self] = OperatingSystemKey.Value(name: "Linux", version: "6.12.0")
        case "locale": context[LocaleKey.self] = Locale(identifier: "de")
        default: context[NetworkKey.self] = .other
        }
        let expected = context
        let store = try kind.open(at: path, events: [Tapped.self]).store
        _ = store.append(EventRecord(event: Tapped(number: 1), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil, context: context))
        let copy = path + "-copy"
        defer { try? FileManager.default.removeItem(atPath: copy) }
        try FileManager.default.copyItem(atPath: path, toPath: copy)

        let actual = try #require(try kind.open(at: copy, events: [Tapped.self]).store.takeRecoveredRecords().first).context

        #expect(actual.count == 1)
        #expect(actual[SampleRateKey.self] == expected[SampleRateKey.self])
        #expect(actual[ScreenKey.self] == expected[ScreenKey.self])
        #expect(actual[ApplicationKey.self] == expected[ApplicationKey.self])
        #expect(actual[DeviceKey.self] == expected[DeviceKey.self])
        #expect(actual[OperatingSystemKey.self] == expected[OperatingSystemKey.self])
        #expect(actual[LocaleKey.self] == expected[LocaleKey.self])
        #expect(actual[NetworkKey.self] == expected[NetworkKey.self])
    }

    @Test("The bounds of each kept value come back as they were: rates 0, the smallest above 0, and 1, an empty screen, an app whose bundle says nothing", arguments: StoreKind.all)
    func boundaryValuesRoundTrip(kind: StoreKind) throws {
        let path = StoreKind.temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let expectedRates = try [SampleRate(0), SampleRate(.leastNonzeroMagnitude), SampleRate(1)]
        let expectedScreen = ""
        let expectedApplication = ApplicationKey.Value(bundleIdentifier: nil, version: nil, build: nil)
        let expectedDevice = DeviceKey.Value(model: "", formFactor: .vision)
        let expectedSystem = OperatingSystemKey.Value(name: "", version: "")
        let store = try kind.open(at: path, events: [Tapped.self]).store
        for (number, rate) in expectedRates.enumerated() {
            var context = ServiceContext.topLevel
            context[SampleRateKey.self] = rate
            context[ScreenKey.self] = expectedScreen
            context[ApplicationKey.self] = expectedApplication
            context[DeviceKey.self] = expectedDevice
            context[OperatingSystemKey.self] = expectedSystem
            _ = store.append(EventRecord(event: Tapped(number: number), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil, context: context))
        }
        let copy = path + "-copy"
        defer { try? FileManager.default.removeItem(atPath: copy) }
        try FileManager.default.copyItem(atPath: path, toPath: copy)

        let recovered = try kind.open(at: copy, events: [Tapped.self]).store.takeRecoveredRecords()

        let actualRates = recovered.map { $0.context[SampleRateKey.self] }
        #expect(actualRates == expectedRates)
        for record in recovered {
            #expect(record.context[ScreenKey.self] == expectedScreen)
            #expect(record.context[ApplicationKey.self] == expectedApplication)
            #expect(record.context[DeviceKey.self] == expectedDevice)
            #expect(record.context[OperatingSystemKey.self] == expectedSystem)
            #expect(record.context.count == 5)
        }
    }

    @Test("A record read back by its position, as for a batch a full destination buffer dropped, keeps its sample rate, screen and standard context", arguments: StoreKind.all)
    func readBackWithContext(kind: StoreKind) throws {
        let path = StoreKind.temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let expectedRate = try SampleRate(0.5)
        let expectedScreen = "Cart"
        let expectedNetwork = NetworkKey.Value.wifi
        var context = ServiceContext.topLevel
        context[SampleRateKey.self] = expectedRate
        context[ScreenKey.self] = expectedScreen
        context[NetworkKey.self] = expectedNetwork
        let store = try kind.open(at: path, events: [Tapped.self]).store
        let tag = try #require(store.append(EventRecord(event: Tapped(number: 1), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil, context: context)).deliveryTag)

        let readBack = tag.acknowledger.records(at: [tag.position])

        let actual = try #require(readBack.first)
        #expect(readBack.count == 1)
        #expect(actual.context[SampleRateKey.self] == expectedRate)
        #expect(actual.context[ScreenKey.self] == expectedScreen)
        #expect(actual.context[NetworkKey.self] == expectedNetwork)
    }

    @Test("A record's identifier for vendor is never written: a segment store's files, or a database store's database, -wal and -shm files and rows, hold the record's screen but not the identifier in any form", arguments: StoreKind.all)
    func vendorIdentifierNeverWritten(kind: StoreKind) async throws {
        let path = StoreKind.temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let identifier = UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF")!
        let screen = "VendorIdentifierCheckScreen"
        // What the store keeps: every file's raw bytes (a segment store's segments, a database
        // store's database and its -wal and -shm files), and, for a database store, every row's
        // payload too, as a page may hold a payload compressed or split where the raw scan
        // wouldn't find it whole.
        func stored() throws -> [[UInt8]] {
            let files = try FileManager.default.contentsOfDirectory(atPath: path).sorted().compactMap { name in
                FileManager.default.contents(atPath: path + "/" + name).map(Array.init)
            }
            switch kind {
            case .segments:
                return files
            #if canImport(GRDB)
            case .databaseQueue, .databasePool:
                // Scanned before the read below opens the database, which may checkpoint the WAL.
                // A pool is in WAL mode, so its -wal and -shm files are there; a queue's rollback
                // journal is gone once each transaction commits.
                let names = try FileManager.default.contentsOfDirectory(atPath: path)
                #expect(names.contains("records.sqlite"))
                if kind == .databasePool {
                    #expect(names.contains("records.sqlite-wal"))
                    #expect(names.contains("records.sqlite-shm"))
                }
                let database = try DatabaseQueue(path: path + "/records.sqlite")
                return try files + database.read { db in
                    try Data.fetchAll(db, sql: "SELECT payload FROM traffluentRecord").map(Array.init)
                }
            #endif
            }
        }
        let store = try kind.open(at: path, events: [Tapped.self]).store
        let tracker = Tracker(store: store, enrichers: [Enricher { context in
            context[VendorIdentifierKey.self] = Sensitive(identifier)
            context[ScreenKey.self] = screen
        }])
        tracker.track(Tapped(number: 1))
        tracker.track(Tapped(number: 2))
        await tracker.finish()
        store.synchronize()

        let actual = try stored()

        let forms = [
            Array(identifier.uuidString.utf8),
            Array(identifier.uuidString.lowercased().utf8),
            withUnsafeBytes(of: identifier.uuid) { Array($0) },
        ]
        let holdsScreen = actual.contains { $0.firstRange(of: Array(screen.utf8)) != nil }
        let holdsIdentifier = actual.contains { bytes in forms.contains { bytes.firstRange(of: $0) != nil } }
        #expect(store.pendingRecordCount == 2)
        #expect(holdsScreen)
        #expect(!holdsIdentifier)
    }

    @Test("Any mix of kept keys, each there or not, comes back on the next launch as it was stored", .tags(.randomized), arguments: StoreKind.all)
    func randomContextsRoundTrip(kind: StoreKind) async {
        await propertyCheck(count: 40, input: Gen.uint8().optional.array(of: 8 ... 8).array(of: 0 ... 6)) { picks in
            let path = StoreKind.temporaryPath()
            defer { try? FileManager.default.removeItem(atPath: path) }
            let formFactors = DeviceKey.Value.FormFactor.allCases
            let networks = NetworkKey.Value.allCases
            let locales = ["en_US", "fr_CA", "ja_JP", "zh_Hant_TW", "de"]
            let expected: [ServiceContext] = picks.map { pick in
                var context = ServiceContext.topLevel
                context[SessionKey.self] = pick[0].map { UUID(uuid: (0x01, 0x9A, 0, 0, 0, 0, 0x70, 0, 0x80, 0, 0, 0, 0, 0, 0, $0 % 4)) }
                context[SampleRateKey.self] = pick[1].flatMap { try? SampleRate(Double($0) / 255) }
                context[ScreenKey.self] = pick[2].map { "Screen\($0 % 5)" }
                context[ApplicationKey.self] = pick[3].map {
                    ApplicationKey.Value(bundleIdentifier: $0 & 1 == 0 ? nil : "com.example.shop", version: $0 & 2 == 0 ? nil : "2.4.\($0)", build: $0 & 4 == 0 ? nil : "\($0)")
                }
                context[DeviceKey.self] = pick[4].map { DeviceKey.Value(model: "iPhone17,\($0)", formFactor: formFactors[Int($0) % formFactors.count]) }
                context[OperatingSystemKey.self] = pick[5].map { OperatingSystemKey.Value(name: ["iOS", "macOS", "Linux"][Int($0) % 3], version: "26.\($0).0") }
                context[LocaleKey.self] = pick[6].map { Locale(identifier: locales[Int($0) % locales.count]) }
                context[NetworkKey.self] = pick[7].map { networks[Int($0) % networks.count] }
                return context
            }
            let store = try kind.open(at: path, events: [Tapped.self]).store
            for (number, context) in expected.enumerated() {
                _ = store.append(EventRecord(event: Tapped(number: number), timestamp: Date(timeIntervalSince1970: Double(number)), sourceLocation: nil, context: context))
            }
            let copy = path + "-copy"
            defer { try? FileManager.default.removeItem(atPath: copy) }
            try FileManager.default.copyItem(atPath: path, toPath: copy)

            let recovered = try kind.open(at: copy, events: [Tapped.self]).store.takeRecoveredRecords()

            let actualNumbers = recovered.compactMap { ($0.event as? Tapped)?.number }
            #expect(actualNumbers == Array(expected.indices))
            for (actual, expected) in zip(recovered.map(\.context), expected) {
                #expect(actual[SessionKey.self] == expected[SessionKey.self])
                #expect(actual[SampleRateKey.self] == expected[SampleRateKey.self])
                #expect(actual[ScreenKey.self] == expected[ScreenKey.self])
                #expect(actual[ApplicationKey.self] == expected[ApplicationKey.self])
                #expect(actual[DeviceKey.self] == expected[DeviceKey.self])
                #expect(actual[OperatingSystemKey.self] == expected[OperatingSystemKey.self])
                #expect(actual[LocaleKey.self] == expected[LocaleKey.self])
                #expect(actual[NetworkKey.self] == expected[NetworkKey.self])
                #expect(actual.count == expected.count)
            }
        }
    }
}

extension RecordStoreContextTests.Tapped: Codable {}
