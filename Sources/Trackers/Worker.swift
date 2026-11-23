internal import Events
import Logging
internal import Persistence

/// The one consumer of a tracker's ``Intake``: it validates, enriches, gates, writes and
/// publishes each record, in the order the entries came, off the threads that tracked them.
struct Worker: Sendable {
    let sink: RecordSink
    let store: (any RecordStore)?
    let enrichers: [Enricher]
    let membership: ConsentGate.Membership?
    let rejections: DropReportQueue<RejectionReport>

    private static let logger = Logger(label: "Trackers.Worker")

    /// Delivers what `store` kept from earlier runs, then handles each entry until the intake
    /// ends, then lets go of what the consent holds for this tracker and ends the records.
    func run(_ entries: AsyncStream<Intake.Entry>) async {
        // The worker's own view of the decisions, changed only as it reaches each one, so a
        // record is gated by the decisions made before it was tracked, never by a later one.
        var statuses = membership?.statuses ?? [:]
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
            case .track(var record, let scopedEnrichers):
                // First, so an invalid event is never enriched, held, written or delivered.
                guard !rejects(record) else { continue }
                // The copy's own enrichers stand in for the caller's context, so they run first and
                // the tracker's see what they set.
                for enricher in scopedEnrichers {
                    enricher(&record.context)
                }
                for enricher in enrichers {
                    enricher(&record.context)
                }
                record.revealsSensitiveValues = true
                admit([record], statuses: statuses)
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
    }
}

extension Worker {
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
