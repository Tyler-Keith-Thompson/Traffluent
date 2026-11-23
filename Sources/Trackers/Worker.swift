internal import Events
internal import Foundation
internal import Instrumentation
import Logging
internal import Persistence

/// The one consumer of a tracker's ``Intake``: it validates, enriches, samples, gates, writes and
/// publishes each record, in the order the entries came, off the threads that tracked them.
struct Worker: Sendable {
    let sink: RecordSink
    let store: (any RecordStore)?
    let enrichers: [Enricher]
    let membership: ConsentGate.Membership?
    let rejections: DropReportQueue<RejectionReport>
    let samplers: [Sampler]
    let samplingSeed: UInt64
    let samplingDrops: DropReportQueue<SamplingDropReport>

    private static let logger = Logger(label: "Trackers.Worker")

    /// Delivers what `store` kept from earlier runs, then handles each entry until the intake
    /// ends, then lets go of what the consent holds for this tracker and ends the records.
    func run(_ entries: AsyncStream<Intake.Entry>) async {
        // The worker's own view of the decisions, changed only as it reaches each one, so a
        // record is gated by the decisions made before it was tracked, never by a later one.
        var statuses = membership?.statuses ?? [:]
        // The worker's alone, changed one record at a time in the order they were tracked, so
        // the decisions follow from the seed and that order.
        var sampling = SamplingStage(samplers: samplers, seed: samplingSeed)
        if let store {
            // Validated again: a constraint added since a record was written may reject it, and the
            // store then forgets it, as it was dropped on purpose.
            var admitted: [EventRecord] = []
            var rejected: [EventRecord] = []
            for record in store.takeRecoveredRecords().map(\.revealingSensitiveValues) {
                if rejects(record) {
                    rejected.append(record)
                } else {
                    admitted.append(record)
                }
            }
            forget(rejected)
            admit(admitted, statuses: statuses)
        }
        for await entry in entries {
            switch entry {
            case .track(let event, let timestamp, let sourceLocation, let context, let scopedEnrichers):
                // The identifier is drawn here rather than in `track`, which only accepts (D5):
                // nothing reads a record before the worker reaches it, so it is the same
                // identifier from the store to every destination and redelivery.
                let record = EventRecord(id: UUID(), event: event, timestamp: timestamp, sourceLocation: sourceLocation, context: context)
                // First, so an invalid event is never enriched, held, written or delivered.
                guard !rejects(record) else { continue }
                var enriched: [EventRecord] = []
                enrich(record, scopedEnrichers, from: 0, into: &enriched)
                // After the enrichers, whose keys (a session's) a sampler reads, and before the
                // consent and the store, so a sampled-out record is never held or written.
                admit(sample(enriched, with: &sampling), statuses: statuses)
            case .decide(let categories, let status):
                for category in categories {
                    statuses[category] = status
                }
                release(categories, status)
            case .flush(let continuation):
                continuation.resume(returning: true)
            }
        }
        membership?.leave()
        sink.subscription.finish()
        rejections.finish()
        samplingDrops.finish()
    }
}

extension Worker {
    /// Appends `record` to `enriched` as the enrichers from `stage` on leave it, after the records
    /// they add before it, each enriched by the enrichers after the one that added it and
    /// checked as a tracked record is.
    ///
    /// The stages are the copy's enrichers, then the tracker's: the copy's stand in for the
    /// caller's context, so they run first and the tracker's see what they set.
    fileprivate func enrich(_ record: EventRecord, _ scopedEnrichers: [Enricher], from stage: Int, into enriched: inout [EventRecord]) {
        var record = record
        for index in stage ..< scopedEnrichers.count + enrichers.count {
            let enricher = index < scopedEnrichers.count ? scopedEnrichers[index] : enrichers[index - scopedEnrichers.count]
            for added in enricher(&record) where !rejects(added) {
                enrich(added, scopedEnrichers, from: index + 1, into: &enriched)
            }
        }
        record.revealsSensitiveValues = true
        enriched.append(record)
    }

