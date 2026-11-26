# Planted bugs for Persistence; run with `just mutate Persistence`. See scripts/mutate.py.
#
# Each mutant is Mutant(name, file, old, new), where `old` occurs once in Sources/Persistence/<file>
# (or `nth=` picks one), and mode="stmt" replaces whole statements rather than an expression.
# Every mutant must be caught; one that survives needs a test, or a note here saying why it is
# equivalent to the original. Mutants with module= plant bugs in the code that wires a store in:
# deliver(to:)'s acknowledgement (Destinations) and track's write-through (Trackers), which the
# store's suites exercise.
#
# Known equivalent mutants (left out, as they would survive by design):
# - Leaving a synchronized segment marked as needing synchronization: the next synchronize
#   fsyncs it again, which only counting fsync calls could observe.
# - Marking a recovered undecodable record as not acknowledged: it never counts as pending, so
#   it can only change a drop report's count for a recovered segment the bound evicts while it
#   holds an undecodable record, which no test arranges.
# - The directory's fsync after a new segment (pending.directory, synchronizeDirectory): only a
#   power cut on Linux could observe the entry it makes durable.
# - SegmentLog.records(at:)'s filter after the read, which leaves out a segment the bound deleted
#   while it was being read: only an append racing the read between the two locks could observe
#   it, which no test can arrange. A segment deleted before the read is left out by the first
#   lock (readbacknothing's tests). ENOENT's debug log rather than the error one, and the decode
#   failures' logs, are logs alone, which tests don't pin.
# - The fsync shim's own failure path: fsync on an open regular file doesn't fail in a test.
# - The frame buffer an append takes and gives back (spareFrameBuffer), and the limit on the one
#   kept: without them each frame allocates a buffer of its own, which only counting allocations
#   could observe.
# - The registry's encodeNil for an event that isn't its registration's type: the registry finds a
#   registration by the event's own type, so the cast always holds.
# - The rewrite's failure path deleting its temporary file, and its synchronizations (the file's
#   fsync, the directory's): a test can only make the temporary file's creation fail, which leaves
#   nothing to delete, and only a power cut could observe either fsync.

TESTS = ["PersistenceTests"]

F = "SegmentFormat.swift"
L = "SegmentLog.swift"
S = "SegmentStore.swift"
R = "EventRegistry.swift"
N = "RecordEncoding.swift"
V = "VersionMismatchCounts.swift"
SC = "Sensitive+Codable.swift"
RC = "Refined+Codable.swift"

