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
# - The logger.error line in encode(_:) removed: logs are for developers, and tests don't pin them.
# - The logger.notice line for a dropped property removed: the same.
# - The properties PropertyJSON reads (its PropertyReader, propertyTypes and
#   properties(types:writingSensitiveValues:)): PropertyJSON's spec plants those.

TESTS = ["PostHogEncodingTests"]

B = "PostHogBatchEncoder.swift"
C = "EventRecord+PostHogContext.swift"
D = "Date+PostHogTimestamp.swift"

MUTANTS = [
    # $session_id from the v7 SessionKey (TRAF-74).
    Mutant("nosessionid", "PostHogBatchEncoder.swift", 'properties["$session_id"] = .string(session.uuidString.lowercased())', 'properties["$session_id"] = nil', mode="stmt"),
    Mutant("sessionidbeforeproperties", "PostHogBatchEncoder.swift", 'properties["$session_id"] = .string(session.uuidString.lowercased())', 'properties["$session_id"] = .string(session.uuidString)', mode="stmt"),

    # The request's envelope.
    Mutant("emptyapikey", B, ".string(projectToken)", '.string("")'),
    Mutant("batchrenamed", B, '"batch"', '"events"'),
    Mutant("textcontenttype", B, '"application/json"', '"text/plain"'),
    Mutant("wholeseconds", D, "true", "false"),
    # Each event's members.
    Mutant("freshuuid", B, "record.id.uuidString.lowercased()", "UUID().uuidString.lowercased()"),
    Mutant("uuiduppercase", B, "record.id.uuidString.lowercased()", "record.id.uuidString"),
    # Identity: the session, or the record's own id.
    Mutant("distinctiduppercase", B, "identifier.uuidString.lowercased()", "identifier.uuidString"),
    Mutant("sessionignored", B, "context[SessionKey.self] ?? id", "id"),
    Mutant("freshfallback", B, "context[SessionKey.self] ?? id", "context[SessionKey.self] ?? UUID()"),
    Mutant("distinctidisrecord", B, ".string(distinctID)", ".string(record.id.uuidString.lowercased())"),
    # Forced and dropped properties.
    Mutant("personprofiles", B, 'properties["$process_person_profile"] = .boolean(false)', "", mode="stmt"),
    Mutant("geoip", B, 'properties["$geoip_disable"] = .boolean(true)', "", mode="stmt"),
    Mutant("sensitivewritten", B, "properties = try record.properties(types: types, writingSensitiveValues: false)", "properties = try record.properties(types: types, writingSensitiveValues: record.revealsSensitiveValues)", mode="stmt"),
    Mutant("dollarkept", B, 'key.hasPrefix("$")', "false"),
    Mutant("distinctidkept", B, 'key == "distinct_id"', "false"),
    Mutant("droppedkept", B, "properties[key] = nil", "", mode="stmt"),
    Mutant("nocontext", B, "properties[key] = value", "", mode="stmt"),
    # Skipped records.
    Mutant("reservednameaccepted", B, '!record.name.hasPrefix("$")', "true"),
    Mutant("skipnotreported", B, "skippedRecords.append(PostHogSkippedRecord(recordID: record.id, eventName: record.name, schemaVersion: type(of: record.event).schemaVersion, reason: error))", "", mode="stmt"),
    Mutant("skipversionignored", B, "type(of: record.event).schemaVersion", "1", nth=0),
    Mutant("versionignored", B, "type(of: record.event).schemaVersion", "1", nth=1),
    Mutant("allskippedsent", B, "!events.isEmpty || batch.isEmpty", "true"),
    Mutant("emptybatchnobody", B, "!events.isEmpty || batch.isEmpty", "!events.isEmpty"),
    Mutant("lastskipthrown", B, "throw encoded.skippedRecords[0].reason", "throw encoded.skippedRecords[encoded.skippedRecords.count - 1].reason", mode="stmt"),
    Mutant("propertyunnamed", B, ".unrepresentableValue(event: event, property: property)", '.unrepresentableValue(event: event, property: "")'),
    Mutant("notbinarycodableasunknown", B, ".notBinaryCodable(name: name)", "PostHogEncodingError.unknownEvent(name: name, version: 1)"),
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
