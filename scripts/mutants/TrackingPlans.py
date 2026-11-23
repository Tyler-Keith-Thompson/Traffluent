# Planted bugs for TrackingPlans; run with `just mutate TrackingPlans`. See scripts/mutate.py.
#
# Each mutant is Mutant(name, file, old, new), where `old` occurs once in Sources/TrackingPlans/<file>
# (or `nth=` picks one), and mode="stmt" replaces whole statements rather than an expression.
# Every mutant must be caught; one that survives needs a test, or a note here saying why it is
# equivalent to the original.
#
# Known equivalent mutants (left out, as they would survive by design):
# - Ordering names with String's `<` rather than by UTF-8 bytes: Swift compares strings by their
#   normalized scalars, the same order as their bytes for the NFC text every test can write.
# - The fallback CocoaError in `cocoa(_:)`: every error Foundation's file calls throw is a CocoaError
#   already, so no test can reach it.

TESTS = ["TrackingPlansTests"]

T = "TrackingPlan.swift"
J = "JSON.swift"
D = "EventSchema+Document.swift"
W = "WrittenType.swift"
F = "TrackingPlan+Write.swift"
C = "TrackingPlanCommand.swift"

MUTANTS = [
    # TrackingPlan: the rules, the order and the index.
    Mutant("emptynameallowed", T, "!schema.name.isEmpty", "true"),
    Mutant("duplicatepropertyallowed", T, "schema.hasDistinctPropertyNames", "true"),
    Mutant("duplicateeventallowed", T, "fileNames.insert(schema.fileName.lowercased()).inserted", "true"),
    Mutant("casesensitive", T, "schema.fileName.lowercased()", "schema.fileName"),
    Mutant("unsorted", T, "schemas.sorted(by: EventSchema.precedesInPlan)", "schemas"),
    Mutant("versionsreversed", T, "first.version < second.version", "first.version > second.version"),
    Mutant("namesreversed", T, "first.name.utf8.lexicographicallyPrecedes(second.name.utf8)", "second.name.utf8.lexicographicallyPrecedes(first.name.utf8)"),
    Mutant("noindex", T, "[File(path: TrackingPlan.indexFileName, json: index)]", "[]"),
    Mutant("indexrenamed", T, '"tracking-plan.json"', '"index.json"', nth=1),
    Mutant("indexversionfixed", T, ".integer(Int64(version))", ".integer(1)"),
    Mutant("indexcategoryfixed", T, '.string(consentCategory.name)', '.string("analytics")'),
    Mutant("indexschemaname", T, ".string(fileName)", ".string(name)"),
    Mutant("notrailingnewline", T, 'json.rendered + "\\n"', "json.rendered"),
    # JSON: the rendering.
    Mutant("emptyarraymultiline", J, "!elements.isEmpty", "true"),
    Mutant("emptyobjectmultiline", J, "!members.isEmpty", "true"),
    Mutant("arrayindentwide", J, 'indentation + "  "', 'indentation + "    "', nth=0),
    Mutant("objectindentwide", J, 'indentation + "  "', 'indentation + "    "', nth=1),
    Mutant("arraytrailingcomma", J, 'offset == elements.count - 1 ? "\\n" : ",\\n"', '",\\n"'),
    Mutant("objecttrailingcomma", J, 'offset == sorted.count - 1 ? "\\n" : ",\\n"', '",\\n"'),
    Mutant("keysreversed", J, "$0.key.utf8.lexicographicallyPrecedes($1.key.utf8)", "$1.key.utf8.lexicographicallyPrecedes($0.key.utf8)"),
    Mutant("colonspaced", J, '": "', '" : "'),
    Mutant("booleanalwaystrue", J, 'boolean ? "true" : "false"', '"true"'),
    Mutant("quoteunescaped", J, r'"\\\""', r'"\""'),
    Mutant("backslashunescaped", J, r'"\\\\"', r'"\\"'),
    Mutant("newlineraw", J, r'"\\n"', r'"\n"'),
    Mutant("controlnotpadded", J, "4 - hex.count", "2 - hex.count"),
    Mutant("controllowercase", J, "String(scalar.value, radix: 16, uppercase: true)", "String(scalar.value, radix: 16, uppercase: false)"),
    # EventSchema+Document: file names and documents.
    Mutant("everybyteunreserved", D, "byte.isUnreserved", "true"),
    Mutant("hexnotpadded", D, '(hex.count == 1 ? "0" : "")', '""'),
    Mutant("hexlowercase", D, "String(byte, radix: 16, uppercase: true)", "String(byte, radix: 16, uppercase: false)"),
    Mutant("noversioninfilename", D, '"\\(encoded).v\\(version).schema.json"', '"\\(encoded).schema.json"'),
    Mutant("idisname", D, ".string(fileName)", ".string(name)"),
    Mutant("titlerenamed", D, '"title"', '"name"'),
    Mutant("requiredinverted", D, "properties.filter { !$0.isOptional }", "properties.filter { $0.isOptional }"),
    Mutant("additionalallowed", D, ".boolean(false)", ".boolean(true)"),
    Mutant("documentversionfixed", D, ".integer(Int64(version))", ".integer(1)"),
    Mutant("documentcategoryfixed", D, ".string(consentCategory.name)", '.string("analytics")'),
    Mutant("optionalnotnullable", D, "type.schema(isNullable: isOptional)", "type.schema(isNullable: false)"),
    Mutant("unparsedunnamed", D, '["x-traffluent-swift-type": .string(typeName)]', '["x-traffluent-swift-type": .string("")]'),
    Mutant("wrappednotnullable", D, "wrapped.schema(isNullable: true)", "wrapped.schema(isNullable: false)"),
    Mutant("optionalgenericnotnullable", D, "arguments[0].schema(isNullable: true)", "arguments[0].schema(isNullable: false)"),
    Mutant("optionalunqualified", D, 'names("Optional", in: ["Swift"])', 'names("Optional", in: [])'),
    Mutant("sensitiveunmarked", D, '"x-traffluent-sensitive"', '"x-traffluent-secret"'),
    Mutant("sensitivetraffluentmodule", D, '["Events", "Traffluent"]', '["Events"]'),
    Mutant("sensitivedropsnull", D, "arguments[0].schema(isNullable: isNullable)", "arguments[0].schema(isNullable: false)"),
    Mutant("arraynotnullable", D, '.type("array", isNullable: isNullable)', '.type("array", isNullable: false)'),
    Mutant("itemsnullable", D, "element.schema(isNullable: false)", "element.schema(isNullable: true)"),
    Mutant("arraygenericignored", D, 'names("Array", in: ["Swift"])', 'names("List", in: ["Swift"])'),
    Mutant("scalargenericaccepted", D, "arguments.isEmpty", "true"),
    Mutant("unknownunnamed", D, '["x-traffluent-swift-type": .string(source)]', '["x-traffluent-swift-type": .string("")]'),
    Mutant("floatinteger", D, 'Scalar(name: "Float", modules: ["Swift"], type: "number")', 'Scalar(name: "Float", modules: ["Swift"], type: "integer")'),
    Mutant("int32unbounded", D, "bounds(Int64(Int32.min), Int64(Int32.max))", "[:]"),
    Mutant("uintsigned", D, 'Scalar(name: "UInt", modules: ["Swift"], type: "integer", keywords: ["minimum": .integer(0)])', 'Scalar(name: "UInt", modules: ["Swift"], type: "integer")'),
    Mutant("uint8bounds16", D, 'bounds(0, Int64(UInt8.max))', 'bounds(0, Int64(UInt16.max))'),
    Mutant("dateformatless", D, '["format": .string("date-time")]', '[:]'),
    Mutant("uuidformatless", D, '["format": .string("uuid")]', '[:]'),
    Mutant("foundationessentialsunknown", D, '["Foundation", "FoundationEssentials"]', '["Foundation"]', nth=1),
    Mutant("nullnotadded", D, "isNullable ? .array([.string(name), .string(\"null\")]) : .string(name)", ".string(name)"),
    Mutant("underscorereserved", D, "self == 0x5F", "false"),
    Mutant("hyphenreserved", D, "self == 0x2D", "false"),
    # WrittenType: the parser.
    Mutant("anymodule", W, "modules.contains(components[0])", "true"),
    Mutant("deepqualified", W, "components.count", "min(components.count, 2)"),
    Mutant("trailingtextignored", W, "parser.isAtEnd", "true"),
    Mutant("bangnotoptional", W, 'consume("?") || consume("!")', 'consume("?")'),
    Mutant("unclosedarray", W, 'consume("]")', "true"),
    Mutant("onegenericargument", W, 'consume(",")', "false"),
    Mutant("unclosedgeneric", W, 'consume(">")', "true"),
    Mutant("whitespacesignificant", W, "characters[position].isWhitespace", "false"),
    Mutant("argumentsunspaced", W, 'arguments.map(\\.source).joined(separator: ", ")', 'arguments.map(\\.source).joined(separator: ",")'),
    Mutant("optionalsourcedropped", W, 'wrapped.source + "?"', "wrapped.source"),
    Mutant("arraysourcebare", W, '"[" + element.source + "]"', "element.source"),
    Mutant("underscorenotidentifier", W, 'isLetter || isNumber || self == "_"', "isLetter || isNumber"),
    Mutant("digitnotidentifier", W, 'isLetter || isNumber || self == "_"', 'isLetter || self == "_"', nth=0),
    # Writing and the command. nointermediatedirectories comes first: the file's only `true`, before
    # the mutants below write more.
    Mutant("nointermediatedirectories", F, "true", "false"),
    Mutant("deletesall", F, '$0.hasSuffix(".schema.json") && !paths.contains($0)', '!paths.contains($0)'),
    Mutant("deletesplanfiles", F, '$0.hasSuffix(".schema.json") && !paths.contains($0)', '$0.hasSuffix(".schema.json")'),
    Mutant("rewritesunchanged", F, "fileManager.contents(atPath: url.path) != contents", "true"),
    Mutant("extraargumentsallowed", C, "arguments.count == 1", "arguments.count >= 1"),
    Mutant("usagestatus", C, "            return 64", "            return 1", mode="stmt"),
    Mutant("writefailurestatus", C, "            return 73", "            return 1", mode="stmt"),
    Mutant("successstatus", C, "            return 0", "            return 1", mode="stmt"),
]
