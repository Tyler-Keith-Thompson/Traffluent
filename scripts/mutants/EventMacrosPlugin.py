# Planted bugs for EventMacrosPlugin, the @Event macro; run with `just mutate EventMacrosPlugin`.
# See scripts/mutate.py.
#
# Each mutant is Mutant(name, file, old, new), where `old` occurs once in
# Sources/EventMacrosPlugin/<file> (or `nth=` picks one), and mode="stmt" replaces whole statements
# rather than an expression. Every mutant must be caught; one that survives needs a test, or a note
# here saying why it is equivalent to the original.
#
# The expansion tests call the macro in process, so the mutant switch reaches it. Plugin.swift, the
# entry point the compiler starts, is left out: only a real compile reaches it, which
# //Tests/CompileFailures and //Tests/EventMacrosTests do under Bazel.
#
# Known equivalent mutants (left out, as they would survive by design): in EventLinkerSetMacro's
# uniqueKey, the throw for a name: that isn't a string literal, replaced by `return
# structure.typeName` or `return nil`. @Event's peer reports nameNotALiteral from the arguments and
# writes no record before LinkerSets asks for the key, and @_DiscoverableEvent takes no name:, so no
# expansion reaches it; it stays so the key never stands in for a name it didn't read (TRAF-139).
#
# Left out because no mutant run compiles it: IntegerLiteralExprSyntax+RepresentedLiteralValue.swift,
# swift-syntax 600's backport of representedLiteralValue, sits under
# `#if !canImport(SwiftSyntax601)`, and this repository resolves a newer swift-syntax. Checked by
# hand instead (TRAF-120), in a SwiftPM package of the plugin and its tests pinned to 600.0.0: a
# wrong radix for 0b, 0o or 0x, a radix prefix kept, and underscores kept are each caught by
# versionLiteralRadix. Dropping the `hasError` guard survives, equivalent: every integer literal
# the parser flags (a prefix without digits, a digit outside its radix) is text `Int(_:radix:)`
# rejects too; the guard stays to read literals as 601's own property does.
#
# Left out because a schema can't switch it: the schema's `consentCategory: Self.consentCategory`,
# text inside a multi-line string literal. //Tests/EventMacrosTests pins each event's schema
# category, and Events.py's schemaconsentfixed the stored field.

TESTS = ["EventMacrosPluginTests"]

M = "EventMacro.swift"
A = "EventArguments.swift"
P = "StoredProperty.swift"
D = "EventMacroDiagnostic.swift"
C = "DeclaredConstraint.swift"
X = "ConstrainedMacro.swift"
R = "RawValueEnum.swift"
L = "EventLinkerSetMacro.swift"
V = "DiscoverableEventMacro.swift"
E = "EventRecordMacro.swift"
# A schema property's entry, as EventMacro.swift writes it.
PROPERTY = r'"        Events.EventSchema.Property(name: \"\(property.name)\", typeName: \"\(property.typeName)\", isOptional: \(property.isOptional), \(defaultValue)hasInvalidConstraint: Events.ValidationKeyword.hasInvalidConstraint(of: \\Self.\(property.identifier)), keywords: \(property.keywords)\(enumeration)),"'

