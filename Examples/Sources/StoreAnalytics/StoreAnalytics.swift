import Afluent
import AsyncQueues
import AutomaticControlTracking
import CollectorEncoding
import Destinations
public import Events
public import Foundation
public import HTTPDestinations
import LifecycleTracking
import Logging
public import Persistence
import Sessions
import StandardContext
import StoreEvents
import SwiftUITracking
public import SystemPackage
public import Trackers
public import TrackingPlans

/// The store app's analytics: one tracker, which checks each event's constraints, stamps it with
/// the session and the device, gates it by the shopper's consent, keeps it on disk, and delivers
/// it to the collector without its sensitive values.
///
/// Build it once, where the app starts, and run ``deliver()`` for the life of the app:
///
/// ```swift
/// let analytics = StoreAnalytics(collector: collectorURL, consent: preferences.consent)
/// Task { try await analytics.deliver() }
/// ```
///
/// Then hand ``tracker`` to the code that tracks: the SwiftUI environment, a window scene's
/// traits, or a `withTracker` binding.
public struct StoreAnalytics: Sendable {
    /// What the app tracks its events through.
    public let tracker: Tracker
    /// Every drop report of the tracker, its consent, its store, the collector and the delivery,
    /// in the order each source reports them. It has one reader.
    public let drops: AsyncStream<AnalyticsDrop>
    // A closure building a new delivery on each call, rather than the delivery itself: a
    // delivery that was cancelled can't run again, and the collector's generic type stays out of
    // this one's.
    private let delivery: @Sendable () async throws -> Void

    private static let logger = Logger(label: "StoreAnalytics.StoreAnalytics")

    /// What every record's context gains: its session, and the app, device, operating system,
    /// locale and network it was tracked on.
    public static var enrichers: [Enricher] {
        [.sessions(), .application(), .device(), .operatingSystem(), .locale(), .network()]
    }

    /// The store's analytics, delivering to the collector at `endpoint`.
    ///
    /// - Parameters:
    ///   - endpoint: The collector's batches URL, such as the example server's
    ///     `http://127.0.0.1:8080/v1/batches`.
    ///   - consent: The shopper's consent, restored from their saved decisions.
    ///   - directory: Where the records are kept until they are delivered. When the store can't
    ///     be opened there, records are kept in memory only, and the failure is logged.
    ///   - enrichers: What every record's context gains; ``enrichers`` by default.
    ///   - transport: What sends each batch; `URLSession` by default.
    ///   - backoff: How long to wait before sending a batch again after a transient failure; 1
    ///     second, doubling up to 60, by default.
    ///   - clock: The clock batches are timed and failed sends are retried on.
    ///   - trackingPlan: The plan the collector encodes each record through; the store's,
    ///     `TrackingPlan.store`, by default. When it throws, nothing is delivered,
    ///     and ``deliver()`` throws its error.
    public init(
        collector endpoint: URL,
        consent: Consent,
        directory: FilePath = SegmentStore.defaultDirectory,
        enrichers: [Enricher] = StoreAnalytics.enrichers,
        transport: some HTTPTransport = URLSessionTransport(),
        backoff: ExponentialBackoff = ExponentialBackoff(),
        clock: some Clock<Duration> = ContinuousClock(),
        trackingPlan: () throws(TrackingPlanError) -> TrackingPlan = { () throws(TrackingPlanError) in try .store }
    ) {
        let store = Self.store(in: directory)
        let tracker = Self.tracker(store: store, consent: consent, enrichers: enrichers)
        let (bufferDrops, bufferDropReporter) = AsyncStream.makeStream(of: BufferDropReport.self)
        self.tracker = tracker
        do throws(TrackingPlanError) {
            let collector = try Self.collector(at: endpoint, plan: trackingPlan(), transport: transport, backoff: backoff, clock: clock)
            delivery = Self.delivery(of: tracker, to: collector, clock: clock, bufferDropReporter: bufferDropReporter)
            drops = AsyncStream(merging: tracker.rejectionReports, consent.dropReports, store?.dropReports, collector.dropReports, bufferDrops)
        } catch {
            // The store's plan is built from this app's own schemas, so this is a bug in the release. The
            // tracker still keeps every record in the store, for a release with a valid plan to
            // deliver, and deliver() throws the plan's error rather than sending nothing silently.
            Self.logger.error("Not delivering: the store's tracking plan is invalid (\(error))")
            delivery = { throw error }
            drops = AsyncStream(merging: tracker.rejectionReports, consent.dropReports, store?.dropReports, nil, bufferDrops)
        }
    }

