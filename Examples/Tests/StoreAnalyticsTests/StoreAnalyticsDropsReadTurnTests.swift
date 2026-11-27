import Afluent
import AsyncQueues
import Foundation
import HTTPDestinations
import HTTPTypes
import StoreAnalytics
import StoreEvents
import SystemPackage
import Testing
import Trackers

@Suite("StoreAnalytics: one reader of its drops at a time", .timeLimit(.minutes(1)))
struct StoreAnalyticsDropsReadTurnTests {
    /// A transport that accepts every request and sends nothing.
    struct AcceptingTransport: HTTPTransport {
        func send(_ request: HTTPRequest, body: Data) async throws(HTTPTransportError) -> HTTPResponse {
            HTTPResponse(status: .noContent)
        }
    }

    // Swift Testing's runner, not the main serial executor (swift-concurrency-extras, which this
    // package doesn't depend on), orders these tasks, so the second reader may reach the drops
    // before or after the first one's iteration ends. Either way it gets none of them: the first
    // holds the turn from its first drop to the end, and the second reads only after that.
    @Test("A second reader of drops that starts while the first reads ends once the first's iteration ends and the analytics are gone; the first gets every drop, in order")
    func secondReaderWaitsItsTurn() async throws {
        let directory = FilePath(NSTemporaryDirectory()).appending("StoreAnalyticsDropsReadTurnTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: directory.string) }
        let endpoint = try #require(URL(string: "http://127.0.0.1:8080/v1/batches"))
        var sut: StoreAnalytics? = StoreAnalytics(
            collector: endpoint,
            consent: Consent([.analytics: .granted]),
            directory: directory,
            enrichers: [],
            transport: AcceptingTransport()
        )
        let drops = try #require(sut?.drops)
        let firstHoldsTurn = SingleValueSubject<Void>()
        let secondAboutToRead = SingleValueSubject<Void>()
        let expectedFirst = ["quantity", "quantity", "productID"]
        let expectedSecond: [String] = []
        let first = Task {
            var rejected: [String] = []
            for await drop in drops {
                if case .rejected(let report) = drop {
                    rejected.append(report.violation.property)
                }
                if rejected.count == 1 { try? firstHoldsTurn.send() }
            }
            return rejected
        }
        sut?.tracker.track(ProductAddedToCart(productID: "canvas-tote", quantity: 0))
        try await firstHoldsTurn.execute()
        let second = Task {
            var rejected: [String] = []
            try? secondAboutToRead.send()
            for await drop in drops {
                if case .rejected(let report) = drop {
                    rejected.append(report.violation.property)
                }
            }
            return rejected
        }
        try await secondAboutToRead.execute()

        sut?.tracker.track(ProductAddedToCart(productID: "canvas-tote", quantity: 11))
        sut?.tracker.track(ProductAddedToCart(productID: "Canvas Tote", quantity: 1))
        await sut?.tracker.finish()
        sut = nil
        let actualFirst = await first.value
        let actualSecond = await second.value

        #expect(actualFirst == expectedFirst)
        #expect(actualSecond == expectedSecond)
    }
}
