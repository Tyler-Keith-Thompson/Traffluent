import Events
import Foundation
import Persistence
import StandardContext
import SystemPackage
import Testing
import Trackers

@Suite("StandardContext: the identifier for vendor", .timeLimit(.minutes(1)))
struct VendorIdentifierEnricherTests {
    struct Tapped: Event, BinaryCodable {
        var number: Int

        init(number: Int) {
            self.number = number
        }

        func encode(to encoder: inout BinaryEncoder) {
            encoder.encodeMap { map in
                map.encode(number, forKey: "number")
            }
        }

        init(from decoder: inout BinaryDecoder) throws(BinaryDecodingError) {
            var map = try decoder.decodeMap()
            number = try map.decode(forKey: "number")
        }
    }

    @Test("The vendor identifier enricher sets VendorIdentifierKey to the system's identifier, which the record reveals")
    func setsTheIdentifier() async throws {
        let expected = try #require(UUID(uuidString: "6F1C2A7E-3B9D-4C55-9E21-0A4B7C8D9E10"))
        let sut = Tracker(enrichers: [.vendorIdentifier(expected)])

        sut.track(Tapped(number: 1))
        sut.track(Tapped(number: 2))
        await sut.finish()

        var actual: [UUID?] = []
        for await record in sut.records {
            actual.append(record.context[VendorIdentifierKey.self].flatMap(record.reveal))
        }
        #expect(actual == [expected, expected])
    }

    @Test("Without the vendor identifier enricher, no record carries the key, whatever other standard enrichers it has")
    func absentUnlessAdded() async throws {
        let sut = Tracker(enrichers: [
            .application(ApplicationKey.Value(bundleIdentifier: "com.example.shop", version: "2.4.1", build: "418")),
            .device(DeviceKey.Value(model: "iPhone17,1", formFactor: .phone)),
            .operatingSystem(OperatingSystemKey.Value(name: "iOS", version: "26.1.0")),
            .locale(Locale(identifier: "fr_CA")),
            .network { .wifi },
        ])

        sut.track(Tapped(number: 1))
        await sut.finish()

        var records = sut.records.makeAsyncIterator()
        let record = try #require(await records.next())
        #expect(record.context[VendorIdentifierKey.self] == nil)
    }

    @Test("Where the system has no identifier yet, the enricher sets nothing rather than making one up")
    func noIdentifierNoKey() async throws {
        let sut = Tracker(enrichers: [.vendorIdentifier(nil)])

        sut.track(Tapped(number: 1))
        await sut.finish()

        var records = sut.records.makeAsyncIterator()
        let record = try #require(await records.next())
        #expect(record.context[VendorIdentifierKey.self] == nil)
    }

    #if os(macOS) || os(Linux)
    @Test("On macOS and Linux, which have no identifier for vendor, the platform's enricher sets nothing")
    @MainActor
    func absentOnMacOSAndLinux() async throws {
        let sut = Tracker(enrichers: [.vendorIdentifier()])

        sut.track(Tapped(number: 1))
        await sut.finish()

        var records = sut.records.makeAsyncIterator()
        let record = try #require(await records.next())
        #expect(record.context[VendorIdentifierKey.self] == nil)
    }
    #endif

    @Test("Nothing writes the identifier to disk: a store's directory holds the same files as without it, none holding the identifier")
    func nothingWritten() async throws {
        let identifier = try #require(UUID(uuidString: "6F1C2A7E-3B9D-4C55-9E21-0A4B7C8D9E10"))
        let root = FileManager.default.temporaryDirectory.appending(path: "StandardContext-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let withIdentifier = root.appending(path: "with")
        let without = root.appending(path: "without")
        let events: [any (Event & BinaryCodable).Type] = [Tapped.self]
        let store = try SegmentStore(events: events, directory: FilePath(withIdentifier.path(percentEncoded: false)))
        let controlStore = try SegmentStore(events: events, directory: FilePath(without.path(percentEncoded: false)))
        let sut = Tracker(store: store, enrichers: [.vendorIdentifier(identifier)])
        let control = Tracker(store: controlStore)

        sut.track(Tapped(number: 1))
        sut.track(Tapped(number: 2))
        await sut.finish()
        control.track(Tapped(number: 1))
        control.track(Tapped(number: 2))
        await control.finish()
        store.synchronize()
        controlStore.synchronize()

        var carried = 0
        for await record in sut.records where record.context[VendorIdentifierKey.self].flatMap(record.reveal) == identifier {
            carried += 1
        }
        func names(in directory: URL) throws -> [String] {
            try FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false)).sorted()
        }
        func contains(_ bytes: [UInt8], _ needle: [UInt8]) -> Bool {
            guard bytes.count >= needle.count else { return false }
            return (0 ... bytes.count - needle.count).contains { bytes[$0 ..< $0 + needle.count].elementsEqual(needle) }
        }
        let expectedNames = try names(in: without)
        let actualNames = try names(in: withIdentifier)
        #expect(carried == 2)
        #expect(actualNames == expectedNames)
        for name in actualNames {
            let bytes = try Array(Data(contentsOf: withIdentifier.appending(path: name)))
            #expect(!contains(bytes, Array(identifier.uuidString.utf8)))
            #expect(!contains(bytes, Array(identifier.uuidString.lowercased().utf8)))
            #expect(!contains(bytes, withUnsafeBytes(of: identifier.uuid) { Array($0) }))
        }
    }
}
