# Planted bugs for PostHogEncoding; run with `just mutate PostHogEncoding`. See scripts/mutate.py.
#
# Each mutant is Mutant(name, file, old, new), where `old` occurs once in
# Sources/PostHogEncoding/<file> (or `nth=` picks one), and mode="stmt" replaces whole
# statements rather than an expression. Mutants are applied in this order, so one whose `old`
# holds another's comes first. Every mutant must be caught; one that survives needs a test, or a
# note here saying why it is equivalent.
#
# Known equivalent mutants (left out, as they would survive by design):
# - `events.reserveCapacity(batch.count)` removed: capacity only.
# - The logger.notice line for a dropped property removed: the same.
# - The properties PropertyJSON reads (its PropertyReader, propertyTypes and
#   properties(types:writingSensitiveValues:)), its identity, timestamps and batch splitting:
#   PropertyJSON's spec plants those.
# - The unknownEvent arm of `PostHogEncodingError.init(_ error: PropertyReadingError)` mapped to
#   another case: the catch in json(of:) only reaches it for an event the plan doesn't describe,
#   and the unknownEvent tests pin the case it maps to.
# - The factory's `backoff:` and `clock:` arguments: a mutant switch can't hold an argument, and
#   without them the destination would use the default backoff, which only slows the retry check.
#   Its instrument is a constant of its own, so `bootstrappedinstrument` reaches it.

TESTS = ["PostHogEncodingTests"]

B = "PostHogBatchEncoder.swift"
C = "EventRecord+PostHogContext.swift"
F = "HTTPDestination+PostHog.swift"

