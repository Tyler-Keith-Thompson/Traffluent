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
# - readCount's check that a count fits in the bytes left: every reader of a count still throws
#   endOfData without it (a string's read checks again; an array's elements run out). It only
#   bounds the memory an array reserves for a corrupt count, which a test can't observe safely.
# - The directory's fsync after a new segment (pending.directory, synchronizeDirectory): only a
#   power cut on Linux could observe the entry it makes durable.
# - The fsync shim's own failure path: fsync on an open regular file doesn't fail in a test.

TESTS = ["PersistenceTests"]

F = "SegmentFormat.swift"
L = "SegmentLog.swift"
S = "SegmentStore.swift"
R = "EventRegistry.swift"
C = "StandardConformances.swift"
D = "BinaryDecoder.swift"
E = "BinaryEncoder.swift"
N = "RecordEncoding.swift"

MUTANTS = [
    # The format.
    Mutant("headermagic", F, "[0x54, 0x52, 0x46, 0x4C, 1, 0, 0, 0]", "[0x54, 0x52, 0x46, 0x4D, 1, 0, 0, 0]"),
    Mutant("headerversion", F, "[0x54, 0x52, 0x46, 0x4C, 1, 0, 0, 0]", "[0x54, 0x52, 0x46, 0x4C, 2, 0, 0, 0]"),
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
    Mutant("filealwaysnil", N, "encoder.encode(location.file == location.fileID ? nil : location.file)", "encoder.encode(String?.none)", mode="stmt"),
    Mutant("filefromfileid", N, "file ?? fileID", "fileID"),
    Mutant("trailingbytesaccepted", N, "guard decoder.isAtEnd else { throw .invalidValue }", "", mode="stmt"),
    Mutant("lengthnotwritten", F, "encoder.overwriteLittleEndian(length, at: 0)", "", mode="stmt"),
    Mutant("checksumnotwritten", F, "encoder.overwriteLittleEndian(checksum, at: 4)", "", mode="stmt"),
    Mutant("markoffbyone", F, "encoder.encode(index)", "encoder.encode(index + 1)", mode="stmt"),
    # Appending.
    Mutant("notwritten", L, "try withErrno { try state.segments[active].file.descriptor.writeAll(frame) }", "", mode="stmt"),
    Mutant("nottagged", L, "tagged.deliveryTag = DeliveryTag(acknowledger: self, position: position)", "", mode="stmt"),
    Mutant("positionwithoutindex", L, "return .written(state.segments[active].number << 32 | index)", "return .written(state.segments[active].number << 32)", mode="stmt"),
    Mutant("notpending", L, "state.segments[active].pendingCount += 1", "", mode="stmt"),
    Mutant("lognotcounted", L, "state.byteCount += frame.count", "", mode="stmt", nth=0),
    Mutant("segmentnotcounted", L, "state.segments[active].byteCount += frame.count", "", mode="stmt"),
    Mutant("rollsearly", L, "active.byteCount + frameByteCount > segmentByteCount", "active.byteCount + frameByteCount >= segmentByteCount"),
    Mutant("boundoffbyone", L, "state.byteCount + frameByteCount + (state.hasActive ? 0 : SegmentFormat.header.count) > byteBound", "state.byteCount + frameByteCount + (state.hasActive ? 0 : SegmentFormat.header.count) >= byteBound"),
    # After boundoffbyone, its condition holds two copies; the second is the original's.
    Mutant("headernotbounded", L, "(state.hasActive ? 0 : SegmentFormat.header.count)", "0", nth=1),
    Mutant("fullignored", L, "guard state.byteCount + frameByteCount + (state.hasActive ? 0 : SegmentFormat.header.count) <= byteBound else { return .full }", "", mode="stmt"),
    Mutant("writefailurenotreported", L, "dropReporter.yield(.writeFailed(recordCount: 1, timestamps: record.timestamp...record.timestamp))", "", mode="stmt", nth=0),
    Mutant("fullnotreported", L, "dropReporter.yield(.writeFailed(recordCount: 1, timestamps: record.timestamp...record.timestamp))", "", mode="stmt", nth=1),
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
    Mutant("marknotcounted", L, "state.byteCount += frame.count", "", mode="stmt", nth=1),
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
    Mutant("anyfilename", L, 'guard name.hasSuffix(".segment") else { return nil }', "", mode="stmt"),
    # The store.
    Mutant("defaultbound", S, "5 * 1024 * 1024", "5 * 1000 * 1000"),
    Mutant("defaultsegment", S, "max(byteBound / 8, 1)", "max(byteBound / 4, 1)"),
    Mutant("boundatheaderallowed", S, "byteBound > SegmentFormat.header.count", "byteBound >= SegmentFormat.header.count"),
    Mutant("zerosegmentallowed", S, "$0 > 0", "$0 >= 0"),
    Mutant("duplicatenamesallowed", R, 'precondition(byName[registration.name] == nil || byType[ObjectIdentifier(type)] != nil, "Two persisted event types share the name \\(registration.name); give one an explicit Event.name")', "", mode="stmt"),
    Mutant("repeatedtypetraps", R, "byName[registration.name] == nil || byType[ObjectIdentifier(type)] != nil", "byName[registration.name] == nil"),
    Mutant("notfoundbyname", R, "byName[registration.name] = registration", "", mode="stmt"),
    # The binary encoding.
    Mutant("intas32bits", C, "encoder.writeLittleEndian(Int64(self))", "encoder.writeLittleEndian(Int32(truncatingIfNeeded: self))", mode="stmt"),
    Mutant("truebyte", C, "UInt8(self ? 1 : 0)", "UInt8(self ? 2 : 0)"),
    Mutant("somebyte", C, "encoder.writeLittleEndian(UInt8(1))", "encoder.writeLittleEndian(UInt8(2))", mode="stmt"),
    Mutant("arraycount", C, "encoder.writeCount(count)", "encoder.writeCount(count + 1)", mode="stmt"),
    Mutant("datesince1970", C, "encoder.encode(timeIntervalSinceReferenceDate)", "encoder.encode(timeIntervalSince1970)", mode="stmt"),
    Mutant("doubleswapped", C, "encoder.writeLittleEndian(bitPattern)", "encoder.writeLittleEndian(bitPattern.byteSwapped)", mode="stmt", nth=0),
    Mutant("writebigendian", E, "value.littleEndian", "value.bigEndian", nth=0),
    Mutant("readbigendian", D, "Integer(littleEndian: raw.loadUnaligned(fromByteOffset: start - bytes.startIndex, as: Integer.self))", "Integer(bigEndian: raw.loadUnaligned(fromByteOffset: start - bytes.startIndex, as: Integer.self))"),
    Mutant("readunchecked", D, "guard count <= remainingCount else { throw .endOfData }", "", mode="stmt", nth=0),
    Mutant("endbeforeend", D, "position == bytes.endIndex", "position >= bytes.endIndex - 1"),
    # Delivery's acknowledgement, in Destinations.
    Mutant("neveracknowledged", "Deliver.swift", "delivery.acknowledgement?.received()", "", mode="stmt", module="Destinations"),
    Mutant("acknowledgedwhencancelled", "Deliver.swift", "guard !Task.isCancelled else { return }", "", mode="stmt", module="Destinations"),
    Mutant("nowilldeliver", "Deliver.swift", "store.acknowledger.willDeliver(store.positions)", "Set<UInt64>()", module="Destinations"),
    Mutant("withheldsent", "Deliver.swift", "return !held.contains(tag.position)", "return true", mode="stmt", module="Destinations"),
    Mutant("emptybatchsent", "Deliver.swift", "guard !delivered.isEmpty else { return nil }", "", mode="stmt", module="Destinations"),
    Mutant("firstdestinationacknowledges", "Deliver.swift", "remaining = Mutex(destinationCount)", "remaining = Mutex(1)", mode="stmt", module="Destinations"),
    Mutant("nodestinationswait", "Deliver.swift", "destinationCount == 0", "destinationCount == -1", module="Destinations"),
    # Write-through, in Trackers.
    Mutant("storeignored", "Tracker.swift", "subscription.send(store?.append(record) ?? record)", "subscription.send(record)", mode="stmt", module="Trackers"),
    # storeignored's replacement is a second copy, after the original in init.
    Mutant("recoverednotsent", "Tracker.swift", "subscription.send(record)", "", mode="stmt", module="Trackers", nth=0),
]
