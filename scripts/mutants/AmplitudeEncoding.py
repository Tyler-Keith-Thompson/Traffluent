# Planted bugs for AmplitudeEncoding; run with `just mutate AmplitudeEncoding`. See scripts/mutate.py.
#
# Each mutant is Mutant(name, file, old, new), where `old` occurs once in
# Sources/AmplitudeEncoding/<file> (or `nth=` picks one), and mode="stmt" replaces whole
# statements rather than an expression. Mutants are applied in this order, so one whose `old`
# holds another's comes first. Every mutant must be caught; one that survives needs a test, or a
# note here saying why it is equivalent.
#
# Known equivalent mutants (left out, as they would survive by design):
# - The limit's `maximumRecordByteCount: 1_000_000` raised: it equals `maximumByteCount`, and a
#   record also has to fit in a request beside the envelope, so the request's bytes bind first.
# - The properties PropertyJSON reads (its PropertyReader), its identity, timestamps and batch
#   splitting: PropertyJSON's spec plants those.
# - The unknownEvent arm of `AmplitudeEncodingError.init(_ error: PropertyReadingError)` mapped to
#   another case: the catch in json(of:) only reaches it for an event the plan doesn't describe,
#   and the unknownEvent tests pin the case it maps to.
# - The factory's `backoff:` and `clock:` arguments: a mutant switch can't hold an argument, and
#   without them the destination would use the default backoff, which only slows the retry check.
#   Its instrument is a constant of its own, so `bootstrappedinstrument` reaches it.
# - The endpoints' `?? URL(fileURLWithPath: "/")` fallbacks: the literals always parse.

TESTS = ["AmplitudeEncodingTests"]

B = "AmplitudeBatchEncoder.swift"
C = "EventRecord+AmplitudeContext.swift"
F = "HTTPDestination+Amplitude.swift"

