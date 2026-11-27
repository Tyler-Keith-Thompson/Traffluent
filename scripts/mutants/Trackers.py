# Planted bugs for Trackers; run with `just mutate Trackers`. See scripts/mutate.py.
#
# Each mutant is Mutant(name, file, old, new), where `old` occurs once in Sources/Trackers/<file>
# (or `nth=` picks one), and mode="stmt" replaces whole statements rather than an expression.
# Every mutant must be caught; one that survives needs a test, or a note here saying why it is
# equivalent to the original.
#
# Known equivalent mutants (left out, as they would survive by design):
# - `file: file` swapped for `file: fileID` in `track`'s defaults: in the Swift 6 language mode
#   `#file` is `#fileID`. The explicit-location test still catches the swap in the record's
#   initializer arguments (filefromfileid below).

TESTS = ["TrackersTests"]

T = "Tracker.swift"
W = "WithTracker.swift"
S = "Subscription.swift"
E = "Records.swift"
C = "Consent.swift"
G = "ConsentGate.swift"
I = "Intake.swift"
K = "Worker.swift"
D = "DroppedRecords.swift"
N = "ConsentDropReport.swift"
J = "RejectionReport.swift"
R = "SampleRate.swift"
P = "Sampler.swift"
A = "SamplingStage.swift"
O = "SamplingDropReport.swift"
Z = "Int+SaturatingAdd.swift"

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
# - Tracker.current's unbound drops warning at every call, or never: only the log's level differs,
#   and tests don't pin logs.
# - Dropping the warning a records iterator logs as it starts to wait for its turn: tests don't
#   pin logs.
# - A never-set view tracker resolving to a bootstrapped `noOp` as the warning `unbound` rather
#   than `none`: only the log's level differs.
# - The enrichers' join with either early return removed: it then concatenates, the same array
#   with an allocation more.
# - The fallback with nothing bootstrapped given the bootstrapped clock or `Self.unbound`'s: a
#   tracker that drops reads no clock.
# - `Tracker.viewDefault` made from an empty environment rather than the process's: the test
#   processes aren't previews, so the two agree; `viewDefault(environment:)` is tested directly.
#
# Sampling mutants left out as equivalent:
# - Dropping the group decision's cache of the latest group (`latest = Decided(...)`): every record
#   then decides its group again, from the same node, to the same answer; only the time differs.
# - `if keeps, let rate` set to `if let rate`: the rate then lands on records that are dropped, which
#   nothing reads.
#
# The call site track captures. An expression rather than the statement: a mutated `let` would be
# scoped to its branch.
LOCATION = "SourceLocation(file: file, fileID: fileID, function: function, line: line, column: column)"
# What Tracker.current resolves to, swapped whole: the binding, then the bootstrapped default,
# then the unbound no-op.
CURRENT = "bound ?? bootstrapped.withLock { $0 } ?? .unbound"
# The enriched copy enriched(by:) returns, swapped whole as LOCATION is.
COPY = "Tracker(backing: backing, now: now, scopedEnrichers: scopedEnrichers + [enricher])"
# Tracker.viewDefault(environment:)'s answer, and the preview check inside it.
VIEW_DEFAULT = 'environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" ? .noOp : unset'
PREVIEW = 'environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"'
# The tracker a never-set view tracker resolves to, and its track's call to it.
RESOLVED = "Tracker(backing: target.backing, now: target.now, scopedEnrichers: Self.enrichers(target.scopedEnrichers, then: scopedEnrichers))"
# The fallback with nothing bootstrapped; its second copy is the bootstrapped `unset` tracker's.
UNBOUND_FALLBACK = "return Tracker(backing: .unbound, now: now, scopedEnrichers: scopedEnrichers)"
# What withTracker binds for an `unset` tracker given inside another binding.
BINDING = "Tracker(backing: bound.backing, now: bound.now, scopedEnrichers: Self.enrichers(bound.scopedEnrichers, then: scopedEnrichers))"
UNSET_TRACK = "resolved.track(event, file: file, fileID: fileID, function: function, line: line, column: column)"
WORKER = "Worker(sink: RecordSink(subscription: subscription, store: store), store: store, enrichers: enrichers, membership: membership, rejections: rejections, samplers: samplers, samplingSeed: samplingSeed, samplingDrops: samplingDrops)"

