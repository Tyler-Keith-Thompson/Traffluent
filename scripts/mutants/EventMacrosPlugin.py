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
# Known equivalent mutants (left out, as they would survive by design): none.
#
# Left out because a schema can't switch it: the schema's `consentCategory: Self.consentCategory`,
# text inside a multi-line string literal. //Tests/EventMacrosTests pins each event's schema
# category, and Events.py's schemaconsentfixed the stored field.

TESTS = ["EventMacrosPluginTests"]

M = "EventMacro.swift"
A = "EventArguments.swift"
P = "StoredProperty.swift"
D = "EventMacroDiagnostic.swift"
# A schema property's entry, as EventMacro.swift writes it.
PROPERTY = r'"        Events.EventSchema.Property(name: \"\($0.name)\", typeName: \"\($0.typeName)\", isOptional: \($0.isOptional)),"'

MUTANTS = [
    # EventMacro: the extension.
    Mutant("notastructsilent", M, "context.diagnose(Diagnostic(node: node, message: EventMacroDiagnostic.notAStruct))", "", mode="stmt"),
    Mutant("errorsstillexpand", M, "diagnostics.isEmpty", "true"),
    Mutant("accessdropped", M, '"\\($0.name.text) "', '""'),
    Mutant("packagenotcopied", M, "[.keyword(.public), .keyword(.package)]", "[.keyword(.public)]"),
    Mutant("conformanceinverted", M, '$0.trimmedDescription.split(separator: ".").last.map(String.init) == name', '$0.trimmedDescription.split(separator: ".").last.map(String.init) != name'),
    Mutant("conformancesfirstonly", M, 'conformances.joined(separator: ", ")', 'conformances.first ?? ""'),
    Mutant("nameignored", M, 'arguments.name.map { "\\(access)static var name: String {\\n    \\($0)\\n}" }', "nil"),
    Mutant("consentignored", M, 'arguments.consent.map { "\\(access)static var consentCategory: Events.ConsentCategory {\\n    \\($0)\\n}" }', "nil"),
    Mutant("versionfixed", M, "arguments.version", "1"),
    # Two mutants of the property entry's literal: the first leaves the original once, in its
    # unmutated branch, for the second.
    Mutant("schemanamebackticked", M, PROPERTY, PROPERTY.replace("$0.name", "$0.identifier")),
    Mutant("schemanotoptional", M, PROPERTY, PROPERTY.replace(r"\($0.isOptional)", "false")),
    Mutant("emptylistbracketed", M, '"[]"', '"[\\n    ]"'),
    Mutant("encodereversed", M, 'properties.map { "    encoder.encode(self.\\($0.identifier))" }', 'properties.reversed().map { "    encoder.encode(self.\\($0.identifier))" }'),
    # After encodereversed, its literal occurs twice; the second is the original's.
    Mutant("encodeunqualified", M, '"    encoder.encode(self.\\($0.identifier))"', '"    encoder.encode(\\($0.identifier))"', nth=1),
    Mutant("decodereversed", M, 'properties.map { "    self.\\($0.identifier) = try decoder.decode()" }', 'properties.reversed().map { "    self.\\($0.identifier) = try decoder.decode()" }'),
    Mutant("requirementsnone", M, "        guard !properties.isEmpty else { return [] }", "        return []", mode="stmt"),
    Mutant("requirementlabelidentifier", M, '"private static func requireBinaryCodable(\\($0.label): KeyPath<Self, some Persistence.BinaryCodable>) {}"', '"private static func requireBinaryCodable(\\($0.identifier): KeyPath<Self, some Persistence.BinaryCodable>) {}"'),
    Mutant("requirementsuncalled", M, '["private static var binaryCodableRequirements: Void {\\n\\(calls)}"]', "[]"),
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
    # first: the file's only `true`, before the mutants below write more.
    Mutant("getterstored", P, "true", "false"),
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
    Mutant("warningsonly", D, "        .error", "        .warning", mode="stmt"),
]
