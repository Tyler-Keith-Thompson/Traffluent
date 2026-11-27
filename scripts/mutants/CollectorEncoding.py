# Planted bugs for CollectorEncoding; run with `just mutate CollectorEncoding`. See scripts/mutate.py.
#
# Each mutant is Mutant(name, file, old, new), where `old` occurs once in
# Sources/CollectorEncoding/<file> (or `nth=` picks one), and mode="stmt" replaces whole
# statements rather than an expression. `module=` puts a mutant in another module's file: here
# JSONValues' JSON.minified, which only this module's body reaches. Every mutant must be caught;
# one that survives needs a test, or a note here saying why it is equivalent.
#
# Known equivalent mutants (left out, as they would survive by design):
# - `records.reserveCapacity(batch.count)` removed: capacity only.
# - The property reader, propertyTypes and properties(types:writingSensitiveValues:) live in
#   PropertyJSON, whose spec plants them with these tests among its own.
# - The unknownEvent arm of `CollectorEncodingError.init(_ error: PropertyReadingError)` mapped to
#   another case: the encoder looks the event up in the plan itself and reads it through
#   `properties(types:writingSensitiveValues:)`, which never throws unknownEvent.

TESTS = ["CollectorEncodingTests"]

B = "CollectorBatchEncoder.swift"
C = "EventRecord+CollectorContext.swift"

MUTANTS = [
    # The record's envelope.
    Mutant("freshid", B, "record.id.uuidString", "UUID().uuidString"),
    Mutant("neverredelivered", B, "record.isRedelivered", "false"),
    Mutant("textcontenttype", B, '"application/json"', '"text/plain"'),
    Mutant("firstrecorddropped", B, "records.append(try json(of: record))", "if record.id != batch.first?.id { records.append(try json(of: record)) }", mode="stmt"),
    # Skipped records.
    Mutant("skipnotreported", B, "skippedRecords.append(SkippedRecord(recordID: record.id, eventName: record.name, schemaVersion: type(of: record.event).schemaVersion, reason: error))", "", mode="stmt"),
    Mutant("skipversionignored", B, "type(of: record.event).schemaVersion", "1", nth=0),
    Mutant("allskippedsent", B, "!records.isEmpty || batch.isEmpty", "true"),
    Mutant("emptybatchnobody", B, "!records.isEmpty || batch.isEmpty", "!records.isEmpty"),
    # requests(for:): the one request of batch(of:)'s body, naming only the records it holds.
    Mutant("skippedidssent", B, "batch.map(\\.id).filter { !skipped.contains($0) }", "batch.map(\\.id)"),
    # The first copy is the return for a batch with no body, the third the request's.
    Mutant("allskippedunreported", B, "encoded.skippedRecords", "[]", nth=0),
    Mutant("skipsunreported", B, "encoded.skippedRecords", "[]", nth=2),
    # The second: json(of:)'s plan lookup, after batch(of:)'s skipped record.
    Mutant("versionignored", B, "type(of: record.event).schemaVersion", "1", nth=1),
    # The second revealsSensitiveValues: the call's, after the doc comment's.
    Mutant("alwaysreveals", B, "revealsSensitiveValues", "true", nth=1),
    Mutant("neverreveals", B, "revealsSensitiveValues", "false", nth=1),
    Mutant("timestampjulian", B, "timestamp = try record.timestamp.iso8601Timestamp", "timestamp = record.timestamp.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true))", mode="stmt"),
    Mutant("unrepresentabletimestampsent", B, "throw .unrepresentableTimestamp", 'timestamp = "1970-01-01T00:00:00.000Z"', mode="stmt"),
    Mutant("notencodableasunrepresentable", B, ".notEncodable(name: name)", 'CollectorEncodingError.unrepresentableValue(event: name, property: "")'),
    Mutant("propertyunnamed", B, ".unrepresentableValue(event: event, property: property)", '.unrepresentableValue(event: event, property: "")'),
    # Context.
    Mutant("applicationabbreviated", C, '"application"', '"app"'),
    Mutant("applicationnilasnull", C, "application.build.map(JSON.string)", "Optional.some(application.build.map(JSON.string) ?? JSON.null)"),
    Mutant("padasphone", C, '"pad"', '"phone"'),
    Mutant("ethernetrenamed", C, '"wiredEthernet"', '"ethernet"'),
    Mutant("localeidentifier", C, "locale.identifier(.bcp47)", "locale.identifier"),
    Mutant("nosamplerate", C, 'members["sampleRate"] = rate', "", mode="stmt"),
    Mutant("nosession", C, 'members["session"] = .string(session.uuidString)', "", mode="stmt"),
    Mutant("vendoridentifierunredacted", C, "context[VendorIdentifierKey.self].flatMap(reveal)", "context[VendorIdentifierKey.self]?.value"),
    Mutant("emptytrace", C, "!trace.isEmpty", "true"),
    Mutant("notrace", C, 'members["trace"] = .object(trace.mapValues(JSON.string))', "", mode="stmt"),
    # TrackingPlans' minified rendering.
    # The second "," in JSON.swift: minified's separator between an object's members.
    Mutant("minifiedspaced", "JSON.swift", '","', '", "', nth=1, module="JSONValues"),
    Mutant("minifiedcolonspaced", "JSON.swift", '":"', '": "', module="JSONValues"),
    # The second sort in JSON.swift is minified's.
    Mutant("minifiedunsorted", "JSON.swift", "$0.key.utf8.lexicographicallyPrecedes($1.key.utf8)", "$1.key.utf8.lexicographicallyPrecedes($0.key.utf8)", nth=1, module="JSONValues"),
]
