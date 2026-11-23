# Planted bugs for Trackers; run with `just mutate Trackers`. See scripts/mutate.py.
#
# Each mutant is Mutant(name, file, old, new), where `old` occurs once in Sources/Trackers/<file>
# (or `nth=` picks one), and mode="stmt" replaces whole statements rather than an expression.
# Every mutant must be caught; one that survives needs a test, or a note here saying why it is
# equivalent to the original.
#
# Known equivalent mutants (left out, as they would survive by design):
# - Dropping `waiter.id == call` from stopWaiting: it matters only when a cancellation reaches a
#   reader after its record was handed over and before its wait returns, and another reader has
#   started waiting in between. No test can place a cancellation inside that window: the reader's
#   own task is the one that would have to run in it.
# - Dropping deinit's cancellation of the read task: a tracker dropped while a read waits then keeps
#   one suspended task and its subscription alive, which no test can observe without inspecting
#   the process's tasks.
# - `file: file` swapped for `file: fileID` in `track`'s defaults: in the Swift 6 language mode
#   `#file` is `#fileID`. The explicit-location test still catches the swap in the record's
#   initializer arguments (filefromfileid below).

TESTS = ["TrackersTests"]

T = "Tracker.swift"
W = "WithTracker.swift"
S = "Subscription.swift"
N = "Enricher.swift"
C = "Consent.swift"
G = "ConsentGate.swift"
I = "Intake.swift"
K = "Worker.swift"
D = "DroppedRecords.swift"
Q = "DropReportQueue.swift"
J = "RejectionReport.swift"

# Consent mutants that only a store can catch (a recovered record's gating, a store forgetting what
# the hold drops) are in Persistence.py, whose suites have stores.
#
# Also equivalent, so left out:
# - Dropping `leave()`'s removal of the tracker's intake: a decision then yields to an intake
#   already finished, which drops it.
# - Dropping flush's wait for the worker once the intake is finished: it matters only to a flush
#   racing a finish on another task, which no test can order without a hook in the intake.
# - Dropping the log of an event tracked after finish: tests don't pin logs. Nor the worker's
#   debug log of a rejection.
#
# The call site track captures. An expression rather than the statement: a mutated `let` would be
# scoped to its branch.
LOCATION = "SourceLocation(file: file, fileID: fileID, function: function, line: line, column: column)"
WORKER = "Worker(sink: RecordSink(subscription: subscription, store: store), store: store, enrichers: enrichers, membership: membership, rejections: rejections)"