    /// Delivers the tracker's records, those the store kept from earlier launches first, until
    /// the tracker finishes or the task is cancelled.
    ///
    /// Each call starts a new delivery, so one that was cancelled can be followed by another.
    /// Only one may run at a time: the tracker's records have one reader.
    ///
    /// - Throws: `CancellationError` when the task is cancelled, or the ``TrackingPlanError``
    ///   of a store tracking plan that is invalid, in which case nothing is delivered.
    public func deliver() async throws {
        try await delivery()
    }
}

extension StoreAnalytics {
    /// Step 1: a store, so a record survives the app ending before it is delivered; `nil`, and
    /// logged, when it can't be opened in `directory`. It keeps every event the app declares and
    /// the library's own, found in the modules the app links, so a new event needs no list.
    fileprivate static func store(in directory: FilePath) -> SegmentStore? {
        do {
            return try SegmentStore(directory: directory)
        } catch {
            logger.error("Keeping records in memory only: the store couldn't open (\(error))")
            return nil
        }
    }

    /// Step 2: the tracker. Its worker checks each event's constraints, runs the enrichers, then
    /// the samplers (this app has none), gates the record by `consent`, writes it to `store` and
    /// publishes it, in that order.
    fileprivate static func tracker(store: SegmentStore?, consent: Consent, enrichers: [Enricher]) -> Tracker {
        if let store {
            Tracker(store: store, consent: consent, enrichers: enrichers)
        } else {
            Tracker(consent: consent, enrichers: enrichers)
        }
    }

    /// Step 3: the collector, which encodes each record through the store's tracking plan. A
    /// batch that gets no response, a 5xx, 408 or 429 is sent again after `backoff`'s wait; any
    /// other refusal, a request that can't be sent, or a batch that can't be encoded is dropped
    /// and reported.
    fileprivate static func collector<Transport: HTTPTransport>(
        at endpoint: URL,
        plan: TrackingPlan,
        transport: Transport,
        backoff: ExponentialBackoff,
        clock: some Clock<Duration>
    ) -> HTTPDestination<Transport, CollectorBatchEncoder> {
        HTTPDestination(endpoint: endpoint, transport: transport, encoder: CollectorBatchEncoder(plan: plan), backoff: backoff, clock: clock)
    }

    /// Step 4: the delivery, a new one each time it runs: batches of 20, every 30 seconds, and
    /// as the app goes to the background.
    ///
    /// The collector never sees a sensitive value. A record without `SignedUp.email` still
    /// matches the plan, which never requires a `Sensitive` property.
    fileprivate static func delivery<Transport: HTTPTransport>(
        of tracker: Tracker,
        to collector: HTTPDestination<Transport, CollectorBatchEncoder>,
        clock: some Clock<Duration>,
        bufferDropReporter: AsyncStream<BufferDropReport>.Continuation
    ) -> @Sendable () async throws -> Void {
        {
            // One reporter serves every delivery, so the buffer drops arrive on one stream.
            try await tracker.records
                .batch(strategy: .either(.count(20), .time(interval: .seconds(30), clock: clock), .lifecycle))
                .deliver(to: collector.redactingSensitiveValues(), bufferDropReporter: bufferDropReporter)
                .execute()
        }
    }
}

extension AsyncStream where Element == AnalyticsDrop {
    /// Step 5: every drop report, as one stream, each source's in its order. The sources are
    /// passed as streams, not their owners, so the reading task holds no collector or store.
    fileprivate init(
        merging rejections: AsyncQueue<RejectionReport>,
        _ consentDrops: AsyncQueue<ConsentDropReport>,
        _ storeDrops: AsyncQueue<DropReport>?,
        _ collectorDrops: AsyncQueue<HTTPDropReport<CollectorEncodingError>>?,
        _ bufferDrops: AsyncStream<BufferDropReport>
    ) {
        let (drops, continuation) = AsyncStream.makeStream(of: AnalyticsDrop.self)
        let forwarding = Task {
            await withDiscardingTaskGroup { group in
                group.addTask { for await report in rejections { continuation.yield(.rejected(report)) } }
                group.addTask { for await report in consentDrops { continuation.yield(.notConsented(report)) } }
                if let storeDrops {
                    group.addTask { for await report in storeDrops { continuation.yield(.notStored(report)) } }
                }
                if let collectorDrops {
                    group.addTask { for await report in collectorDrops { continuation.yield(.notSent(report)) } }
                }
                group.addTask { for await report in bufferDrops { continuation.yield(.bufferFull(report)) } }
            }
            continuation.finish()
        }
        continuation.onTermination = { _ in forwarding.cancel() }
        self = drops
    }
}
