# Planted bugs for HeapEncoding; run with `just mutate HeapEncoding`. See scripts/mutate.py.
#
# Each mutant is Mutant(name, file, old, new), where `old` occurs once in
# Sources/HeapEncoding/<file> (or `nth=` picks one), and mode="stmt" replaces whole statements
# rather than an expression. Mutants are applied in this order, so one whose `old` holds another's
# comes first. Every mutant must be caught; one that survives needs a test, or a note here saying
# why it is equivalent.
#
# Known equivalent mutants (left out, as they would survive by design):
# - The properties PropertyJSON reads (its PropertyReader), flattening, identity and batch
#   splitting: PropertyJSON's spec plants those.
# - The unknownEvent arm of `HeapEncodingError.init(_ error: PropertyReadingError)` mapped to
#   another case: the catch in json(of:) only reaches it for an event the plan doesn't describe,
#   and the unknownEvent tests pin the case it maps to.
# - The catch of iso8601Timestamp: the guard before it already refuses every timestamp the
#   conversion would, so it is never taken.
# - The endpoints' `?? URL(fileURLWithPath: "/")` fallbacks: the literals always parse.
# - The factory's `backoff:` and `clock:` arguments: a mutant switch can't hold an argument, and
#   without them the destination would use the default backoff, which only slows the retry check.
# - The batch limit's record byte count moved by one either way alone: a record's capacity is the
#   smaller of it and the request's 1,000,000 bytes less the envelope, so 999,999 and 1,000,001
#   both leave 999,967; the default-limit test compares the whole limit, which catches both.
# - The notices the encoder's initializer logs for names Heap refuses or reserves: logs are for
#   developers, and tests don't pin them (AGENTS.md, Logging).

TESTS = ["HeapEncodingTests"]

B = "HeapBatchEncoder.swift"
F = "HTTPDestination+Heap.swift"
N = "String+HeapNames.swift"

LIMIT = "BatchLimit(maximumRecordCount: 1_000, maximumByteCount: 1_000_000, maximumRecordByteCount: 1_000_000)"
NAME_CHECK_ON_FAILURE = "if case .unknownEvent = error {} else {\n                try record.checkHeapName()\n            }"

