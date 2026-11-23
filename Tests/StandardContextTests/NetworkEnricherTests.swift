import Events
import Foundation
import StandardContext
import Synchronization
import Testing
import Trackers
#if canImport(Network)
import Network
#endif

@Suite("StandardContext: the network", .timeLimit(.minutes(1)))
struct NetworkEnricherTests {
    struct Tapped: Event {
        var number: Int
    }

    /// The connection a test sets, read by the enricher for each event.
    final class Connection: Sendable {
        private let value: Mutex<NetworkKey.Value?>

        init(_ value: NetworkKey.Value?) {
            self.value = Mutex(value)
        }

        func set(_ newValue: NetworkKey.Value?) {
            value.withLock { $0 = newValue }
        }

        func get() -> NetworkKey.Value? {
            value.withLock { $0 }
        }
    }

    @Test("The network enricher sets NetworkKey to the connection when the worker reaches each event, not when it was made")
    func readsPerEvent() async throws {
        let connection = Connection(.wifi)
        let sut = Tracker(enrichers: [.network { connection.get() }])
        let expected: [NetworkKey.Value?] = [.wifi, .cellular, .offline]

        sut.track(Tapped(number: 1))
        await sut.flush()
        connection.set(.cellular)
        sut.track(Tapped(number: 2))
        await sut.flush()
        connection.set(.offline)
        sut.track(Tapped(number: 3))
        await sut.finish()

        var actual: [NetworkKey.Value?] = []
        for await record in sut.records {
            actual.append(record.context[NetworkKey.self])
        }
        #expect(actual == expected)
    }

    @Test("Before the first report of a connection, the network enricher sets nothing")
    func noConnectionNoKey() async throws {
        let sut = Tracker(enrichers: [.network { nil }])

        sut.track(Tapped(number: 1))
        await sut.finish()

        var records = sut.records.makeAsyncIterator()
        let actual = try #require(await records.next()).context[NetworkKey.self]
        #expect(actual == nil)
    }

    #if canImport(Network)
    @Test(
        "A path's connection is offline unless satisfied, then the first of Wi-Fi, cellular and wired Ethernet it uses, or other",
        arguments: [
            (NWPath.Status.unsatisfied, [NWInterface.InterfaceType.wifi], NetworkKey.Value.offline),
            (.requiresConnection, [.wifi], .offline),
            (.satisfied, [.wifi, .cellular, .wiredEthernet], .wifi),
            (.satisfied, [.cellular, .wiredEthernet], .cellular),
            (.satisfied, [.wiredEthernet, .other], .wiredEthernet),
            (.satisfied, [.other], .other),
            (.satisfied, [.loopback], .other),
            (.satisfied, [], .other),
        ]
    )
    func pathConnection(status: NWPath.Status, interfaces: [NWInterface.InterfaceType], expected: NetworkKey.Value) {
        let actual = NetworkKey.Value(status: status, usesInterfaceType: interfaces.contains)

        #expect(actual == expected)
    }
    #endif

    #if os(Linux)
    @Test("On Linux there is no path monitor, and the network enricher sets nothing")
    func linuxHasNoNetwork() async throws {
        let sut = Tracker(enrichers: [.network()])

        sut.track(Tapped(number: 1))
        await sut.finish()

        var records = sut.records.makeAsyncIterator()
        let actual = try #require(await records.next()).context[NetworkKey.self]
        #expect(actual == nil)
    }
    #endif
}