    /// Whether `record`'s event breaks a constraint, reporting it if so.
    fileprivate func rejects(_ record: EventRecord) -> Bool {
        guard let violation = record.event.constraintViolation() else { return false }
        let name = type(of: record.event).name
        #if DEBUG
        // At error in debug builds only: a release build reports it on rejectionReports alone,
        // and the property's value is never logged.
        Self.logger.error("Rejected \(name) tracked at \(record.sourceLocation.map { "\($0.fileID):\($0.line)" } ?? "an unknown call site"): \(violation)")
        #endif
        rejections.report(RejectionReport(eventName: name, violation: violation, recordCount: 1, timestamps: record.timestamp ... record.timestamp))
        return true
    }
}

extension Worker {
    /// The records of `records` that `sampling` keeps, in order, each stamped with its rate;
    /// each one dropped is reported.
    fileprivate func sample(_ records: [EventRecord], with sampling: inout SamplingStage) -> [EventRecord] {
        // A tracker without samplers, most of them, pays nothing for the stage: not even the
        // allocation of the kept records' array.
        guard !sampling.isEmpty else { return records }
        var kept: [EventRecord] = []
        kept.reserveCapacity(records.count)
        for var record in records {
            if sampling.keeps(&record) {
                kept.append(record)
            } else {
                samplingDrops.report(SamplingDropReport(eventName: record.name, recordCount: 1, timestamps: record.timestamp ... record.timestamp))
            }
        }
        return kept
    }
}

extension Worker {
    /// Sends each of `records` on, holds it or drops it, by its category's status in `statuses`.
    fileprivate func admit(_ records: [EventRecord], statuses: [ConsentCategory: ConsentStatus]) {
        guard let membership else {
            records.forEach(sink.send)
            return
        }
        var denied = DroppedRecordsByCategory()
        var forgotten: [EventRecord] = []
        var overflow = DroppedRecords()
        for record in records {
            switch statuses[record.consentCategory, default: .undecided] {
            case .granted:
                sink.send(record)
            case .denied:
                // An event tracked while denied was never collected; one a store kept from an
                // earlier run was, so its drop is reported and the store forgets it.
                guard record.deliveryTag != nil else { continue }
                denied.add(record)
                forgotten.append(record)
            case .undecided:
                if let dropped = membership.hold(record) {
                    overflow.add(dropped)
                }
            }
        }
        membership.report(denied.reports)
        if let timestamps = overflow.timestamps {
            membership.report([.heldRecordLimit(recordCount: overflow.count, timestamps: timestamps)])
        }
        forget(forgotten)
    }

    /// Delivers or drops what the consent holds of `categories` for this tracker, now `status`.
    fileprivate func release(_ categories: Set<ConsentCategory>, _ status: ConsentStatus) {
        guard let membership else { return }
        let released = membership.release(categories)
        switch status {
        case .granted:
            // Outside the consent's lock, on this worker: a store's writes block no tracker,
            // and nothing tracked after the decision is handled before these.
            released.forEach(sink.send)
        case .denied:
            var denied = DroppedRecordsByCategory()
            released.forEach { denied.add($0) }
            membership.report(denied.reports)
            forget(released)
        case .undecided:
            break
        }
    }

    /// Tells each store keeping one of `records` to forget it: they were dropped on purpose.
    fileprivate func forget(_ records: [EventRecord]) {
        // Grouped by store, so each store is told once (one transaction, for a database).
        var positions: [(acknowledger: any Acknowledger, positions: [UInt64])] = []
        for record in records {
            guard let tag = record.deliveryTag else { continue }
            if let index = positions.firstIndex(where: { $0.acknowledger === tag.acknowledger }) {
                positions[index].positions.append(tag.position)
            } else {
                positions.append((tag.acknowledger, [tag.position]))
            }
        }
        for store in positions {
            store.acknowledger.acknowledge(store.positions)
        }
    }
}

extension EventRecord {
    /// This record, revealing its event's sensitive values, as a tracker delivers its own.
    fileprivate var revealingSensitiveValues: EventRecord {
        var record = self
        record.revealsSensitiveValues = true
        return record
    }
}