MUTANTS = [
    # The request's envelope.
    Mutant("emptyapikey", B, ".string(apiKey)", '.string("")'),
    Mutant("eventsrenamed", B, '"events"', '"batch"'),
    # Each event's members.
    Mutant("freshinsertid", B, ".string(record.deduplicationID)", ".string(UUID().uuidString.lowercased())"),
    Mutant("eventtypeempty", B, ".string(record.name)", '.string("")'),
    Mutant("noeventproperties", B, 'event["event_properties"] = .object(properties)', "", mode="stmt"),
    Mutant("timeinseconds", B, ".integer(time)", ".integer(time / 1_000)"),
    Mutant("timestampzeroed", B, "throw .unrepresentableTimestamp", "time = 0", mode="stmt"),
    # Identity: the session, or the record's own id, and never a user_id. useridsent first, as its
    # statement holds the expression the next two change.
    Mutant("useridsent", B, 'event["device_id"] = .string(identity.uuid.uuidString.lowercased())', 'event["user_id"] = .string(identity.uuid.uuidString.lowercased())', mode="stmt"),
    Mutant("deviceiduppercase", B, ".string(identity.uuid.uuidString.lowercased())", ".string(identity.uuid.uuidString)", nth=1),
    Mutant("deviceidisrecord", B, ".string(identity.uuid.uuidString.lowercased())", ".string(record.deduplicationID)", nth=1),
    Mutant("sensitivewritten", B, "properties = try reader.properties(of: record, includingSensitiveValues: false)", "properties = try reader.properties(of: record, includingSensitiveValues: true)", mode="stmt"),
    # session_id from the v7 SessionKey.
    Mutant("nosessionid", B, 'event["session_id"] = .integer(start)', "", mode="stmt"),
    Mutant("sessionidseconds", B, ".integer(start)", ".integer(start / 1_000)"),
    Mutant("anyversion", B, "bytes.6 >> 4 == 7", "true"),
    Mutant("anyvariant", B, "bytes.8 >> 6 == 0b10", "true"),
    Mutant("shiftwrong", B, "milliseconds << 8", "milliseconds << 4"),
    Mutant("bytesshifted", B, "[bytes.0, bytes.1, bytes.2, bytes.3, bytes.4, bytes.5]", "[bytes.1, bytes.2, bytes.3, bytes.4, bytes.5, bytes.6]"),
    # The context.
    Mutant("nocontext", B, "record.amplitudeContext", "[String: JSON]()"),
    # Skipped records.
    # The catch's guard dropped, so a reserved name is reported before an event the plan doesn't
    # describe. First, as its statement holds the name check reservedafterreaderror changes.
    Mutant("reservedbeforeunknown", B,
           "if case .unknownEvent = error {} else if record.name.isReservedByAmplitude {\n                throw .reservedEventName(name: record.name)\n            }",
           "if record.name.isReservedByAmplitude {\n                throw .reservedEventName(name: record.name)\n            }",
           mode="stmt"),
    Mutant("reservednameaccepted", B, "!record.name.isReservedByAmplitude", "true"),
    # The second copy is the catch's, after reservedbeforeunknown's: a reserved event the reader
    # can't read.
    Mutant("reservedafterreaderror", B, "record.name.isReservedByAmplitude", "false", nth=1),
    Mutant("amplitudeprefixaccepted", B, 'hasPrefix("[Amplitude]")', "false"),
    Mutant("amplitudeprefixcaseless", B, 'hasPrefix("[Amplitude]")', 'lowercased().hasPrefix("[amplitude]")'),
    Mutant("identifyaccepted", B, 'self == "$identify"', "false"),
    Mutant("identifyprefix", B, 'self == "$identify"', 'hasPrefix("$identify")'),
    Mutant("groupidentifyaccepted", B, 'self == "$groupidentify"', "false"),
    Mutant("propertyunnamed", B, ".unrepresentableValue(event: event, property: property)", '.unrepresentableValue(event: event, property: "")'),
    Mutant("notencodableasunknown", B, ".notEncodable(name: name)", "AmplitudeEncodingError.unknownEvent(name: name, version: 1)"),
    Mutant("oversizedsizedropped", B, ".oversized(byteCount: byteCount)", ".oversized(byteCount: 0)"),
    Mutant("limitignored", B, "self.limit = limit", "self.limit = .unlimited", mode="stmt"),
    # The whole limit, as an expression mutant can't hold an argument label.
    Mutant("countlimitwrong", B, "(try? BatchLimit(maximumRecordCount: 10, maximumByteCount: 1_000_000, maximumRecordByteCount: 1_000_000)) ?? .unlimited", "(try? BatchLimit(maximumRecordCount: 2_000, maximumByteCount: 1_000_000, maximumRecordByteCount: 1_000_000)) ?? .unlimited"),
    Mutant("requestlimitwrong", B, "(try? BatchLimit(maximumRecordCount: 10, maximumByteCount: 1_000_000, maximumRecordByteCount: 1_000_000)) ?? .unlimited", "(try? BatchLimit(maximumRecordCount: 10, maximumByteCount: 2_000_000, maximumRecordByteCount: 1_000_000)) ?? .unlimited"),
    # The factory.
    Mutant("emptykeyaccepted", F, "!apiKey.isEmpty", "true"),
    Mutant("untrimmedkey", F, "apiKey.trimmingCharacters(in: .whitespacesAndNewlines)", "apiKey"),
    Mutant("clientkeyaccepted", F, '!apiKey.hasPrefix("client-")', "true"),
    Mutant("serverkeyaccepted", F, '!apiKey.hasPrefix("server-")', "true"),
    Mutant("deploymentkeycaseless", F, '!apiKey.hasPrefix("server-")', '!apiKey.lowercased().hasPrefix("server-")'),
    Mutant("bootstrappedinstrument", F, "NoOpInstrument()", "InstrumentationSystem.instrument"),
    # Before usaseu, which writes the EU endpoint a second time.
    Mutant("euasus", F, '"https://api.eu.amplitude.com/2/httpapi"', '"https://api2.amplitude.com/2/httpapi"'),
    Mutant("usaseu", F, '"https://api2.amplitude.com/2/httpapi"', '"https://api.eu.amplitude.com/2/httpapi"', nth=0),
    # Context.
    Mutant("noappversion", C, 'fields["app_version"] = .string(version)', "", mode="stmt"),
    Mutant("nodevicemodel", C, 'fields["device_model"] = .string(device.model)', "", mode="stmt"),
    Mutant("nolanguage", C, 'fields["language"] = .string(locale.identifier(.bcp47))', "", mode="stmt"),
    Mutant("localeidentifier", C, "locale.identifier(.bcp47)", "locale.identifier"),
    Mutant("noplatform", C, 'fields["platform"] = .string(operatingSystem.name)', "", mode="stmt"),
    Mutant("noosname", C, 'fields["os_name"] = .string(operatingSystem.name)', "", mode="stmt"),
    Mutant("osnameasversion", C, 'fields["os_name"] = .string(operatingSystem.name)', 'fields["os_name"] = .string(operatingSystem.version)', mode="stmt"),
    Mutant("noosversion", C, 'fields["os_version"] = .string(operatingSystem.version)', "", mode="stmt"),
]