MUTANTS = [
    # $session_id from the v7 SessionKey (TRAF-74).
    Mutant("nosessionid", "PostHogBatchEncoder.swift", 'properties["$session_id"] = .string(session.uuidString.lowercased())', 'properties["$session_id"] = nil', mode="stmt"),
    Mutant("sessionidbeforeproperties", "PostHogBatchEncoder.swift", 'properties["$session_id"] = .string(session.uuidString.lowercased())', 'properties["$session_id"] = .string(session.uuidString)', mode="stmt"),

    # The request's envelope.
    Mutant("emptyapikey", B, ".string(projectToken)", '.string("")'),
    Mutant("batchrenamed", B, '"batch"', '"events"'),
    Mutant("utcoffset", B, "timestamp = try record.timestamp.iso8601Timestamp", "timestamp = record.timestamp.formatted(.iso8601)", mode="stmt"),
    Mutant("unrepresentabletimestampsent", B, "throw .unrepresentableTimestamp", 'timestamp = "1970-01-01T00:00:00.000Z"', mode="stmt"),
    # Each event's members.
    Mutant("freshuuid", B, ".string(record.deduplicationID)", ".string(UUID().uuidString.lowercased())"),
    # Identity: the session, or the record's own id.
    Mutant("distinctiduppercase", B, ".string(identity.uuid.uuidString.lowercased())", ".string(identity.uuid.uuidString)"),
    Mutant("distinctidisrecord", B, ".string(identity.uuid.uuidString.lowercased())", ".string(record.deduplicationID)"),
    # Forced and dropped properties.
    Mutant("personprofiles", B, 'properties["$process_person_profile"] = .boolean(false)', "", mode="stmt"),
    Mutant("geoip", B, 'properties["$geoip_disable"] = .boolean(true)', "", mode="stmt"),
    Mutant("sensitivewritten", B, "properties = try reader.properties(of: record, includingSensitiveValues: false)", "properties = try reader.properties(of: record, includingSensitiveValues: true)", mode="stmt"),
    Mutant("dollarkept", B, 'key.hasPrefix("$")', "false"),
    Mutant("distinctidkept", B, 'key == "distinct_id"', "false"),
    Mutant("droppedkept", B, "properties[key] = nil", "", mode="stmt"),
    Mutant("nocontext", B, "properties[key] = value", "", mode="stmt"),
    # Skipped records.
    Mutant("reservednameaccepted", B, '!record.name.hasPrefix("$")', "true"),
    # The first copy is the catch's: a $-named event the reader can't read.
    Mutant("reservedafterreaderror", B, 'record.name.hasPrefix("$")', "false", nth=0),
    Mutant("propertyunnamed", B, ".unrepresentableValue(event: event, property: property)", '.unrepresentableValue(event: event, property: "")'),
    Mutant("notencodableasunknown", B, ".notEncodable(name: name)", "PostHogEncodingError.unknownEvent(name: name, version: 1)"),
    Mutant("oversizedsizedropped", B, ".oversized(byteCount: byteCount)", ".oversized(byteCount: 0)"),
    Mutant("limitignored", B, "self.limit = limit", "self.limit = .unlimited", mode="stmt"),
    Mutant("requestlimitwrong", B, "10_000_000", "20_000_000"),
    Mutant("eventlimitwrong", B, "1_000_000", "2_000_000"),
    # The factory.
    Mutant("emptytokenaccepted", F, "!projectToken.isEmpty", "true"),
    Mutant("untrimmedtoken", F, "projectToken.trimmingCharacters(in: .whitespacesAndNewlines)", "projectToken"),
    Mutant("personalkeyaccepted", F, '!projectToken.hasPrefix("phx_")', "true"),
    Mutant("httpaccepted", F, 'components.scheme?.lowercased() == "https"', "true"),
    Mutant("schemecasesensitive", F, 'components.scheme?.lowercased() == "https"', 'components.scheme == "https"'),
    Mutant("nohostaccepted", F, "components.percentEncodedHost?.isEmpty == false", "true"),
    Mutant("useraccepted", F, "components.percentEncodedUser == nil", "true"),
    Mutant("queryaccepted", F, "components.percentEncodedQuery == nil", "true"),
    Mutant("fragmentaccepted", F, "components.percentEncodedFragment == nil", "true"),
    Mutant("batchhostaccepted", F, 'path.split(separator: "/").last != "batch"', "true"),
    Mutant("pathdropped", F, 'components.percentEncodedPath = path + "/batch/"', 'components.percentEncodedPath = "/batch/"', mode="stmt"),
    # The first copy is the read, before pathdropped's two.
    Mutant("pathdecoded", F, "components.percentEncodedPath", "components.path", nth=0),
    Mutant("bootstrappedinstrument", F, "NoOpInstrument()", "InstrumentationSystem.instrument"),
    Mutant("trailingslashkept", F, "path.removeLast()", "break", mode="stmt"),
    # The second copy is the original's, after pathdropped's.
    Mutant("noslashafterbatch", F, '"/batch/"', '"/batch"', nth=1),
    # Context.
    Mutant("nobundleidentifier", C, 'properties["$app_namespace"] = .string(bundleIdentifier)', "", mode="stmt"),
    Mutant("versionasbuild", C, 'properties["$app_version"] = .string(version)', 'properties["$app_build"] = .string(version)', mode="stmt"),
    Mutant("nobuild", C, 'properties["$app_build"] = .string(build)', "", mode="stmt"),
    Mutant("nodevicemodel", C, 'properties["$device_model"] = .string(device.model)', "", mode="stmt"),
    Mutant("padasmobile", C, '"Tablet"', '"Mobile"'),
    Mutant("desktoprenamed", C, '"Desktop"', '"Mac"'),
    Mutant("tvrenamed", C, '"TV"', '"Television"'),
    Mutant("visionrenamed", C, '"Vision"', '"Headset"'),
    # The second `nil` in the file: the watch's, after the doc comment's.
    Mutant("watchtyped", C, "nil", '"Watch"', nth=1),
    Mutant("localeidentifier", C, "locale.identifier(.bcp47)", "locale.identifier"),
    Mutant("ethernetaswifi", C, "network == .wifi", "network != .cellular"),
    Mutant("nocellular", C, 'properties["$network_cellular"] = .boolean(network == .cellular)', "", mode="stmt"),
    Mutant("noosname", C, 'properties["$os_name"] = .string(operatingSystem.name)', "", mode="stmt"),
    Mutant("noosversion", C, 'properties["$os_version"] = .string(operatingSystem.version)', "", mode="stmt"),
]