MUTANTS = [
    # EventMacro: the extension.
    Mutant("notastructsilent", M, "context.diagnose(Diagnostic(node: node, message: EventMacroDiagnostic.notAStruct))", "", mode="stmt"),
    Mutant("errorsstillexpand", M, "diagnostics.isEmpty", "true"),
    Mutant("accessdropped", M, '"\\($0.name.text) "', '""'),
    Mutant("packagenotcopied", M, "[.keyword(.public), .keyword(.package)]", "[.keyword(.public)]"),
    Mutant("conformanceinverted", M, '$0.trimmedDescription.split(separator: ".").last.map(String.init) == name', '$0.trimmedDescription.split(separator: ".").last.map(String.init) != name'),
    Mutant("conformancesfirstonly", M, 'conformances.joined(separator: ", ")', 'conformances.first ?? ""'),
    # TRAF-118: the extension is nonisolated. The expansion tests catch the mutant, as every
    # expected expansion holds the keyword. //Tests/CompileFailures:EventDefaultMainActorControl
    # compiles the real expansion, which no mutant run reaches.
    Mutant("extensionisolated", M, '"nonisolated extension \\(type.trimmedDescription)\\(inheritance) {\\n\\(body)\\n}"', '"extension \\(type.trimmedDescription)\\(inheritance) {\\n\\(body)\\n}"'),
    Mutant("nameignored", M, 'arguments.name.map { "\\($0)" } ?? defaultName', "defaultName"),
    # TRAF-139: the name always declared, the default as Event's own.
    Mutant("namedefaultwrong", M, '"String(describing: Self.self)"', '"String(reflecting: Self.self)"'),
    Mutant("consentignored", M, 'arguments.consent.map { "\\(access)static var consentCategory: Events.ConsentCategory {\\n    \\($0)\\n}" }', "nil"),
    Mutant("versionfixed", M, "arguments.version", "Int?.some(1)"),
    # Two mutants of the property entry's literal: the first leaves the original once, in its
    # unmutated branch, for the second.
    Mutant("schemanamebackticked", M, PROPERTY, PROPERTY.replace("property.name", "property.identifier")),
    Mutant("schemanotoptional", M, PROPERTY, PROPERTY.replace(r"\(property.isOptional)", "false")),
    Mutant("emptylistbracketed", M, '"[]"', '"[\\n    ]"'),
    # The coding (TRAF-83): CodingKeys, encode(to:) and init(from:) over Codable.
    # Left out: reversing the order of encode(to:)'s and init(from:)'s lines, whose closures span
    # statements a mutant switch can't wrap. The expansion tests pin both orders.
    Mutant("decodabledropped", M, '"Swift.Decodable"', '"Swift.Encodable"'),
    Mutant("keysreversed", M, 'properties.map { "    case \\($0.identifier)\\n" }', 'properties.reversed().map { "    case \\($0.identifier)\\n" }'),
    # After keysreversed, its literal occurs twice; the second is the original's.
    Mutant("keyrawbackticked", M, '"    case \\($0.identifier)\\n"', '"    case \\($0.identifier) = \\"\\($0.identifier)\\"\\n"', nth=1),
    Mutant("emptykeystyped", M, '        guard !properties.isEmpty else { return "private enum CodingKeys: Swift.CodingKey {\\n}" }', '', mode="stmt"),
    Mutant("nilwritten", M, 'property.isOptional && !property.hasDefaultValue ? "encodeIfPresent" : "encode"', '"encode"'),
    Mutant("defaultednilleftout", M, 'property.isOptional && !property.hasDefaultValue', 'property.isOptional'),
    Mutant("dateencodedasdate", M, '"\\(unwrap).timeIntervalSinceReferenceDate"', '""'),
    Mutant("dateunwrapforced", M, 'property.isOptional ? "?" : ""', '""'),
    Mutant("emptyencodenocontainer", M, '"    _ = encoder.container(keyedBy: CodingKeys.self)\\n"', '""'),
    Mutant("optionalrequired", M, 'property.isOptional ? "decodeIfPresent" : "decode"', '"decode"', nth=0),
    Mutant("scalarsgeneric", M, 'property.isDate || property.isStandardScalar || property.dateArrayElement != nil', 'false'),
    Mutant("dategeneric", M, 'property.isDate || property.isStandardScalar || property.dateArrayElement != nil', 'property.isStandardScalar || property.dateArrayElement != nil'),
    Mutant("datearraygeneric", M, 'property.isDate || property.isStandardScalar || property.dateArrayElement != nil', 'property.isDate || property.isStandardScalar'),
    Mutant("datereadasdate", M, 'if property.isDate { return "Swift.Double" }', '', mode="stmt"),
    # Left out: reading an array of dates as its own type in writtenType(of:), whose guard binds the
    # element a statement mutant would scope away. The expansion tests pin the read type.
    Mutant("optionaldatearrayreadasdates", M, 'element.isOptional ? "[Swift.Double?]" : "[Swift.Double]"', '"[Swift.Double]"'),
    Mutant("datearrayencodedasdates", M, 'seconds ?? ""', '""'),
    Mutant("optionaldateelementsforced", M, '"\\(unwrap).map { $0?.timeIntervalSinceReferenceDate }"', '"\\(unwrap).map(\\\\.timeIntervalSinceReferenceDate)"'),
    Mutant("datearraydecodedasdoubles", M, 'Self.dates(from: read, element: element, isOptional: property.isOptional)', 'read'),
    Mutant("optionaldatearrayunwrapped", M, 'isOptional ? "\\(read).map { $0\\(array) }" : "\\(read)\\(array)"', '"\\(read)\\(array)"'),
    Mutant("optionaldateelementsnotmapped", M, 'element.isOptional ? ".map { $0.map(\\(date)) }" : ".map(\\(date))"', '".map(\\(date))"'),
    Mutant("datearrayundetected", P, 'guard Self.dateNames.contains(name) else { return nil }', 'return nil', mode="stmt"),
    Mutant("optionaldateelementundetected", P, 'element.hasSuffix("?")', 'false'),
    Mutant("datedecodedasdate", M, '!property.isDate', 'true', nth=1),
    Mutant("decodefunctionsdropped", M, 'decodeFunctions(of: properties)', '[String]()'),
    Mutant("scalarqualifiedmissed", P, 'typeName.hasPrefix("Swift.") ? String(typeName.dropFirst("Swift.".count)) : typeName', 'typeName'),
    Mutant("scalarsnone", P, '["String", "Bool", "Double", "Float", "Int", "Int8", "Int16", "Int32", "Int64", "UInt", "UInt8", "UInt16", "UInt32", "UInt64"].contains(name)', 'false'),
    Mutant("decodefunctionmissing", M, 'generic.contains { !$0.isOptional }', 'false'),
    Mutant("decodeifpresentfunctionmissing", M, 'generic.contains(where: \\.isOptional)', 'false'),
    Mutant("decodefunctionsalways", M, 'generic.contains { !$0.isOptional }', 'true'),
    Mutant("decodefunctionsforscalars", M, 'properties.filter { !$0.isDate && !$0.isStandardScalar && $0.dateArrayElement == nil }', 'properties'),
    Mutant("decodefunctionsfordatearrays", M, '$0.dateArrayElement == nil', 'true'),
    Mutant("optionaldatenotmapped", M, 'property.isOptional ? "\\(read).map(\\(date))" : "\\(property.typeName)(timeIntervalSinceReferenceDate: \\(read))"', '"\\(property.typeName)(timeIntervalSinceReferenceDate: \\(read))"'),
    Mutant("defaultnotdecoded", M, '            guard property.hasDefaultValue else { return "    \\(assignment)\\n" }', '            return "    \\(assignment)\\n"', mode="stmt"),
    Mutant("defaultalwaysguarded", M, '            guard property.hasDefaultValue else { return "    \\(assignment)\\n" }', '', mode="stmt"),
    Mutant("emptydecodenocontainer", M, '"    _ = try decoder.container(keyedBy: CodingKeys.self)\\n"', '""'),
    Mutant("dateundetected", P, 'Self.dateNames.contains(typeName)', 'typeName == "Date"'),
    Mutant("requirementsnone", M, "        guard !properties.isEmpty else { return [] }", "        return []", mode="stmt"),
    Mutant("requirementlabelidentifier", M, '"private static func requireCodable(\\($0.label): KeyPath<Self, some Swift.Codable>) {}"', '"private static func requireCodable(\\($0.identifier): KeyPath<Self, some Swift.Codable>) {}"'),
    Mutant("requirementsuncalled", M, '["private static var codableRequirements: Void {\\n\\(calls)}"]', "[]"),
    # EventArguments: what the attribute was given.
    Mutant("nilnotdefault", A, "            if expression.is(NilLiteralExprSyntax.self) { continue }", "", mode="stmt"),
    Mutant("namelabel", A, '"name"', '"title"'),
    Mutant("namediagnosticignored", A, "expression.nameDiagnostic", "nil"),
    Mutant("consentdropped", A, "                arguments.consent = expression.trimmed", "", mode="stmt"),
    Mutant("versionzero", A, "version >= 1", "version >= 0"),
    Mutant("versiondropped", A, "                arguments.version = version", "", mode="stmt"),
    Mutant("interpolationallowed", A, "literal.segments.allSatisfy({ $0.is(StringSegmentSyntax.self) })", "true"),
    Mutant("emptyallowed", A, "isEmpty ? .emptyName : nil", "nil"),
    # StoredProperty: which properties are encoded, and how they are described. getterstored comes
    # first: the file's second `true` (the first marks a declaration's bounds diagnosed), before the
    # mutants below write more.
    Mutant("getterstored", P, "true", "false", nth=1),
    Mutant("staticincluded", P, "!variable.isStatic", "true"),
    Mutant("lazyallowed", P, "variable.isLazy", "false"),
    Mutant("letwithvalueincluded", P, "isLet && binding.initializer != nil", "false"),
    Mutant("computedincluded", P, "!binding.isComputed", "true"),
    Mutant("observerscomputed", P, "![.keyword(.willSet), .keyword(.didSet)].contains($0.accessorSpecifier.tokenKind)", "true"),
    Mutant("destructuringsilent", P, "                    diagnostics.append(Diagnostic(node: binding.pattern, message: EventMacroDiagnostic.destructuringPattern))", "", mode="stmt"),
    Mutant("untypedsilent", P, "                    diagnostics.append(Diagnostic(node: binding, message: EventMacroDiagnostic.missingTypeAnnotation))", "", mode="stmt"),
    Mutant("noshareannotation", P, "bindings[(index + 1)...]", "bindings[bindings.endIndex...]"),
    Mutant("initializershares", P, "        guard initializer == nil else { return nil }", "", mode="stmt"),
    Mutant("sharepastinitializer", P, "            if binding.initializer != nil { return nil }", "", mode="stmt"),
    Mutant("typenamewhole", P, "(wrapped ?? type).trimmedDescription", "type.trimmedDescription"),
    Mutant("namebackticked", P, "pattern.identifier.identifier?.name ?? identifier", "identifier"),
    Mutant("labelalwaysbare", P, '["inout", "var", "let"].contains(name) ? identifier : name', "name"),
    Mutant("labelalwaysidentifier", P, '["inout", "var", "let"].contains(name) ? identifier : name', "identifier"),
    Mutant("optionalsugarmissed", P, "        if let optional = self.as(OptionalTypeSyntax.self) { return optional.wrappedType }", "", mode="stmt"),
    Mutant("iuomissed", P, "        if let optional = self.as(ImplicitlyUnwrappedOptionalTypeSyntax.self) { return optional.wrappedType }", "", mode="stmt"),
    Mutant("anygenericoptional", P, 'identifier.name.text == "Optional"', "true"),
    Mutant("anymoduleoptional", P, 'member.baseType.trimmedDescription == "Swift"', "true"),
    Mutant("qualifiedoptionalmissed", P, 'member.name.text == "Optional"', "false"),
    # EventMacroDiagnostic: errors, not warnings.
    Mutant("warningsonly", D, "isNote ? .note : .error", ".warning"),
    Mutant("notesaserrors", D, "isNote ? .note : .error", ".error"),
    # @Constrained: what @Event generates from it.
    Mutant("noconstraintviolation", M, "constraintViolation(of: properties, access: access),", "nil,"),
    # Constraints that throw as they are built: the event breaks the first, rather than passing.
    Mutant("invalidconstraintpasses", M, r'"    return Events.ConstraintViolation(property: \"\(property.name)\", invalidConstraint: \(constraint.source.stringLiteral), error: error)\n"', r'"    return nil\n"'),
    Mutant("backslashunescaped", M, r'"\\\\"', r'"\\"'),
    Mutant("quoteunescaped", M, r'"\\\""', r'"\""'),
    # Bounds a schema can't state as written: diagnosed, rather than left to throw at run time.
    Mutant("inexactboundaccepted", C, "Double(exactly: magnitude) == nil", "false"),
    Mutant("doubleoverflowaccepted", C, "!value.isFinite", "false"),
    Mutant("floatoverflowaccepted", C, "value.isFinite", "true", nth=1),
    Mutant("floatroundingaccepted", C, "Double(value.description) == written", "true"),
    Mutant("roundedsignlost", C, '(literal.isNegative ? "-" : "")', '""'),
    Mutant("optionalunwrapped", M, "guard property.isOptional else { return checks }", "return checks", mode="stmt"),
    Mutant("schemadeclaredkeywordsdropped", P, "guard !constraints.isEmpty else { return typed }", "return typed", mode="stmt"),
    Mutant("constraintsunread", P, "DeclaredConstraint.constraints(of: variable)", "([DeclaredConstraint](), [Diagnostic]())"),
    # @Constrained: what @Event reads, and the errors it reports.
    Mutant("qualifiednotread", C, 'name == "Constrained" || name == "EventMacros.Constrained"', 'name == "Constrained"'),
    Mutant("invalidpatternaccepted", C, "(try? Regex(pattern)) != nil", "true"),
    Mutant("conflictsunchecked", C, "diagnostics = conflicts(among: constraints)", "", mode="stmt"),
    Mutant("equalboundsconflict", C, "lower > upper", "lower >= upper"),
    Mutant("exampleunchecked", C, "!$0.keyword.accepts(example)", "false"),
    Mutant("examplelengthunchecked", C, "string.unicodeScalars.count <= length", "true"),
    Mutant("negativeboundpositive", C, "prefix.expression.numberLiteralValue.map { -$0 }", "prefix.expression.numberLiteralValue"),
    Mutant("labelledcountaccepted", C, "arguments[0].label == nil", "true", nth=0),
    Mutant("examplelabelunchecked", C, 'arguments[1].label?.text == "example"', "true"),
    # @Constrained's own check of where it is.
    Mutant("staticconstrained", X, "!variable.isStatic && !variable.bindings.contains { $0.isComputed }", "!variable.bindings.contains { $0.isComputed }"),
    Mutant("computedconstrained", X, "!variable.isStatic && !variable.bindings.contains { $0.isComputed }", "!variable.isStatic"),
    Mutant("anystructconstrained", X, "!isStored || !inEvent", "!isStored"),
    # A property's default value (TRAF-18): marked in the schema, and read back when its key is
    # missing.
    Mutant("defaultvalueundetected", P, "binding.initializer != nil", "false", nth=1),
    Mutant("defaultnotinschema", M, 'property.hasDefaultValue ? "hasDefaultValue: true, " : ""', '""'),
    # Raw-value enums (TRAF-91): the enumeration each property's schema gets, and the error for an
    # enum declared inside the event without Codable.
    Mutant("enumcasesunread", M, "held.cases", "[String]?.none"),
    Mutant("enumcasesunqualified", M, '"] as [Self.\\(held.name)])"', '"] as [\\(held.name)])"'),
    Mutant("enumcasesunescaped", M, '".`\\($0)`"', '".\\($0)"'),
    Mutant("enumdiagnosticrepeated", M, "Set(lacking).sorted()", "lacking"),
    Mutant("enumerationforscalars", M, "!property.isStandardScalar", "true", nth=0),
    Mutant("enumerationfordates", M, "!property.isDate", "true", nth=0),
    Mutant("enumerationfordatearrays", M, "property.dateArrayElement == nil", "true"),
    Mutant("enumnotdiagnosed", M, "$0?.lacksCodable == true", "false"),
    Mutant("enumdiagnosedever", M, "$0?.lacksCodable == true", "$0 != nil"),
    Mutant("enumrawtypeany", R, "rawTypeNames.contains(rawType.withoutSwiftModule)", "true"),
    Mutant("enumswiftmodulekept", R, 'hasPrefix("Swift.") ? String(dropFirst("Swift.".count)) : self', "self"),
    Mutant("enumifconfigread", R, "if member.decl.is(IfConfigDeclSyntax.self) { return nil }", "", mode="stmt"),
    Mutant("enumfirstcaseonly", R, "declaration.elements.map(\\.name.text.withoutBackticks)", "declaration.elements.prefix(1).map(\\.name.text.withoutBackticks)"),
    Mutant("enumbacktickskept", R, 'hasPrefix("`") && hasSuffix("`") && count > 1 ? String(dropFirst().dropLast()) : self', "self"),
    Mutant("enumselfprefixdropped", R, '["", "Self.", "\\(structure)."]', '["", "\\(structure)."]'),
    Mutant("enumstructureprefixdropped", R, '["", "Self.", "\\(structure)."]', '["", "Self."]'),
    Mutant("enumcodablepairignored", R, '!names.isSuperset(of: ["Encodable", "Decodable"])', "true"),
    Mutant("enumunknownlacks", R, "names.isSubset(of: unrelated)", "true"),
    Mutant("leafoptionalkept", P, "if let wrapped = wrappedInOptional { return wrapped.leaf }", "", mode="stmt"),
    Mutant("leafarraykept", P, "if let array = self.as(ArrayTypeSyntax.self) { return array.element.leaf }", "", mode="stmt"),
    Mutant("leafqualifiedkept", P, "wrapper.modules.contains(member.baseType.trimmedDescription)", "false"),
    Mutant("leafsensitivekept", P, '"Sensitive"', '"Mine"'),
    Mutant("leafarraynamekept", P, '"Array"', '"Mine"'),
    # EventMacro: the discovery record, the peer LinkerSets' expansion writes (recordPeers, from
    # EventMacro's own LinkerSetMacro conformance), the __DiscoverableEvent conformance the record
    # holds the struct as, and the mapping of LinkerSets' refusals to the note or to silence.
    Mutant("recordalwaysdropped", M, "return try recordPeers(of: node, providingPeersOf: declaration, in: context)", "return []", mode="stmt"),
    # The peer's guard: anything but a struct gets no record (the extension reports notAStruct).
    Mutant("recordbesidenonstruct", M, "return []", "return try recordPeers(of: node, providingPeersOf: declaration, in: context)", mode="stmt", nth=2),
    Mutant("recordbesideargumenterrors", M, "argumentDiagnostics.isEmpty", "true"),
    Mutant("recordbesidepropertyerrors", M, "propertyDiagnostics.isEmpty", "true"),
    Mutant("recordbesideenumerrors", M, "enumDiagnostics(of: held, in: enums).isEmpty", "true"),
    Mutant("recordbesideundiscoverable", M, "isRecorded && expands", "expands"),
    Mutant("discoverableunconformed", M, 'discovery.isRecorded ? [("__DiscoverableEvent", "Events.__DiscoverableEvent")] : []', "[]"),
    Mutant("undiscoverableconformed", M, 'discovery.isRecorded ? [("__DiscoverableEvent", "Events.__DiscoverableEvent")] : []', '[("__DiscoverableEvent", "Events.__DiscoverableEvent")]'),
    # EventLinkerSetMacro: what @Event's and @_DiscoverableEvent's records share. The kind is
    # caught by the expansion tests, and against Events' LinkerSetKind.events by
    # //Tests/EventDiscoveryTests, which no mutant run reaches.
    Mutant("recordkindwrong", L, "0x6576_6E74", "0x6576_6E75"),
    Mutant("recordholdsany", L, '"Events.__DiscoverableEvent"', "nil"),
    Mutant("recordmacrolinkersets", L, '"__eventRecord"', '"linkerSetRecord"'),
    Mutant("discoverynoteunsaid", M, "discovery.note.map(context.diagnose)", "", mode="stmt"),
    # Any other refusal (a local struct's) recorded: recordPeers then throws LinkerSets' error.
    Mutant("otherrefusalrecorded", M, "return .refused", "return .recorded", mode="stmt"),
    Mutant("genericrefusalsilent", M, "return .noted(Diagnostic(node: structure.genericParameterClause.map(Syntax.init) ?? refusal.node, message: EventMacroDiagnostic.genericNotDiscovered))", "return .refused", mode="stmt"),
    Mutant("genericnoteatdeclaration", M, "structure.genericParameterClause.map(Syntax.init) ?? refusal.node", "refusal.node"),
    Mutant("nestedrefusalsilent", M, "return .noted(Diagnostic(node: structure.name, message: EventMacroDiagnostic.nestedInGenericNotDiscovered))", "return .refused", mode="stmt"),
    Mutant("nestednotedasgeneric", M, "EventMacroDiagnostic.nestedInGenericNotDiscovered", "EventMacroDiagnostic.genericNotDiscovered"),
    # @_DiscoverableEvent: the conformance only where the compiler asks for it, and #__eventRecord,
    # LinkerSets' record under Traffluent's name.
    Mutant("handwrittenconformsalways", V, "guard !protocols.isEmpty else { return names }", "", mode="stmt"),
    Mutant("handwrittenunconformed", V, 'return [try ExtensionDeclSyntax("extension \\(type.trimmed): Events.__DiscoverableEvent {}")] + names', "return names", mode="stmt"),
    Mutant("eventrecordempty", E, "try LinkerSetRecordMacro.expansion(of: node, in: context)", "[]"),
    # TRAF-139: the record's unique key, the event's name. The expansion tests pin each key's
    # symbol; //Tests/CompileFailures' DuplicateEventNames, DuplicateEventNamesAcrossVersions and
    # DuplicateEventNameInOneModule link the real expansion, which no mutant run reaches.
    Mutant("keynil", L, "declaration.as(StructDeclSyntax.self)", "Optional<StructDeclSyntax>.none"),
    Mutant("keyalwaystypename", L, "EventArguments.arguments(of: attribute).arguments.name", "Optional<ExprSyntax>.none"),
    Mutant("keyrawliteral", L, "name.as(StringLiteralExprSyntax.self)?.representedLiteralValue", "name.as(StringLiteralExprSyntax.self)?.segments.trimmedDescription"),
    Mutant("typenamebackticked", "StructDeclSyntax+EventName.swift", 'return String(text.dropFirst().dropLast())', "return text", mode="stmt"),
    Mutant("namememberanystatic", "StructDeclSyntax+EventName.swift", '$0.pattern.as(IdentifierPatternSyntax.self)?.identifier.text == "name"', "true"),
    Mutant("namememberinstance", "StructDeclSyntax+EventName.swift", "$0.name.tokenKind == .keyword(.static)", "true"),
    Mutant("namememberunreported", M, "argumentDiagnostics + nameMemberDiagnostics(of: structure, attribute: node) + propertyDiagnostics", "argumentDiagnostics + propertyDiagnostics"),
    Mutant("namememberpeerrecorded", M, "EventArguments.arguments(of: node).diagnostics + nameMemberDiagnostics(of: structure, attribute: node)", "EventArguments.arguments(of: node).diagnostics"),
    # The Fix-It that moves a name member into name:.
    Mutant("fixitdropped", M, "moveNameFixIt(of: member, in: structure, attribute: attribute).map { [$0] } ?? []", "[]"),
    Mutant("fixitbesidename", M, "EventArguments.arguments(of: attribute).arguments.name == nil", "true"),
    Mutant("fixitmultiplebindings", M, "member.bindings.count == 1", "true"),
    Mutant("fixitnocomma", M, "existing.isEmpty ? nil : .commaToken(trailingTrivia: .space)", "nil"),
    Mutant("fixitnamelast", M, "[name] + existing", "existing + [name]"),
    Mutant("fixitmemberkept", M, "structure.memberBlock.members.filter { $0.decl.id != DeclSyntax(member).id }", "structure.memberBlock.members"),
    # What @Event and @_DiscoverableEvent share in a private or fileprivate scope: no key, rather
    # than LinkerSets' refusal. Which scopes count is LinkerSets' rule (uniqueKeyInPrivateScope).
    Mutant("privatescopekeyrefused", L, ".omitted", "UniqueKeyInPrivateScope.refused"),
    # @_DiscoverableEvent's name and key.
    Mutant("discoverablenameomitted", V, "structure?.nameMember == nil ? [name] : []", "[ExtensionDeclSyntax]()"),
    Mutant("discoverablenamebesidemember", V, "structure?.nameMember == nil ? [name] : []", "[name]"),
    Mutant("discoverablenameunexported", V, '"\\($0.name.text) "', '""'),
    # After handwrittenunconformed, whose replacement is the same statement, it occurs twice; the first is the guard's.
    Mutant("discoverablenamewhenconforming", V, "return names", "return []", mode="stmt", nth=0),
    Mutant("discoverablekeynil", V, "declaration.as(StructDeclSyntax.self)", "Optional<StructDeclSyntax>.none", nth=1),
    Mutant("discoverablenamememberignored", V, "throw DiagnosticsError(diagnostics: [Diagnostic(node: member, message: EventMacroDiagnostic.discoverableNameMember)])", "", mode="stmt"),
    Mutant("discoverablemessageevents", V, "EventMacroDiagnostic.discoverableNameMember", "EventMacroDiagnostic.nameMember"),
]
