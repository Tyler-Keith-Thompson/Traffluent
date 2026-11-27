// The examples of the "Getting Started" article
// (Sources/Traffluent/Traffluent.docc/GettingStarted.md), verbatim, so the article cannot drift
// from the code. Its SwiftUI views are hosted in an AppKit window, so they run on the Mac alone,
// at the end of the file.

import Foundation
import SystemPackage
import Testing
import TrackerTesting
import TrackingPlans
import Traffluent

@Suite("Getting started examples", .timeLimit(.minutes(1)))
struct GettingStartedExamplesTests {
    @Event(name: "product_added_to_cart")
    struct ProductAddedToCart: Equatable {
        @Constrained(.pattern("^[a-z0-9]+(-[a-z0-9]+)*$", example: "canvas-tote"))
        var productID: String
        @Constrained(.minimum(1), .maximum(10))
        var quantity: Int
    }

    @Event(name: "signed_up", consent: .functional)
    struct SignedUp {
        var plan: String
        var email: Sensitive<String>
        var referrer: String?
    }

    struct Product: Identifiable, Hashable {
        var id: String
        var name: String
        var priceInCents: Int

        static let catalog = [
            Product(id: "canvas-tote", name: "Canvas Tote", priceInCents: 2_400),
            Product(id: "enamel-mug", name: "Enamel Mug", priceInCents: 1_800),
        ]
    }

    struct QuantityOutOfRange: Error, Equatable {}

    struct Cart {
        struct Line: Equatable {
            var product: Product
            var quantity: Int
        }

        private(set) var lines: [Line] = []

        static let quantities = 1...10

        mutating func add(_ product: Product, quantity: Int = 1) throws(QuantityOutOfRange) {
            guard Self.quantities.contains(quantity) else { throw QuantityOutOfRange() }
            lines.append(Line(product: product, quantity: quantity))
            Tracker.current.track(ProductAddedToCart(productID: product.id, quantity: quantity))
        }
    }

    @Test("A ProductAddedToCart with a quantity of 0 is rejected and never delivered")
    func constraints() async throws {
        let memory = InMemoryDestination()
        let tracker = Tracker()
        let delivery = tracker.records.batch().deliver(to: memory)
        let expected = [ProductAddedToCart(productID: "canvas-tote", quantity: 1)]

        tracker.track(ProductAddedToCart(productID: "canvas-tote", quantity: 0))
        tracker.track(ProductAddedToCart(productID: "canvas-tote", quantity: 1))
        await tracker.finish()
        try await delivery.execute()

        #expect(memory.events(of: ProductAddedToCart.self) == expected)
    }