MUTANTS = [
    # isNoOp. The first `return false` is an intake's, the second a never-set view tracker's.
    Mutant("isnoopalwaysfalse", T, "return true", "return false", mode="stmt"),
    Mutant("intakeisnoop", T, "return false", "return true", mode="stmt", nth=0),
    Mutant("unsetisnoop", T, "return false", "return true", mode="stmt", nth=1),
    Mutant("currentignoresbinding", T, CURRENT, "bootstrapped.withLock { $0 } ?? .unbound"),
    # Tracker.current with nothing bound or bootstrapped: a tracker that records into nothing
    # (TRAF-81).
    Mutant("unboundrecords", T, CURRENT, "bound ?? bootstrapped.withLock { $0 } ?? Tracker()"),
    # The bootstrapped default (TRAF-81), whose tests are exit tests: never read, or read ahead
    # of the binding.
    Mutant("currentignoresbootstrap", T, CURRENT, "bound ?? .unbound"),
    Mutant("bootstrapoverbinding", T, CURRENT, "bootstrapped.withLock { $0 } ?? bound ?? .unbound"),
    # bootstrap: never stores, replaces the first tracker, or keeps it without throwing.
    Mutant("bootstrapstoresnothing", T, "bootstrapped = tracker", "", mode="stmt"),
    Mutant("bootstrapreplaces", T, "guard bootstrapped == nil else { throw TrackerAlreadyBootstrapped() }", "", mode="stmt"),
    Mutant("bootstrapsilent", T, "throw TrackerAlreadyBootstrapped()", "return", mode="stmt"),
    # The binding, nothing rather than the tracker: the sync spelling's, then the async one's,
    # after the first leaves one copy of the original.
    Mutant("syncunbound", W, "Optional(tracker.binding(over: Tracker.bound))", "nil", nth=0),
    Mutant("asyncunbound", W, "Optional(tracker.binding(over: Tracker.bound))", "nil", nth=1),
    # An `unset` tracker shadowing the binding around it (TRAF-94), in each spelling.
    Mutant("syncunsetshadows", W, "Optional(tracker.binding(over: Tracker.bound))", "Optional(tracker)", nth=0),
    Mutant("asyncunsetshadows", W, "Optional(tracker.binding(over: Tracker.bound))", "Optional(tracker)", nth=1),
    Mutant("defaultnow", T, "Date.now", "Date.distantPast", nth=0),
    Mutant("fixedtimestamp", T, "now()", "Date(timeIntervalSince1970: 0)"),
    Mutant("constanttrackid", K, "UUID()", "UUID(uuid: (0, 0, 0, 0, 0, 0, 0x40, 0, 0x80, 0, 0, 0, 0, 0, 0, 0))"),
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
    Mutant("nottracked", T, "intake.enqueue(entry)", "false"),
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
    Mutant("enrichersskipped", K, "scopedEnrichers.count + enrichers.count", "scopedEnrichers.count"),
    # Tracker.enriched(by:): the copy's enrichers, carried with each record to the worker.
    Mutant("scopedskipped", K, "enrich(record, scopedEnrichers, from: 0, into: &enriched)", "enrich(record, scopedEnrichers, from: scopedEnrichers.count, into: &enriched)", mode="stmt"),
    # The last `scopedEnrichers`: the one track's entry carries.
    Mutant("scopednotcarried", T, "scopedEnrichers", "[]", nth=16),
    Mutant("scopedreplaced", T, COPY, COPY.replace("scopedEnrichers + [enricher]", "[enricher]")),
    Mutant("scopedreversed", T, COPY, COPY.replace("scopedEnrichers + [enricher]", "[enricher] + scopedEnrichers")),
    Mutant("scopedignored", T, COPY, COPY.replace("scopedEnrichers + [enricher]", "scopedEnrichers")),
    Mutant("copylosesnow", T, COPY, COPY.replace("now: now,", "now: { Date.distantPast },")),
    # The first is track's; the second, the recovered records' helper.
    Mutant("recordsredacted", K, "record.revealsSensitiveValues = true", "record.revealsSensitiveValues = false", mode="stmt", nth=0),
    Mutant("workerdecisionignored", K, "statuses[category] = status", "", mode="stmt"),
    Mutant("flushnotresumed", K, "continuation.resume(returning: true)", "continuation.resume(returning: false)", mode="stmt"),
    Mutant("nofinish", K, "sink.subscription.finish()", "", mode="stmt"),
    Mutant("finishkeepsheld", K, "membership?.leave()", "", mode="stmt"),
    Mutant("gatebypassed", K, "admit(sample(enriched, with: &sampling), statuses: statuses)", "sample(enriched, with: &sampling).forEach(sink.send)", mode="stmt"),
    # Records an enricher adds (Enricher(records:)).
    Mutant("addedreversed", K, "enricher(&record)", "enricher(&record).reversed()"),
    Mutant("addeddropped", K, "!rejects(added)", "false"),
    Mutant("addedunchecked", K, "!rejects(added)", "true"),
    Mutant("addedunenriched", K, "index + 1", "scopedEnrichers.count + enrichers.count"),
    Mutant("addedrerunsearlier", K, "index + 1", "0"),
    Mutant("admitdefaultgranted", K, "statuses[record.consentCategory, default: .undecided]", "statuses[record.consentCategory, default: .granted]"),
    Mutant("grantednotsent", K, "sink.send(record)", "", mode="stmt"),
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
    Mutant("defaultstatusesignored", C, "        gate = ConsentGate(statuses: statuses, heldRecordLimit: Consent.defaultHeldRecordLimit)", "        gate = ConsentGate(statuses: [:], heldRecordLimit: Consent.defaultHeldRecordLimit)", mode="stmt"),
    Mutant("limitignored", C, "        gate = ConsentGate(statuses: statuses, heldRecordLimit: heldRecordLimit)", "        gate = ConsentGate(statuses: statuses, heldRecordLimit: Consent.defaultHeldRecordLimit)", mode="stmt"),
    # limitignored's text is now in the original branch alone.
    Mutant("limitstatusesignored", C, "        gate = ConsentGate(statuses: statuses, heldRecordLimit: heldRecordLimit)", "        gate = ConsentGate(statuses: [:], heldRecordLimit: heldRecordLimit)", mode="stmt"),
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
    Mutant("reportsneverend", G, "dropReports.finish()", "", mode="stmt"),
    Mutant("countdoubled", D, "count += 1", "count += 2", mode="stmt"),
    Mutant("lowerboundfirst", D, "min($0.lowerBound, record.timestamp)", "$0.lowerBound"),
    Mutant("upperboundlatest", D, "max($0.upperBound, record.timestamp)", "record.timestamp"),
    # How the drop reports merge while unread. The queue holding them is AsyncQueues', whose spec
    # plants its bugs.
    Mutant("reportsnotmerged", N, "last.merging(report)", "nil"),
    Mutant("mergedcountlost", N, "count.saturatingAdd(nextCount)", "count"),
    # Merged counts saturate (TRAF-115): a plain sum traps on a count of Int.max.
    Mutant("mergedcountunsaturated", N, "count.saturatingAdd(nextCount)", "count + nextCount"),
    Mutant("mergedtimestampsfirst", N, "max(timestamps.upperBound, nextTimestamps.upperBound)", "timestamps.upperBound"),
    # Subscription.
    Mutant("subjectnotfinished", S, "subject.send(completion: .finished)", "", mode="stmt"),
    Mutant("subscriptionnotsent", S, "subject.send(record)", "", mode="stmt"),
    # A cancelled read traps on its CancellationError rather than returning nil.
    Mutant("cancelledreadtraps", S, "try? await subscription.next()", "try! await subscription.next()"),
    # Each read subscribes afresh, so what was tracked before it, or while a cancelled read waited,
    # is lost.
    Mutant("subscribedperread", S, "try? await subscription.next()", "try? await subject.makeSubscription().next()"),
    # One reader at a time (TRAF-97). The turn itself is AsyncQueues' ReadLock, whose spec plants
    # its bugs; these are the records' use of it.
    Mutant("endedreaderkeepsturn", E, "reader.release()", "", mode="stmt"),
    # A cancelled wait taken as the turn, reading the subscription while another reader waits.
    Mutant("cancelledwaitreads", E, "guard await reader.acquire() else { return nil }", "_ = await reader.acquire()", mode="stmt"),
    # The worker's validation, first, and its reports.
    Mutant("rejectedadmitted", K, "guard !rejects(record) else { continue }", "", mode="stmt"),
    Mutant("unvalidatedwithconsent", K, "record.event.constraintViolation()", "(membership == nil ? record.event.constraintViolation() : nil)"),
    Mutant("rejectionnotreported", K, "rejections.enqueue(RejectionReport(eventName: name, violation: violation, recordCount: 1, timestamps: record.timestamp ... record.timestamp))", "", mode="stmt"),
    Mutant("rejectionsneverend", K, "rejections.finish()", "", mode="stmt"),
    Mutant("rejectionsunread", I, "rejectionReports = rejections", "rejectionReports = .finished(name: \"\")", mode="stmt"),
    Mutant("rejectionreportsofnoop", T, "intake.rejectionReports", ".finished(name: \"\")"),
    # Rejection reports' merging: by event, property and keyword, wherever the report waits.
    Mutant("rejectionsnotmerged", J, "waiting.firstIndex(where: { $0.eventName == report.eventName && $0.violation == report.violation })", "nil"),
    Mutant("mergedacrossevents", J, "$0.eventName == report.eventName && $0.violation == report.violation", "$0.violation == report.violation"),
    Mutant("mergedacrossviolations", J, "$0.eventName == report.eventName && $0.violation == report.violation", "$0.eventName == report.eventName"),
    Mutant("mergedrejectioncountlost", J, "recordCount.saturatingAdd(report.recordCount)", "recordCount"),
    Mutant("mergedrejectionunsaturated", J, "recordCount.saturatingAdd(report.recordCount)", "recordCount + report.recordCount"),
    Mutant("mergedrejectionlowerlatest", J, "min(timestamps.lowerBound, report.timestamps.lowerBound)", "report.timestamps.lowerBound"),
    Mutant("mergedrejectionupperlatest", J, "max(timestamps.upperBound, report.timestamps.upperBound)", "report.timestamps.upperBound"),
    # Sampling: the keep or drop draw, the rate's 0 and 1 boundaries, a group's one decision, the
    # rate stamped on kept records, the stage before the consent and the store, and the drops counted.
    Mutant("drawinverted", A, "generator.bernoulli(samplers[index].rate.value)", "!generator.bernoulli(samplers[index].rate.value)"),
    Mutant("sharedstream", A, "tree[index]", "tree[0]"),
    Mutant("shortcircuit", A, "samplers[index].selects(record)", "keeps && samplers[index].selects(record)"),
    Mutant("anydecisionkeeps", A, "keeps = keeps && decision", "keeps = keeps || decision", mode="stmt"),
    Mutant("ratenotmultiplied", A, "rate?.multiplied(by: samplers[index].rate) ?? samplers[index].rate", "samplers[index].rate"),
    Mutant("productisother", R, "value * other.value", "other.value"),
    Mutant("ratenotstamped", A, "record.context[SampleRateKey.self] = rate", "", mode="stmt"),
    Mutant("ratetopbound", R, "(0 ... 1).contains(value)", "(0 ..< 1).contains(value)"),
    Mutant("rateunbounded", R, "(0 ... 1).contains(value)", "value >= 0"),
    Mutant("anyeventtype", P, "$0.event is E", "true"),
    Mutant("ungroupeddropped", P, "return nil", "return false", mode="stmt"),
    Mutant("stalegroup", P, "latest.group == group", "true"),
    Mutant("onegroupnode", P, "node[group.description]", 'node["group"]'),
    Mutant("defaultseedfixed", T, ".random(in: .min ... .max)", "0", nth=0),
    Mutant("notsampled", K, "admit(sample(enriched, with: &sampling), statuses: statuses)", "admit(enriched, statuses: statuses)", mode="stmt"),
    Mutant("stageskipped", K, "guard !sampling.isEmpty else { return records }", "guard sampling.isEmpty else { return records }", mode="stmt"),
    Mutant("dropnotreported", K, "samplingDrops.enqueue(SamplingDropReport(eventName: record.name, recordCount: 1, timestamps: record.timestamp ... record.timestamp))", "", mode="stmt"),
    Mutant("dropsneverend", K, "samplingDrops.finish()", "", mode="stmt"),
    Mutant("dropsmergedacrossevents", O, "waiting.firstIndex(where: { $0.eventName == report.eventName })", "waiting.indices.last"),
    Mutant("mergeddropcountlost", O, "recordCount.saturatingAdd(report.recordCount)", "recordCount"),
    Mutant("mergeddropunsaturated", O, "recordCount.saturatingAdd(report.recordCount)", "recordCount + report.recordCount"),
    Mutant("mergeddroplowerlatest", O, "min(timestamps.lowerBound, report.timestamps.lowerBound)", "report.timestamps.lowerBound"),
    # Saturating addition (TRAF-115). The upper guard dropped is the *unsaturated mutants above,
    # as each merge's sum then traps. Equivalent, so left out: `<` for `<=` and `>` for `>=` in the
    # guards, or a bound one nearer, which differ only where the sum is exactly that bound, which
    # both branches return; and `other > 0` for `other >= 0`, as adding 0 gives `self` either way.
    Mutant("saturatesbelowmax", Z, "return Int.max", "return Int.max - 1", mode="stmt"),
    Mutant("saturatingunderflows", Z, "guard self >= Int.min - other else { return Int.min }", "", mode="stmt"),
    Mutant("rejectiondescribed", J, '"\\(eventName): \\(violation) (\\(recordCount) rejected)"', '"\\(eventName): \\(violation)"'),
    # A view's tracker that was never set (TRAF-94): the preview check, whole, then its test.
    Mutant("previewignored", T, VIEW_DEFAULT, "unset"),
    Mutant("alwayspreview", T, VIEW_DEFAULT, ".noOp"),
    Mutant("previewanyvalue", T, PREVIEW, 'environment["XCODE_RUNNING_FOR_PREVIEWS"] != nil'),
    # What it resolves to as it is used, whose tests bootstrap, so are exit tests: the
    # bootstrapped tracker, its enrichers then the copy's, its clock; never itself again.
    Mutant("unsetignoresbootstrap", T, "Self.bootstrapped.withLock({ $0 })", "nil as Tracker?"),
    Mutant("unsetresolvesitself", T, UNBOUND_FALLBACK, UNBOUND_FALLBACK.replace(".unbound", ".unset"), mode="stmt", nth=1),
    Mutant("unsetdropsintake", T, RESOLVED, RESOLVED.replace("backing: target.backing", "backing: .unbound")),
    Mutant("unsetenrichersreversed", T, RESOLVED, RESOLVED.replace("Self.enrichers(target.scopedEnrichers, then: scopedEnrichers)", "Self.enrichers(scopedEnrichers, then: target.scopedEnrichers)")),
    Mutant("unsetlosestargetenrichers", T, RESOLVED, RESOLVED.replace("Self.enrichers(target.scopedEnrichers, then: scopedEnrichers)", "scopedEnrichers")),
    Mutant("unsetlosesownenrichers", T, RESOLVED, RESOLVED.replace("Self.enrichers(target.scopedEnrichers, then: scopedEnrichers)", "target.scopedEnrichers")),
    Mutant("unsetlosesnow", T, RESOLVED, RESOLVED.replace("now: target.now,", "now: { Date.distantPast },")),
    # Its members, each the resolved tracker's.
    Mutant("unsetnottracked", T, UNSET_TRACK, "", mode="stmt"),
    Mutant("unsetlosescallsite", T, UNSET_TRACK, "resolved.track(event)", mode="stmt"),
    Mutant("unsetrecordsempty", T, "resolved.records", "Records(subscription: nil)"),
    Mutant("unsetnostore", T, "resolved.store", "nil"),
    Mutant("unsetrejectionsempty", T, "resolved.rejectionReports", ".finished(name: \"\")"),
    Mutant("unsetsamplingdropsempty", T, "resolved.samplingDropReports", ".finished(name: \"\")"),
    Mutant("unsetflushreturns", T, "await resolved.flush()", "", mode="stmt"),
    Mutant("unsetfinishreturns", T, "await resolved.finish()", "", mode="stmt"),
    # The enrichers' join, which hands back one side when the other is empty.
    Mutant("joinfirstemptywrong", T, "if first.isEmpty { return second }", "if first.isEmpty { return first }", mode="stmt"),
    Mutant("joinsecondemptywrong", T, "if second.isEmpty { return first }", "if second.isEmpty { return second }", mode="stmt"),
    # withTracker's binding of an `unset` tracker inside another: keeping the `unset` backing, or
    # the enrichers reversed. Shadowing the binding is syncunsetshadows and asyncunsetshadows: a
    # statement mutant of binding(over:)'s guard would scope its unwrapped `bound` to a branch.
    Mutant("bindingkeepsunset", T, BINDING, BINDING.replace("backing: bound.backing", "backing: backing")),
    Mutant("bindingreversed", T, BINDING, BINDING.replace("Self.enrichers(bound.scopedEnrichers, then: scopedEnrichers)", "Self.enrichers(scopedEnrichers, then: bound.scopedEnrichers)")),
]