MUTANTS = [
    # Event types not in `events` (TRAF-62).
    Mutant("unlistednotreported", L, "dropReporter.yield(.notPersisted(event: record.name))", "", mode="stmt"),
    Mutant("unlistedreportedeachrecord", L, "unlistedTypes.insert(type(of: record.event))", "(unlistedTypes.insert(type(of: record.event)) || true)"),
    Mutant("unlistedtypesalwaysnew", "UnlistedEventTypes.swift", "seen.withLock { $0.insert(ObjectIdentifier(type)).inserted }", "seen.withLock { _ in true }", mode="stmt"),

    # The format.
    Mutant("headermagic", F, "[0x54, 0x52, 0x46, 0x4C, 3, 0, 0, 0]", "[0x54, 0x52, 0x46, 0x4D, 3, 0, 0, 0]"),
    Mutant("headerversion", F, "[0x54, 0x52, 0x46, 0x4C, 3, 0, 0, 0]", "[0x54, 0x52, 0x46, 0x4C, 2, 0, 0, 0]"),
    Mutant("magicnotchecked", F, "bytes[0..<4].elementsEqual(header[0..<4])", "true"),
    Mutant("newerunreadable", F, "guard version <= Self.version else { return .newerVersion(version) }", "", mode="stmt"),
    Mutant("reservednotchecked", F, "guard bytes[4..<header.count].elementsEqual(header[4...]) else { return .unreadable }", "", mode="stmt"),
    Mutant("emptyframeaccepted", F, "length >= 1", "length >= 0"),
    Mutant("lengthpastend", F, "length <= bytes.count - start", "length <= bytes.count - start + 1"),
    Mutant("checksumignored", F, "bytes.crc32(of: payload) == checksum", "true"),
    Mutant("malformedmarkaccepted", F, "guard (length - 1) % 4 == 0 else { break reading }", "", mode="stmt"),
    Mutant("validcountnotadvanced", F, "contents.validByteCount = offset", "", mode="stmt"),
    Mutant("marknotread", F, "contents.marked.insert(bytes.littleEndianUInt32(at: numberOffset))", "", mode="stmt"),
    Mutant("payloadwithkind", F, "start + 1..<payload.upperBound", "start..<payload.upperBound"),
    # The record map (TRAF-83): Codable over the CBOR package.
    Mutant("filealwayswritten", N, "location.file != location.fileID", "true"),
    Mutant("filenotwritten", N, "location.file != location.fileID", "false"),
    Mutant("filefromfileid", N, "try container.decodeIfPresent(String.self, forKey: .file) ?? fileID", "fileID"),
    Mutant("functionnotwritten", N, "try container.encode(location.function, forKey: .function)", "", mode="stmt"),
    Mutant("linenotwritten", N, "try container.encode(location.line, forKey: .line)", "", mode="stmt"),
    Mutant("timestampsince1970", N, "record.timestamp.timeIntervalSinceReferenceDate", "record.timestamp.timeIntervalSince1970"),
    Mutant("timestampreadsince1970", N, "Date(timeIntervalSinceReferenceDate: try container.decode(Double.self, forKey: .timestamp))", "Date(timeIntervalSince1970: try container.decode(Double.self, forKey: .timestamp))"),
    Mutant("namenotwritten", N, "try container.encode(registration.name, forKey: .name)", "", mode="stmt"),
    Mutant("eventnotwritten", N, "try registration.encode(record.event, .event, &container)", "", mode="stmt"),
    Mutant("callsitenotwritten", N, "try container.encodeIfPresent(record.sourceLocation.map(StoredSourceLocation.init(location:)), forKey: .sourceLocation)", "", mode="stmt"),
    Mutant("callsitenotdecoded", N, "try container.decodeIfPresent(StoredSourceLocation.self, forKey: .sourceLocation)", "StoredSourceLocation?.none"),
    Mutant("storewritesnosensitive", N, "try SensitiveCoding.$revealsValues.withValue(true) {\n            try CBOREncoder().encode(StoredRecord(record: record, registration: registration))\n        }", "try SensitiveCoding.$revealsValues.withValue(false) {\n            try CBOREncoder().encode(StoredRecord(record: record, registration: registration))\n        }", mode="stmt"),
    Mutant("eventreadfromname", N, "try registration.decode(.event, container)", "try registration.decode(.name, container)"),
    # The record's identifier, written and given back on recovery.
    Mutant("idnotwritten", N, "try container.encode(record.id, forKey: .id)", "", mode="stmt"),
    Mutant("idnotrestored", N, "return .record(EventRecord(id: id, event: event, timestamp: timestamp, sourceLocation: location?.location))", "return .record(EventRecord(event: event, timestamp: timestamp, sourceLocation: location?.location))", mode="stmt"),
    Mutant("lengthnotwritten", F, "frame.storeBytes(of: length.littleEndian, toByteOffset: 0, as: UInt32.self)", "", mode="stmt"),
    Mutant("checksumnotwritten", F, "frame.storeBytes(of: checksum.littleEndian, toByteOffset: 4, as: UInt32.self)", "", mode="stmt"),
    Mutant("markoffbyone", F, "withUnsafeBytes(of: index.littleEndian) { frame.append(contentsOf: $0) }", "withUnsafeBytes(of: (index + 1).littleEndian) { frame.append(contentsOf: $0) }", mode="stmt"),
    Mutant("payloadnotframed", F, "frame.append(contentsOf: payload)", "", mode="stmt"),
    # An event whose encode(to:) throws: kept in memory, reported as a failed write.
    Mutant("encodefailurenotreported", L, "            Self.logger.error(\"Kept a \\(registration.name) record in memory only: encoding its event failed with \\(error)\")\n            dropReporter.yield(.writeFailed(recordCount: 1, timestamps: record.timestamp...record.timestamp))", "            Self.logger.error(\"Kept a \\(registration.name) record in memory only: encoding its event failed with \\(error)\")", mode="stmt"),
    # Appending.
    Mutant("notwritten", L, "try frame.write(to: state.segments[active].file.descriptor)", "", mode="stmt"),
    Mutant("nottagged", L, "tagged.deliveryTag = DeliveryTag(acknowledger: self, position: position)", "", mode="stmt"),
    Mutant("positionwithoutindex", L, "return number << 32 | index", "return number << 32", mode="stmt"),
    Mutant("notpending", L, "        pendingCount += 1", "", mode="stmt"),
    Mutant("lognotcounted", L, "state.byteCount += frame.byteCount", "", mode="stmt"),
    Mutant("segmentnotcounted", L, "        byteCount += frameByteCount", "", mode="stmt"),
    Mutant("rollsearly", L, "active.byteCount + frameByteCount > segmentByteCount", "active.byteCount + frameByteCount >= segmentByteCount"),
    Mutant("boundoffbyone", L, "state.byteCount + frameByteCount + (state.hasActive ? 0 : SegmentFormat.header.count) > byteBound", "state.byteCount + frameByteCount + (state.hasActive ? 0 : SegmentFormat.header.count) >= byteBound"),
    # After boundoffbyone, its condition holds two copies; the second is the original's.
    Mutant("headernotbounded", L, "(state.hasActive ? 0 : SegmentFormat.header.count)", "0", nth=1),
    Mutant("fullignored", L, "guard state.byteCount + frameByteCount + (state.hasActive ? 0 : SegmentFormat.header.count) <= byteBound else { return .full }", "", mode="stmt"),
    # The first report is an encoding failure's (encodefailurenotreported, above). The second, of a
    # frame larger than a frame can be (over 4 GiB), has no mutant: no test can build a record that
    # large. The three after it are a failed write's, a full log's and an exhausted log's.
    Mutant("writefailurenotreported", L, "dropReporter.yield(.writeFailed(recordCount: 1, timestamps: record.timestamp...record.timestamp))", "", mode="stmt", nth=2),
    Mutant("fullnotreported", L, "dropReporter.yield(.writeFailed(recordCount: 1, timestamps: record.timestamp...record.timestamp))", "", mode="stmt", nth=3),
    Mutant("partialwritekept", L, "try? state.segments[active].file.descriptor.resize(to: Int64(state.segments[active].byteCount))", "", mode="stmt"),
    Mutant("partialheaderkept", L, "try? path.removeFile()", "", mode="stmt"),
    Mutant("undeletedforgotten", L, "state.undeleted.insert(segment.number)", "", mode="stmt"),
    Mutant("undeletedsubtracted", L, "state.undeleted.insert(segment.number)", "state.undeleted.insert(segment.number)\nstate.byteCount -= segment.byteCount", mode="stmt"),
    Mutant("largestrejected", L, "frameByteCount <= byteBound - SegmentFormat.header.count", "frameByteCount < byteBound - SegmentFormat.header.count"),
    Mutant("evictsnewest", L, "Self.delete(state.segments.removeFirst(), from: &state, reports: &reports)", "Self.delete(state.segments.removeLast(), from: &state, reports: &reports)", mode="stmt", nth=0),
    # A drop that yields no report leaves the test waiting for it; the suite's time limit catches it.
    Mutant("recoverydropnotreported", L, "dropReporter.yield(report)", "", mode="stmt", nth=0),
    Mutant("dropnotreported", L, "dropReporter.yield(report)", "", mode="stmt", nth=1),
    Mutant("markdropnotreported", L, "dropReporter.yield(report)", "", mode="stmt", nth=2),
    Mutant("markunbounded", L, "state.byteCount + frame.count > byteBound", "false"),
    Mutant("reportcountsdelivered", L, "zip(segment.timestamps, segment.acknowledged).filter { !$0.1 }", "zip(segment.timestamps, segment.acknowledged).filter { _ in true }"),
    Mutant("reportlatestonly", L, "earliest...latest", "latest...latest"),
    Mutant("headernotwritten", L, "try withErrno { try descriptor.writeAll(SegmentFormat.header) }", "", mode="stmt"),
    Mutant("numbernotadvanced", L, "state.nextNumber += 1", "", mode="stmt"),
    # Delivery.
    Mutant("undeleteddelivered", L, "withheld.formUnion(indices.map { number << 32 | UInt64($0) })", "", mode="stmt", nth=0),
    Mutant("unmarkeddelivered", L, "withheld.formUnion(indices.map { number << 32 | UInt64($0) })", "", mode="stmt", nth=1),
    Mutant("marknotwritten", L, "try withErrno { try state.segments[segment].file.descriptor.writeAll(frame) }", "", mode="stmt"),
    Mutant("marknotcounted", L, "state.byteCount += frame.count", "", mode="stmt"),
    Mutant("acknowledgementignored", L, "state.segments[segment].acknowledged[index] = true", "", mode="stmt"),
    Mutant("pendingnotdecremented", L, "state.segments[segment].pendingCount -= 1", "", mode="stmt"),
    Mutant("acknowledgedtwice", L, "guard !state.segments[segment].acknowledged[index] else { continue }", "", mode="stmt"),
    Mutant("deliverednotdeleted", L, "Self.delete(segment, from: &state, reports: &reports)", "", mode="stmt"),
    # The third `state.hasActive = false`, after append's failure path and makeRoom's roll.
    Mutant("deletedactivekept", L, "state.hasActive = false", "", mode="stmt", nth=2),
    Mutant("groupslosefollowers", L, "groups[last].1.append(index)", "", mode="stmt"),
    Mutant("groupsloseothers", L, "groups[group].1.append(index)", "", mode="stmt"),
    # Recovery.
    Mutant("recovereduntagged", L, "record.deliveryTag = DeliveryTag(acknowledger: self, position: recovered.position)", "", mode="stmt"),
    Mutant("recoveredtakentwice", L, "state.recovered = []", "", mode="stmt"),
    Mutant("redeliveryignored", L, "record.isRedelivered = contents.marked.contains(frame.index)", "", mode="stmt"),
    Mutant("nottruncated", L, "try withErrno { try descriptor.resize(to: Int64(contents.validByteCount)) }", "", mode="stmt"),
    Mutant("corruptionnotreported", L, "reports.append(.corruption(byteCount: bytes.count - contents.validByteCount))", "", mode="stmt"),
    Mutant("unreadablereportedempty", L, "!bytes.isEmpty", "true"),
    Mutant("unreadablekept", L, "try path.removeFile()", "", mode="stmt", nth=0),
    Mutant("deliveredsegmentkept", L, "try path.removeFile()", "", mode="stmt", nth=1),
    Mutant("recoveryunbounded", L, "recovered.state.byteCount > byteBound", "false"),
    Mutant("numberingrestarts", L, "(numbers.last ?? 0) + 1", "1"),
    Mutant("undecodablenotreported", L, "reports.append(.undecodable(recordCount: undecodable))", "", mode="stmt"),
    Mutant("shortfilenames", L, 'String(repeating: "0", count: 20 - digits.count)', 'String(repeating: "0", count: 19 - digits.count)'),
    # Segment numbers: the last is 2³² - 1, a file numbered past it isn't a segment, and a log
    # that has used them all keeps a new record in memory, reported as a failed write.
    Mutant("segmentlimitraised", L, "1 << 32", "1 << 33"),
    Mutant("numberpastlimitread", L, "$0 < segmentNumberLimit ? $0 : nil", "$0"),
    Mutant("exhaustedunreported", L, "dropReporter.yield(.writeFailed(recordCount: 1, timestamps: record.timestamp...record.timestamp))", "", mode="stmt", nth=4),
    Mutant("anyfilename", L, 'guard name.hasSuffix(".segment") else { return nil }', "", mode="stmt"),
    # The store.
    Mutant("defaultbound", S, "5 * 1024 * 1024", "5 * 1000 * 1000"),
    Mutant("defaultsegment", S, "max(byteBound / 8, 1)", "max(byteBound / 4, 1)"),
    Mutant("boundatheaderallowed", S, "byteBound > SegmentFormat.header.count", "byteBound >= SegmentFormat.header.count"),
    Mutant("zerosegmentallowed", S, "$0 > 0", "$0 >= 0"),
    Mutant("duplicatenamesallowed", R, "guard byName[registration.name] == nil || byType[ObjectIdentifier(type)] != nil else { throw DuplicateEventName() }", "", mode="stmt"),
    Mutant("duplicatenamesmisnamed", S, "throw .duplicateEventName", "throw .byteBoundTooSmall", mode="stmt"),
    Mutant("repeatedtyperefused", R, "byName[registration.name] == nil || byType[ObjectIdentifier(type)] != nil", "byName[registration.name] == nil"),
    Mutant("notfoundbyname", R, "byName[registration.name] = registration", "", mode="stmt"),
    # Delivery's acknowledgement, in Destinations.
    Mutant("neveracknowledged", "DestinationBuffer.swift", "delivery.acknowledgement?.received()", "", mode="stmt", module="Destinations"),
    # The first is the delivery loop's; the second, after the loop, is noted as equivalent.
    Mutant("acknowledgedwhencancelled", "DestinationBuffer.swift", "guard !Task.isCancelled else { return }", "", mode="stmt", module="Destinations", nth=0),
    Mutant("nowilldeliver", "Deliver.swift", "store.acknowledger.willDeliver(store.positions)", "Set<UInt64>()", module="Destinations"),
    Mutant("withheldsent", "Deliver.swift", "return !held.contains(tag.position)", "return true", mode="stmt", module="Destinations"),
    # The batch's timestamps, taken from every record rather than the ones delivered, so a batch
    # whose records are all withheld is sent empty.
    Mutant("emptybatchsent", "Deliver.swift", "delivered.map(\\.timestamp)", "batch.map(\\.timestamp)", module="Destinations"),
    Mutant("firstdestinationacknowledges", "Deliver.swift", "State(remaining: destinationCount, stores: stores)", "State(remaining: 1, stores: stores)", module="Destinations"),
    Mutant("nodestinationswait", "Deliver.swift", "destinationCount == 0", "destinationCount == -1", module="Destinations"),
    # A batch a full destination buffer dropped, read back from the store once that destination
    # has caught up (TRAF-66).
    Mutant("droppednotkept", "DestinationBuffer.swift", "state.dropped.append(dropped)", "", mode="stmt", module="Destinations"),
    Mutant("waitingnotcounted", "DestinationBuffer.swift", "state.waitingCount += 1", "", mode="stmt", module="Destinations"),
    Mutant("readbackbeforecaughtup", "DestinationBuffer.swift", "guard state.waitingCount == 0 else { return nil }", "", mode="stmt", module="Destinations"),
    Mutant("readbacknotredelivered", "DestinationBuffer.swift", "guard await redeliverWhileCaughtUp() else { return }", "", mode="stmt", module="Destinations"),
    # The second, after the receive; the first, before the read, is noted as equivalent.
    Mutant("readbackacknowledgedwhencancelled", "DestinationBuffer.swift", "guard !Task.isCancelled else { return false }", "", mode="stmt", module="Destinations", nth=1),
    Mutant("readbacknotredeliveredmark", "DestinationBuffer.swift", "record.isRedelivered = stored.isRedelivered", "", mode="stmt", module="Destinations"),
    Mutant("readbackredacted", "DestinationBuffer.swift", "record.revealsSensitiveValues = stored.revealsSensitiveValues", "", mode="stmt", module="Destinations"),
    Mutant("readbackdropnotuncounted", "DestinationBuffer.swift", "state.waitingCount -= 1", "", mode="stmt", module="Destinations"),
    Mutant("readbacktakennotuncounted", "DestinationBuffer.swift", "state.withLock { $0.waitingCount -= 1 }", "", mode="stmt", module="Destinations"),
    Mutant("readbackrepeated", "DestinationBuffer.swift", "state.dropped.popFirst()", "state.dropped.first", module="Destinations"),
    # The second is received(keeping:)'s, a read-back batch's receipt.
    Mutant("readbackreceiptuncounted", "Deliver.swift", "state.remaining -= 1", "", mode="stmt", module="Destinations", nth=1),
    Mutant("readbackreceiptnotcounted", "DestinationBuffer.swift", "dropped.acknowledgement.received(keeping: read.kept)", "", mode="stmt", module="Destinations"),
    # Reading a segment's records back.
    Mutant("readbackwrongposition", L, "segment.number << 32 | UInt64(frame.index)", "segment.number << 32 | UInt64(frame.index + 1)"),
    Mutant("readbacknothing", L, "records.append(record)", "", mode="stmt"),
    # Write-through, in Trackers.
    Mutant("storeignored", "RecordSink.swift", "subscription.send(store.append(record))", "subscription.send(record)", mode="stmt", module="Trackers"),
    # The worker's recovered records.
    Mutant("recoverednotsent", "Worker.swift", "admit(admitted, statuses: statuses)", "", mode="stmt", module="Trackers"),
    Mutant("recoverednotgated", "Worker.swift", "admit(admitted, statuses: statuses)", "admitted.forEach(sink.send)", mode="stmt", module="Trackers"),
    Mutant("recoveredredacted", "Worker.swift", "store.takeRecoveredRecords().map(\\.revealingSensitiveValues)", "store.takeRecoveredRecords()", module="Trackers"),
    Mutant("recoveredwrittenagain", "RecordSink.swift", "record.deliveryTag == nil", "true", module="Trackers"),
    # Consent's gating of a store's records, in Trackers.
    Mutant("droppednotforgotten", "Worker.swift", "store.acknowledger.acknowledge(store.positions)", "", mode="stmt", module="Trackers"),
    Mutant("recovereddeniednotreported", "Worker.swift", "denied.add(record)", "", mode="stmt", module="Trackers"),
    Mutant("helddeniednotforgotten", "Worker.swift", "forget(released)", "", mode="stmt", module="Trackers"),
    # The first is leave's, a substring of the hold's after it; leave's first, as the hold's
    # mutant rewrites the text.
    Mutant("finishreportsstored", "ConsentGate.swift", "record.deliveryTag == nil", "true", nth=0, module="Trackers"),
    Mutant("recoveredbounded", "ConsentGate.swift", "held.record.deliveryTag == nil", "true", module="Trackers"),
    Mutant("storedcountzero", "ConsentGate.swift", "$0.stored.count", "0", module="Trackers"),
    # The first is the recovered records'; the second, the hold's, is in Trackers.py.
    Mutant("takesotherstrackersstored", "ConsentGate.swift", "guard held.member == member, isTaken(held.record) else { return false }", "guard isTaken(held.record) else { return false }", mode="stmt", nth=0, module="Trackers"),
    # Sensitive values (TRAF-83): written and read only while a store's coding reveals them, in
    # Events. The first copy of the check is the encoding's, the second the decoding's.
    Mutant("ownencoderwrites", SC, "SensitiveCoding.revealsValues", "true", nth=0, module="Events"),
    Mutant("storewritesnull", SC, "SensitiveCoding.revealsValues", "false", nth=0, module="Events"),
    Mutant("owndecoderreads", SC, "SensitiveCoding.revealsValues", "true", nth=1, module="Events"),
    Mutant("storereadsnothing", SC, "SensitiveCoding.revealsValues", "false", nth=1, module="Events"),
    Mutant("redactednotnull", SC, "try container.encodeNil()", "", mode="stmt", module="Events"),
    Mutant("sensitivenotwritten", SC, "try value.encode(to: encoder)", "", mode="stmt", module="Events"),
    # Refined's coding: its value as it is, checked again as it is read. The check has no mutant:
    # Refined has no initializer that skips it, so dropping it can't compile.
    Mutant("refinednotwritten", RC, "try value.encode(to: encoder)", "", mode="stmt", module="Events"),
    # A recovered record a constraint added since rejects: dropped and forgotten by the store.
    Mutant("recoveredrejectedadmitted", "Worker.swift", "rejected.append(record)", "admitted.append(record)", mode="stmt", module="Trackers"),
    Mutant("recoveredrejectedkept", "Worker.swift", "forget(rejected)", "", mode="stmt", module="Trackers"),
    # The record's schema version (TRAF-18): written with it, checked before its event is read, and
    # each mismatch reported by event and version.
    Mutant("versionnotwritten", N, "try container.encode(registration.version, forKey: .version)", "", mode="stmt"),
    # A record without a version is read by name: defaulting it to 1 would drop it at version 2.
    Mutant("versionmissingmismatches", N, "try container.decodeIfPresent(Int.self, forKey: .version)", "Optional(try container.decodeIfPresent(Int.self, forKey: .version) ?? 1)"),
    Mutant("versionnotchecked", N, "version != registration.version", "false"),
    Mutant("mismatchversionsswapped", N, ".versionMismatch(event: name, storedVersion: version, currentVersion: registration.version)", ".versionMismatch(event: name, storedVersion: registration.version, currentVersion: version)"),
    Mutant("registryversionfixed", R, "E.schemaVersion", "1"),
    Mutant("mismatchnotcounted", L, "mismatches.add(event: event, storedVersion: storedVersion, currentVersion: currentVersion)", "", mode="stmt"),
    Mutant("mismatchnotreported", L, "reports += mismatches.reports", "", mode="stmt"),
    Mutant("mismatchcountdoubled", V, "counts[Key(event: event, storedVersion: storedVersion, currentVersion: currentVersion), default: 0] += 1", "counts[Key(event: event, storedVersion: storedVersion, currentVersion: currentVersion), default: 0] += 2", mode="stmt"),
    Mutant("mismatchnameorderreversed", V, "event.utf8.lexicographicallyPrecedes(other.event.utf8)", "other.event.utf8.lexicographicallyPrecedes(event.utf8)"),
    Mutant("mismatchversionorderreversed", V, "storedVersion < other.storedVersion", "storedVersion > other.storedVersion"),
    Mutant("mismatchcurrentisstored", V, "key.currentVersion", "key.storedVersion"),
    # No mutant for FileSystem's Int(exactly:) on a file's size, which only a file past 2 GiB on a
    # 32-bit Int would reach.
    Mutant("partialwriteaccepted", "FileSystem.swift", "        while written < bytes.count {\n            written += try withErrno { try write(UnsafeRawBufferPointer(rebasing: bytes[written...])) }\n        }", "        written += try withErrno { try write(UnsafeRawBufferPointer(rebasing: bytes[written...])) }", mode="stmt"),
    # Recovery's rewrite of a segment it drops records from (TRAF-47).
    Mutant("dropsnotrewritten", L, "keptFrames.count < contents.records.count", "keptFrames.count < 0"),
    Mutant("rewritemarksdropped", L, "SegmentFormat.compacted(bytes, keeping: frames, marking: marked)", "SegmentFormat.compacted(bytes, keeping: frames, marking: [])"),
    Mutant("rewritemarksinverted", L, "records[$0].record.isRedelivered", "!records[$0].record.isRedelivered"),
    Mutant("compactedframestart", F, "frame.payload.lowerBound - 1 - frameHeaderByteCount", "frame.payload.lowerBound - frameHeaderByteCount"),
    Mutant("compactednomark", F, "!marked.isEmpty", "marked.isEmpty"),
    Mutant("rewritenotrenamed", L, "try temporary.rename(to: segment.file.path)", "", mode="stmt"),
    Mutant("rewritekeepsolddescriptor", L, "file = SegmentFile(path: segment.file.path, descriptor: descriptor)", "file = segment.file", mode="stmt"),
    Mutant("rewritebytecount", L, "compacted.count", "segment.byteCount"),
    Mutant("rewriteoldpositions", L, "Recovered(record: records[index].record, position: segment.number << 32 | UInt64(index))", "records[index]"),
    Mutant("rewriteacknowledged", L, "Array(repeating: false, count: records.count)", "Array(repeating: true, count: records.count)"),
    Mutant("rewritetimestamps", L, "records.map(\\.record.timestamp)", "records.map { _ in Date.distantPast }"),
    Mutant("interruptedrewritekept", L, "try directory.appending(name).removeFile()", "", mode="stmt"),
    Mutant("renamenoop", "FileSystem.swift", "destination.withPlatformString { renameFile(source, $0) }", "0"),
]