    @Test("Building the tracker, delivering to the collector and watching what is dropped")
    func trackerDeliveryAndDrops() async throws {
        let savedDecisions: [ConsentCategory: ConsentStatus] = [.analytics: .granted, .functional: .granted]
        let collectorURL = try #require(URL(string: "https://collector.example.com/v1/batches"))
        let apiKey = "k3y"
        // The article's store uses the default directory; this one uses a scratch directory so the
        // test leaves nothing behind.
        let directory = FilePath(NSTemporaryDirectory()).appending("GettingStartedExamplesTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: directory.string) }

        let consent = Consent(savedDecisions)
        let store = try SegmentStore(directory: directory)
        let tracker = Tracker(
            store: store,
            consent: consent,
            enrichers: [.sessions(), .application(), .device(), .operatingSystem(), .locale(), .network()]
        )

        let plan = try TrackingPlan()
        let collector = HTTPDestination(
            endpoint: collectorURL,
            headerFields: [.authorization: "Bearer \(apiKey)"],
            encoder: CollectorBatchEncoder(plan: plan))
        let delivery = tracker.records
            .batch()
            .deliver(to: collector.redactingSensitiveValues())
        let delivering = Task { try await delivery.execute() }

        let rejections = tracker.rejectionReports
        let consentDrops = consent.dropReports
        let storeDrops = store.dropReports
        let collectorDrops = collector.dropReports
        let bufferDrops = delivery.bufferDropReports
        Task {
            await withDiscardingTaskGroup { group in
                group.addTask { for await report in rejections { print("Rejected: \(report)") } }
                group.addTask { for await report in consentDrops { print("Not consented: \(report)") } }
                group.addTask { for await report in storeDrops { print("Not stored: \(report)") } }
                group.addTask { for await report in collectorDrops { print("Not sent: \(report)") } }
                group.addTask { for await report in bufferDrops { print("Buffer full: \(report)") } }
            }
        }

        // Nothing is tracked through `tracker`, so nothing is sent and the example runs without a
        // network. The plan is checked against records of every event it lists instead: a session
        // tracker records SessionStarted and SessionEnded around the others.
        await tracker.finish()
        try await delivering.value
        let memory = InMemoryDestination()
        let recording = Tracker(enrichers: [.sessions()])
        let recordingDelivery = recording.records.batch().deliver(to: memory.redactingSensitiveValues())
        recording.track(ProductAddedToCart(productID: "canvas-tote", quantity: 2))
        recording.track(SignedUp(plan: "plus", email: Sensitive("ada@example.com"), referrer: nil))
        recording.track(ScreenViewed(screen: "Catalog"))
        await recording.finish()
        try await recordingDelivery.execute()
        let actual = CollectorBatchEncoder(plan: plan).batch(of: memory.records)
        let recordedNames = Set(memory.records.map { type(of: $0.event).name }).sorted()
        let expectedNames = [ProductAddedToCart.name, ScreenViewed.name, SessionStarted.name, SignedUp.name].sorted()

        #expect(actual.skippedRecords.isEmpty)
        #expect(actual.body != nil)
        #expect(recordedNames == expectedNames)
        #expect(store.pendingRecordCount == 0)
    }

    @Test("A tracker bound with withTracker is Tracker.current inside the operation")
    func reachable() async throws {
        let memory = InMemoryDestination()
        let tracker = Tracker()
        let delivery = tracker.records.batch().deliver(to: memory)
        let expected = ["plus"]

        withTracker(tracker) {
            Tracker.current.track(SignedUp(plan: "plus", email: Sensitive("ada@example.com"), referrer: nil))
        }
        await tracker.finish()
        try await delivery.execute()

        #expect(memory.events(of: SignedUp.self).map(\.plan) == expected)
    }

    @Test("A quantity outside 1 to 10 throws QuantityOutOfRange and tracks nothing")
    func quantityOutOfRange() async {
        let mug = Product(id: "enamel-mug", name: "Enamel Mug", priceInCents: 1_800)
        var sut = Cart()
        let expectedError: QuantityOutOfRange? = QuantityOutOfRange()
        let expectedNames: [String] = []

        let tracked = await withRecordingTracker { () -> QuantityOutOfRange? in
            do throws(QuantityOutOfRange) {
                try sut.add(mug, quantity: 11)
                return nil
            } catch {
                return error
            }
        }

        #expect(tracked.value == expectedError)
        #expect(sut.lines.isEmpty)
        #expect(tracked.names == expectedNames)
    }

    @Test("Adding a product tracks ProductAddedToCart with its identifier and the quantity")
    func add() async throws {
        let tote = Product(id: "canvas-tote", name: "Canvas Tote", priceInCents: 2_400)
        var sut = Cart()
        let expectedEvents = [ProductAddedToCart(productID: "canvas-tote", quantity: 2)]
        let expectedLines = [Cart.Line(product: tote, quantity: 2)]

        let tracked = try await withRecordingTracker { try sut.add(tote, quantity: 2) }

        #expect(tracked.events(of: ProductAddedToCart.self) == expectedEvents)
        #expect(sut.lines == expectedLines)
    }
}

#if os(macOS)
import AppKit
import SwiftUI

extension GettingStartedExamplesTests {
    @MainActor
    @Suite("Getting started examples: SwiftUI", .serialized)
    struct SwiftUIExamples {
        struct StoreView: View {
            @State private var cart = Cart()

            var body: some View {
                NavigationStack {
                    List(Product.catalog) { product in
                        NavigationLink(product.name) {
                            ProductView(product: product, cart: $cart)
                                .trackScreen("Product")
                        }
                    }
                    .trackScreen("Catalog")
                }
            }
        }

        struct ProductView: View {
            let product: Product
            @Binding var cart: Cart
            @Environment(\.tracker) private var tracker

            var body: some View {
                Button("Add to Cart") {
                    // The default quantity, 1, is in range, so the cart never refuses it.
                    try? withTracker(tracker) { try cart.add(product) }
                }
                .navigationTitle(product.name)
            }
        }

        // The article shows the body alone; an app marks its App `@main`, which a test bundle,
        // with an entry point of its own, can't.
        struct StoreApp: App {
            let tracker = Tracker()

            var body: some Scene {
                WindowGroup {
                    StoreView()
                        .tracker(tracker)
                }
            }
        }

        @Test("The store's root view, given the tracker, tracks ScreenViewed for the catalog")
        func storeView() async throws {
            let tracker = Tracker()
            let root = StoreView().tracker(tracker)
            let expected = ScreenViewed(screen: "Catalog")

            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200), styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            defer { window.close() }
            let host = NSHostingView(rootView: root)
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            await tracker.finish()
            var records = tracker.records.makeAsyncIterator()
            let record = try #require(await records.next())

            #expect(record.event as? ScreenViewed == expected)
            #expect(record.context[ScreenKey.self] == "Catalog")
        }
    }
}
#endif