MUTANTS = [
    Mutant("currentignoresbinding", T, "bound ?? .noOp", ".noOp"),
    Mutant("syncunbound", W, "return try Tracker.$bound.withValue(tracker, operation: operation)", "return try operation()", mode="stmt"),
    Mutant("asyncunbound", W, "return try await Tracker.$bound.withValue(tracker, operation: operation)", "return try await operation()", mode="stmt"),
    Mutant("defaultnow", T, "Date.now", "Date.distantPast", nth=0),
    Mutant("fixedtimestamp", T, "now()", "Date(timeIntervalSince1970: 0)"),
    # Each swaps one field of the source location; the original expression stays in the innermost
    # else branch, so every one finds it.
    Mutant("filefromfileid", T, LOCATION, LOCATION.replace("file: file,", "file: fileID,")),
    Mutant("fileidfromfile", T, LOCATION, LOCATION.replace("fileID: fileID,", "fileID: file,")),
    Mutant("functionfromfile", T, LOCATION, LOCATION.replace("function: function,", "function: file,")),
    Mutant("ownfunction", T, LOCATION, LOCATION.replace("function: function,", "function: #function,")),
    Mutant("linefromcolumn", T, LOCATION, LOCATION.replace("line: line,", "line: column,")),
    Mutant("ownline", T, LOCATION, LOCATION.replace("line: line,", "line: #line,")),
    Mutant("columnfromline", T, LOCATION, LOCATION.replace("column: column)", "column: line)")),
    Mutant("contextignored", T, "ServiceContext.current ?? .topLevel", "ServiceContext.topLevel"),
    Mutant("nottracked", T, "intake.enqueue(.track(record))", "false"),
    # The intake.
    Mutant("enrichersreversed", I, WORKER, WORKER.replace("enrichers: enrichers,", "enrichers: enrichers.reversed(),")),
    Mutant("consentignored", I, "consent?.gate.join(entries)", "nil"),
    Mutant("finishedqueued", I, "return false", "return true", mode="stmt"),
    Mutant("flushnotqueued", I, "!enqueue(.flush(continuation))", "true"),
    # The first is deinit's: a released tracker then never ends its records.
    Mutant("releasednotfinished", I, "entries.finish()", "", mode="stmt", nth=0),
    # A finish that never ends the intake leaves every read waiting, so the time limit catches it.
    Mutant("intakenotfinished", I, "entries.finish()", "", mode="stmt", nth=1),
    Mutant("finishdoesntwait", I, "await worker.value", "", mode="stmt", nth=1),
    # The worker.
    Mutant("nosend", K, "records.forEach(sink.send)", "", mode="stmt"),
    Mutant("enrichersskipped", K, "enricher(&record.context)", "", mode="stmt"),
    Mutant("enricherinert", N, "enrich(&context)", "", mode="stmt"),
    # The first is track's; the second, the recovered records' helper.
    Mutant("recordsredacted", K, "record.revealsSensitiveValues = true", "record.revealsSensitiveValues = false", mode="stmt", nth=0),
    Mutant("workerdecisionignored", K, "statuses[category] = status", "", mode="stmt"),
    Mutant("flushnotresumed", K, "continuation.resume(returning: true)", "continuation.resume(returning: false)", mode="stmt"),
    Mutant("nofinish", K, "sink.subscription.finish()", "", mode="stmt"),
    Mutant("finishkeepsheld", K, "membership?.leave()", "", mode="stmt"),
    Mutant("gatebypassed", K, "admit([record], statuses: statuses)", "sink.send(record)", mode="stmt"),
    Mutant("admitdefaultgranted", K, "statuses[record.consentCategory, default: .undecided]", "statuses[record.consentCategory, default: .granted]"),
    Mutant("grantednotsent", K, "sink.send(record)", "", mode="stmt", nth=1),
    # An untagged denied record is counted as a recovered one: reported, though never collected.
    Mutant("deniedreported", K, "guard record.deliveryTag != nil else { continue }", "", mode="stmt"),
    Mutant("overflownotcounted", K, "overflow.add(dropped)", "", mode="stmt"),
    Mutant("overflownotreported", K, "membership.report([.heldRecordLimit(recordCount: overflow.count, timestamps: timestamps)])", "", mode="stmt"),
    Mutant("grantnotreleased", K, "released.forEach(sink.send)", "", mode="stmt"),
    Mutant("grantreleasedreversed", K, "membership.release(categories)", "Array(membership.release(categories).reversed())"),
    Mutant("deniednotreported", K, "released.forEach { denied.add($0) }", "", mode="stmt"),
    # Consent: its API.
    Mutant("grantdenies", C, "gate.decide(categories, .granted)", "gate.decide(categories, .denied)", mode="stmt"),
    # grantdenies leaves a copy of this text before the original.
    Mutant("denygrants", C, "gate.decide(categories, .denied)", "gate.decide(categories, .granted)", mode="stmt", nth=1),
    Mutant("defaultheldlimit", C, "1_000", "999"),
    Mutant("negativelimitallowed", C, "heldRecordLimit >= 0", "heldRecordLimit >= -1", nth=0),
    Mutant("checkednegativeallowed", C, "checkedHeldRecordLimit >= 0", "true"),
    Mutant("checkedlimitignored", C, "self.init(statuses, heldRecordLimit: checkedHeldRecordLimit)", "self.init(statuses)", mode="stmt"),
    Mutant("checkedstatusesignored", C, "self.init(statuses, heldRecordLimit: checkedHeldRecordLimit)", "self.init([:], heldRecordLimit: checkedHeldRecordLimit)", mode="stmt", nth=0),
    # Consent: the gate.
    Mutant("statusdefaultgranted", G, "$0.statuses[category, default: .undecided]", "$0.statuses[category, default: .granted]"),
    Mutant("heldcountzero", G, "$0.held.count", "0"),
    Mutant("decisionnotkept", G, "state.statuses[category] = status", "", mode="stmt"),
    Mutant("decisionnotqueued", G, "intake.yield(.decide(decided, status))", "", mode="stmt"),
    Mutant("membersshareid", G, "state.nextMember += 1", "", mode="stmt"),
    Mutant("joinignoresstatuses", G, "Membership(gate: self, id: id, statuses: state.statuses)", "Membership(gate: self, id: id, statuses: [:])"),
    Mutant("everycategorydecided", G, "categories.contains($0.consentCategory)", "true"),
    # The second is the hold's; the first, the recovered records'.
    Mutant("takesotherstrackers", G, "guard held.member == member, isTaken(held.record) else { return false }", "guard isTaken(held.record) else { return false }", mode="stmt", nth=1),
    Mutant("finishnotreported", G, "report([.finishedUndecided(recordCount: dropped.count, timestamps: timestamps)])", "", mode="stmt"),
    Mutant("heldnotkept", G, "state.held.append(held)", "", mode="stmt"),
    Mutant("holdunbounded", G, "state.held.count == heldRecordLimit", "state.held.count == heldRecordLimit + 1"),
    Mutant("dropsnewest", G, "state.held.removeFirst()", "state.held.removeLast()"),
    Mutant("zeroholdkeeps", G, "heldRecordLimit > 0", "heldRecordLimit >= 0"),
    Mutant("reportsneverend", G, "reporter.finish()", "", mode="stmt"),
    Mutant("countdoubled", D, "count += 1", "count += 2", mode="stmt"),
    Mutant("lowerboundfirst", D, "min($0.lowerBound, record.timestamp)", "$0.lowerBound"),
    Mutant("upperboundlatest", D, "max($0.upperBound, record.timestamp)", "record.timestamp"),
    # The drop reports' queue.
    Mutant("reportsnotmerged", Q, "last.merging(report)", "nil"),
    Mutant("mergedcountlost", Q, "count + nextCount", "count"),
    Mutant("mergedtimestampsfirst", Q, "max(timestamps.upperBound, nextTimestamps.upperBound)", "timestamps.upperBound"),
    Mutant("queuenotfinished", Q, "state.isFinished = true", "", mode="stmt"),
    Mutant("waitingreaderskipped", Q, "reader?.resume(returning: report)", "", mode="stmt"),
    Mutant("waitingreportlost", Q, "return .some(state.waiting.removeFirst())", "return .some(nil)", mode="stmt"),
    # Subscription.
    Mutant("subjectnotfinished", S, "subject.send(completion: .finished)", "", mode="stmt"),
    Mutant("subscriptionnotsent", S, "subject.send(record)", "", mode="stmt"),
    # A reader cancelled before it waits attaches anyway, after its handler ran: it waits for ever.
    Mutant("cancelledwaitattaches", S, "guard !Task.isCancelled else { return .some(nil) }", "", mode="stmt"),
    # A cancelled reader's waiter stays, so the next reader finds it still waiting and traps.
    Mutant("cancelledwaiterkept", S, "reads.state = .reading(waiter: nil)", "", mode="stmt"),
    Mutant("cancellednotresumed", S, "stopped?.continuation.resume(returning: nil)", "", mode="stmt"),
    # Taking over a read in flight traps as if its cancelled reader still waited.
    Mutant("takeovertraps", S, "reads.state = .reading(waiter: waiter)", 'preconditionFailure("taken over")', mode="stmt", nth=1),
    # A result no reader waited for is dropped rather than kept.
    Mutant("unclaimedresultdropped", S, "reads.state = .read(record, iterator)", "reads.state = .idle(iterator)", mode="stmt"),
    Mutant("waiterresultdropped", S, "waiter?.continuation.resume(returning: record)", "waiter?.continuation.resume(returning: nil)", mode="stmt"),
    Mutant("unclaimedresultnotgiven", S, "return .some(record)", "return .some(nil)", mode="stmt"),
    Mutant(
        "concurrentreadallowed", S,
        'preconditionFailure("A tracker\'s records are read by one task at a time")',
        "return .some(nil)",
        mode="stmt",
    ),
    # The worker's validation, first, and its reports.
    Mutant("rejectedadmitted", K, "guard !rejects(record) else { continue }", "", mode="stmt"),
    Mutant("unvalidatedwithconsent", K, "record.event.constraintViolation()", "(membership == nil ? record.event.constraintViolation() : nil)"),
    Mutant("rejectionnotreported", K, "rejections.report(RejectionReport(eventName: name, violation: violation, recordCount: 1, timestamps: record.timestamp ... record.timestamp))", "", mode="stmt"),
    Mutant("rejectionsneverend", K, "rejections.finish()", "", mode="stmt"),
    Mutant("rejectionsunread", I, "rejectionReports = AsyncStream(unfolding: { await rejections.next() })", "rejectionReports = AsyncStream { $0.finish() }", mode="stmt"),
    Mutant("rejectionreportsofnoop", T, "intake.rejectionReports", "AsyncStream { $0.finish() }"),
    # Rejection reports' merging: by event, property and keyword, wherever the report waits.
    Mutant("rejectionsnotmerged", J, "waiting.firstIndex(where: { $0.eventName == report.eventName && $0.violation == report.violation })", "nil"),
    Mutant("mergedacrossevents", J, "$0.eventName == report.eventName && $0.violation == report.violation", "$0.violation == report.violation"),
    Mutant("mergedacrossviolations", J, "$0.eventName == report.eventName && $0.violation == report.violation", "$0.eventName == report.eventName"),
    Mutant("mergedrejectioncountlost", J, "merged.recordCount + report.recordCount", "merged.recordCount"),
    Mutant("mergedrejectionlowerlatest", J, "min(merged.timestamps.lowerBound, report.timestamps.lowerBound)", "report.timestamps.lowerBound"),
    Mutant("mergedrejectionupperlatest", J, "max(merged.timestamps.upperBound, report.timestamps.upperBound)", "report.timestamps.upperBound"),
    Mutant("rejectiondescribed", J, '"\\(eventName): \\(violation) (\\(recordCount) rejected)"', '"\\(eventName): \\(violation)"'),
]