MUTANTS = [
    # The limits.
    Mutant("batchcount1001", B, LIMIT, "BatchLimit(maximumRecordCount: 1_001, maximumByteCount: 1_000_000, maximumRecordByteCount: 1_000_000)"),
    Mutant("batchcount999", B, LIMIT, "BatchLimit(maximumRecordCount: 999, maximumByteCount: 1_000_000, maximumRecordByteCount: 1_000_000)"),
    Mutant("batchbytes1000001", B, LIMIT, "BatchLimit(maximumRecordCount: 1_000, maximumByteCount: 1_000_001, maximumRecordByteCount: 1_000_000)"),
    Mutant("batchbytes999999", B, LIMIT, "BatchLimit(maximumRecordCount: 1_000, maximumByteCount: 999_999, maximumRecordByteCount: 1_000_000)"),
    Mutant("recordbytes999999", B, LIMIT, "BatchLimit(maximumRecordCount: 1_000, maximumByteCount: 1_000_000, maximumRecordByteCount: 999_999)"),
    Mutant("recordbytes999966", B, LIMIT, "BatchLimit(maximumRecordCount: 1_000, maximumByteCount: 1_000_000, maximumRecordByteCount: 999_966)"),
    Mutant("oversizedbytecount", B, ".oversized(byteCount: byteCount)", "HeapEncodingError.oversized(byteCount: 0)"),
    Mutant("limitignored", B, "self.limit = limit", "self.limit = HeapBatchEncoder.batchLimit", mode="stmt"),

    # The setup checks and the envelope.
    Mutant("untrimmedappid", B, "appID.trimmingCharacters(in: .whitespacesAndNewlines)", "appID"),
    Mutant("emptyappid", B, "!appID.isEmpty", "true"),
    Mutant("anyappid", B, '(UInt8(ascii: "0") ... UInt8(ascii: "9")).contains($0)', "true"),
    Mutant("digitsfrom1", B, 'UInt8(ascii: "0")', 'UInt8(ascii: "1")'),
    Mutant("digitsto8", B, 'UInt8(ascii: "9")', 'UInt8(ascii: "8")'),
    Mutant("appidkey", B, 'envelope = JSONEnvelope(["app_id": .string(appID)], arrayMember: "events")', 'envelope = JSONEnvelope(["appId": .string(appID)], arrayMember: "events")', mode="stmt"),
    Mutant("eventsmember", B, 'envelope = JSONEnvelope(["app_id": .string(appID)], arrayMember: "events")', 'envelope = JSONEnvelope(["app_id": .string(appID)], arrayMember: "batch")', mode="stmt"),
    Mutant("barearray", B, 'envelope = JSONEnvelope(["app_id": .string(appID)], arrayMember: "events")', "envelope = .array", mode="stmt"),
    Mutant("usendpoint", F, '"https://heapanalytics.com/api/track"', '"https://heapanalytics.com/api/track/bulk"'),
    Mutant("euendpoint", F, '"https://c.eu.heap-api.com/api/track"', '"https://heapanalytics.com/api/track"'),
    Mutant("bootstrappedinstrument", F, "NoOpInstrument()", "InstrumentationSystem.instrument"),

    # The name and length rules.
    Mutant("eventname1023", N, "utf16.count <= 1_024", "utf16.count < 1_024"),
    Mutant("eventname1025", N, "utf16.count <= 1_024", "utf16.count <= 1_025"),
    Mutant("eventnamescalars", N, "utf16.count <= 1_024", "unicodeScalars.count <= 1_024"),
    # The second occurrence, in fitsHeapProperty: the first is eventname1023's replacement.
    Mutant("property1024", N, "utf16.count < 1_024", "utf16.count <= 1_024", nth=1),
    Mutant("property1023", N, "utf16.count < 1_024", "utf16.count < 1_023", nth=1),
    Mutant("propertyscalars", N, "utf16.count < 1_024", "unicodeScalars.count < 1_024", nth=1),
    Mutant("propertybytes", N, "utf16.count < 1_024", "utf8.count < 1_024", nth=1),
    Mutant("nouserid", N, 'self == "user_id"', "false"),
    Mutant("nosessionid", N, 'self == "session_id"', "false"),
    Mutant("noscreenname", N, 'self == "screen_name"', "false"),
    Mutant("reservedanycase", N, 'self == "user_id"', 'lowercased() == "user_id"'),
    Mutant("reservedprefix", N, 'self == "screen_name"', 'hasPrefix("screen_name")'),

    # The skipped records and their order.
    # The second occurrence, after a record is read; the first is in the reader's catch.
    Mutant("namenotchecked", B, "try record.checkHeapName()", "", mode="stmt", nth=1),
    Mutant("namecheckedwhenunknown", B, NAME_CHECK_ON_FAILURE, "try record.checkHeapName()", mode="stmt"),
    Mutant("namenotcheckedonfailure", B, NAME_CHECK_ON_FAILURE, "", mode="stmt"),
    # The second occurrence, in checkHeapName: the first is the initializer's notice.
    Mutant("invalideventname", B, "name.isHeapEventName", "true", nth=1),
    Mutant("collisionkey", B, "error.key", '""'),
    Mutant("descendingnames", B, "$0.utf8.lexicographicallyPrecedes($1.utf8)", "$1.utf8.lexicographicallyPrecedes($0.utf8)"),
    Mutant("noreserved", B, "names.first(where: \\.isReservedByHeap)", "nil"),
    Mutant("nolongname", B, "names.first(where: { !$0.fitsHeapProperty })", "nil"),
    Mutant("nolongvalue", B, "!value.fitsHeapProperty", "false"),
    Mutant("valuepropertyname", B, "throw .propertyValueTooLong(event: record.name, property: name, length: value.utf16.count)", 'throw .propertyValueTooLong(event: record.name, property: "", length: value.utf16.count)', mode="stmt"),
    # The second occurrence, the original; the first is valuepropertyname's replacement.
    Mutant("valuelengthcharacters", B, "value.utf16.count", "value.count", nth=1),
    Mutant("noearliest", B, "seconds >= Self.earliestSeconds", "true"),
    Mutant("noend", B, "seconds < Self.endSeconds", "true"),
    Mutant("earliestexclusive", B, "seconds >= Self.earliestSeconds", "seconds > Self.earliestSeconds"),
    Mutant("endinclusive", B, "seconds < Self.endSeconds", "seconds <= Self.endSeconds"),
    Mutant("earliestyear0", B, "-62_135_596_800", "-62_167_219_200"),
    Mutant("endyear9998", B, "253_402_300_800", "253_370_764_800"),
    Mutant("sensitivesent", B, "read = try reader.properties(of: record, includingSensitiveValues: false)", "read = try reader.properties(of: record, includingSensitiveValues: record.revealsSensitiveValues)", mode="stmt"),

    # The event's members and values.
    Mutant("nullssent", B, 'read.flattened(separator: ".").compactMapValues(\\.heapValue)', 'read.flattened(separator: ".").mapValues { $0.heapValue ?? .null }'),
    # The second occurrence, the original; the first is nullssent's replacement.
    Mutant("underscoreseparator", B, 'read.flattened(separator: ".")', 'read.flattened(separator: "_")', nth=1),
    Mutant("booleanskept", B, '.string(value ? "true" : "false")', "JSON.boolean(value)"),
    Mutant("booleansswapped", B, 'value ? "true" : "false"', 'value ? "false" : "true"'),
    Mutant("emptypropertiessent", B, "!properties.isEmpty", "true"),
    Mutant("nopropertiessent", B, 'event["properties"] = .object(properties)', "", mode="stmt"),
    Mutant("eventempty", B, ".string(record.name)", '.string("")'),
    Mutant("identityrecord", B, "record.pseudonymousIdentity.uuid.uuidString.lowercased()", "record.deduplicationID"),
    Mutant("identityupper", B, "record.pseudonymousIdentity.uuid.uuidString.lowercased()", "record.pseudonymousIdentity.uuid.uuidString"),
    Mutant("keyidentity", B, ".string(record.deduplicationID)", ".string(record.pseudonymousIdentity.uuid.uuidString.lowercased())"),
    Mutant("timestampepoch", B, ".string(timestamp)", ".string(String(record.timestamp.timeIntervalSince1970))"),
]
