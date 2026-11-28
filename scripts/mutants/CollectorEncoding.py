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
# - The decoder's `records.reserveCapacity(items.count)` removed: capacity only.
# - The CBOR writer and ISO 8601 parser the decoder reads through live in PropertyJSON, whose spec
#   plants them with these tests among its own.
# - The decoder's `Int(exactly: version)` made `Int(truncatingIfNeeded: version)`: a JSON integer
#   is an Int64, which a 64-bit Int always holds, so only a 32-bit Int (arm64_32, where no test
#   runs) tells them apart. pastInt32 in CollectorEventVersionTests pins both outcomes.

TESTS = ["CollectorEncodingTests"]

B = "CollectorBatchEncoder.swift"
C = "EventRecord+CollectorContext.swift"
DEC = "CollectorBatchDecoder.swift"
CTX = "ServiceContext+CollectorContext.swift"

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
    # CollectorBatchDecoder: the body.
    Mutant("decodenotjsonasobject", DEC, "throw .notJSON", "throw NotACollectorBatch.notAnObject", mode="stmt"),
    Mutant("decodemissingasnotarray", DEC, "throw .missingRecords", "throw NotACollectorBatch.recordsNotAnArray", mode="stmt"),
    # Expressions rather than statements where a guard binds a name the code after it reads.
    Mutant("decoderecordsanyvalue", DEC, "member.array", "Optional(member.array ?? [])"),
    Mutant("decodereportoffsetzero", DEC, "undecodedRecords.append(UndecodedRecord(offset: offset, recordID: item.recordID, eventName: item.eventName, reason: error))", "undecodedRecords.append(UndecodedRecord(offset: 0, recordID: item.recordID, eventName: item.eventName, reason: error))", mode="stmt"),
    Mutant("decodeundecodedunreported", DEC, "undecodedRecords.append(UndecodedRecord(offset: offset, recordID: item.recordID, eventName: item.eventName, reason: error))", "", mode="stmt"),
    # The first copies are decodereportoffsetzero's, the second batch(from:)'s report's, the third
    # record(from:)'s guard.
    Mutant("decodereportnoid", DEC, "item.recordID", "UUID?.none", nth=1),
    Mutant("decodereportnoname", DEC, "item.eventName", "String?.none", nth=1),
    # The record's members.
    Mutant("decodefreshid", DEC, "item.recordID", "Optional(UUID())", nth=2),
    Mutant("decodetimestampignored", DEC, 'members["timestamp"]?.string.flatMap(Date.init(iso8601Timestamp:))', "Optional(Date(timeIntervalSince1970: 0))"),
    Mutant("decodeneverredelivered", DEC, 'members["isRedelivered"]', "Optional(JSON.boolean(false))"),
    Mutant("decodecontextdropped", DEC, "ServiceContext(collectorContext: context, instrument: instrument)", "ServiceContext.topLevel"),
    Mutant("decodeconcealed", DEC, "record.revealsSensitiveValues = true", "", mode="stmt"),
    Mutant("decodeunknowneventunnamed", DEC, "throw .unknownEvent(name: name)", 'throw CollectorDecodingError.unknownEvent(name: "")', mode="stmt"),
    Mutant("decodepropertyunnamed", DEC, "error.property", '""'),
    # The plan and the types, by name and version (TRAF-151).
    # In this order: the first's replacement doesn't hold the text the second matches, which the
    # other way round would occur twice.
    Mutant("decodeversionunchecked", DEC, "schemas[version].map { DecodableEvent(type: type, propertyTypes: $0.propertyTypes) }", "Optional(DecodableEvent(type: type, propertyTypes: schemas[version]?.propertyTypes ?? [:]))"),
    Mutant("decodeplanversionignored", DEC, "schemas[version].map", "schemas[PlannedVersion(name: version.name, version: 1)].map"),
    Mutant("decodereportedversionone", DEC, "throw .unknownVersion(name: name, version: version)", "throw CollectorDecodingError.unknownVersion(name: name, version: 1)", mode="stmt"),
    # The first copy is the duplicate check's; the second, an assignment, isn't an expression.
    Mutant("decodeduplicatebyname", DEC, "listed[version]", "listed.first(where: { $0.key.name == version.name })?.value", nth=0),
    Mutant("decodeduplicatesallowed", DEC, "listed[version] = type", "", mode="stmt"),
    # The first copy is the error's, before the readable versions' subscript.
    Mutant("decodeduplicateversionone", DEC, "version.version", "1", nth=0),
    Mutant("decodeduplicatetypesswapped", DEC, "String(reflecting: first)", "String(reflecting: type)"),
    # The record's version member.
    Mutant("decodestatedignored", DEC, "statedVersion ?? versions.unstatedVersion", "versions.unstatedVersion"),
    Mutant("decodeunstatedalwaysone", DEC, "statedVersion ?? versions.unstatedVersion", "statedVersion ?? 1"),
    Mutant("decodeunstatedastwo", DEC, "statedVersion = nil", "statedVersion = 2", mode="stmt"),
    Mutant("decodeunstatednewest", DEC, "readable[1] != nil ? 1 : readable.keys.min() ?? 1", "readable.keys.max() ?? 1"),
    Mutant("decodeunstatedlowest", DEC, "readable[1] != nil ? 1 : readable.keys.min() ?? 1", "readable.keys.min() ?? 1"),
    Mutant("decodeunstatednonezero", DEC, "readable[1] != nil ? 1 : readable.keys.min() ?? 1", "readable[1] != nil ? 1 : readable.keys.min() ?? 0"),
    # The second copy is the catch-all case's, after the guard's past a 32-bit Int.
    Mutant("decodemalformedversionasabsent", DEC, 'throw .malformedMember("version")', "statedVersion = nil", nth=1, mode="stmt"),
    Mutant("versionwrittenasone", B, ".integer(Int64(version.version))", ".integer(1)"),
    Mutant("versionrenamed", B, '"version"', '"schemaVersion"'),
    Mutant("decodenothingdiscovered", DEC, "DiscoveredEvent.all.map { $0.type }", "DiscoveredEvent.all.prefix(0).map { $0.type }"),
    # The context.
    Mutant("decodeapplicationdropped", CTX, "context[ApplicationKey.self] = ApplicationKey.Value(bundleIdentifier: bundleIdentifier, version: version, build: build)", "", mode="stmt"),
    Mutant("decodebuildasversion", CTX, "ApplicationKey.Value(bundleIdentifier: bundleIdentifier, version: version, build: build)", "ApplicationKey.Value(bundleIdentifier: bundleIdentifier, version: version, build: version)"),
    Mutant("decodeapplicationnonstrings", CTX, "value.string.map(Optional.some)", "Optional.some(value.string)"),
    Mutant("decodedevicedropped", CTX, "context[DeviceKey.self] = DeviceKey.Value(model: model, formFactor: formFactor)", "", mode="stmt"),
    Mutant("decodelocaledropped", CTX, "context[LocaleKey.self] = Locale(identifier: identifier)", "", mode="stmt"),
    Mutant("decodenetworkdropped", CTX, "context[NetworkKey.self] = value", "", mode="stmt"),
    Mutant("decodeosdropped", CTX, "context[OperatingSystemKey.self] = OperatingSystemKey.Value(name: name, version: version)", "", mode="stmt"),
    Mutant("decodesampleratedropped", CTX, "context[SampleRateKey.self] = rate", "", mode="stmt"),
    Mutant("decodesessiondropped", CTX, "context[SessionKey.self] = key", "", mode="stmt"),
    Mutant("decodevendordropped", CTX, "context[VendorIdentifierKey.self] = Sensitive(identifier)", "", mode="stmt"),
    Mutant("decodetracenotextracted", CTX, "instrument.extract(fields, into: &context, using: DictionaryExtractor())", "", mode="stmt"),
    Mutant("decodetraceanyvalue", CTX, "trace.object", "Optional(trace.object ?? [:])"),
    # The first copy is the trace loop's, before optionalString's.
    Mutant("decodetracenonstrings", CTX, "value.string", 'Optional(value.string ?? "")', nth=0),
    # The first is the form factor's, the second the network's.
    Mutant("decodeanyformfactor", CTX, "Self.allCases.first(where: { $0.collectorName == name })", "Self.allCases.first", nth=0),
    Mutant("decodeanynetwork", CTX, "Self.allCases.first(where: { $0.collectorName == name })", "Self.allCases.first", nth=1),
]
