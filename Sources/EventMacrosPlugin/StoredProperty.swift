import SwiftDiagnostics
import SwiftSyntax

/// A stored instance property of an event's struct, which the event encodes.
struct StoredProperty {
    /// The name as written, backticks included, for use in code.
    let identifier: String
    /// The name without backticks, for the schema.
    let name: String
    /// The type as written, without the optional.
    let typeName: String
    /// Whether the type is optional.
    let isOptional: Bool
    /// Whether the declaration gives it an initial value, which a map without its key reads as.
    let hasDefaultValue: Bool
    /// The keywords `@Constrained` declares on it, in order.
    let constraints: [DeclaredConstraint]

    /// The schema's keywords for it: its type's, which a `Refined` type's rule gives, then the
    /// declared ones.
    ///
    /// The declared ones are written as `Events.ValidationKeyword`s, whose cases are spelled as the
    /// constraints are, rather than built as constraints, which throw: the macro has checked their
    /// arguments, and `constraintViolation()` builds them in a context typed by the property's
    /// type.
    var keywords: String {
        let typed = "Events.ValidationKeyword.keywords(of: \\Self.\(identifier))"
        guard !constraints.isEmpty else { return typed }
        return "\(typed) + (\(constraintList) as [Events.ValidationKeyword])"
    }

    /// The declared constraints as an array literal, as written.
    var constraintList: String {
        "[" + constraints.map(\.source).joined(separator: ", ") + "]"
    }

    /// The name as an argument label: without backticks, which a label needs only for `inout`,
    /// `var` and `let`.
    var label: String {
        ["inout", "var", "let"].contains(name) ? identifier : name
    }

    /// The stored instance properties `members` declare, in order, with the diagnostics of the
    /// ones the macro can't encode.
    ///
    /// Static and computed properties are skipped, and so is a `let` with an initial value, which
    /// every value shares and an initializer can't assign.
    static func properties(of members: MemberBlockItemListSyntax) -> (properties: [StoredProperty], diagnostics: [Diagnostic]) {
        var properties: [StoredProperty] = []
        var diagnostics: [Diagnostic] = []
        for member in members {
            guard let variable = member.decl.as(VariableDeclSyntax.self), !variable.isStatic else { continue }
            if variable.isLazy {
                diagnostics.append(Diagnostic(node: variable, message: EventMacroDiagnostic.lazyProperty))
                continue
            }
            let isLet = variable.bindingSpecifier.tokenKind == .keyword(.let)
            let (constraints, constraintDiagnostics) = DeclaredConstraint.constraints(of: variable)
            diagnostics += constraintDiagnostics
            let bindings = Array(variable.bindings)
            var boundsDiagnosed = false
            for (index, binding) in bindings.enumerated() where !binding.isComputed {
                if isLet && binding.initializer != nil { continue }
                guard let pattern = binding.pattern.as(IdentifierPatternSyntax.self) else {
                    diagnostics.append(Diagnostic(node: binding.pattern, message: EventMacroDiagnostic.destructuringPattern))
                    continue
                }
                guard let type = binding.declaredType(sharedFrom: bindings[(index + 1)...]) else {
                    diagnostics.append(Diagnostic(node: binding, message: EventMacroDiagnostic.missingTypeAnnotation))
                    continue
                }
                let identifier = pattern.identifier.text
                let wrapped = type.wrappedInOptional
                let typeName = (wrapped ?? type).trimmedDescription
                // Once per declaration: an attribute applies to every binding of it alike.
                if !boundsDiagnosed {
                    boundsDiagnosed = true
                    diagnostics += constraints.compactMap { constraint in
                        constraint.boundDiagnostic(forType: typeName).map { Diagnostic(node: constraint.expression, message: $0) }
                    }
                }
                properties.append(StoredProperty(
                    identifier: identifier,
                    name: pattern.identifier.identifier?.name ?? identifier,
                    typeName: typeName,
                    isOptional: wrapped != nil,
                    // A `let` with one was skipped above, so this is a `var`'s.
                    hasDefaultValue: binding.initializer != nil,
                    // An attribute applies to every binding of its declaration: `var a, b: String`.
                    constraints: constraints
                ))
            }
        }
        return (properties, diagnostics)
    }
}

extension VariableDeclSyntax {
    /// Whether the declaration is `static`: a property of the type, not of each value. (A struct
    /// can't declare `class` properties.)
    var isStatic: Bool {
        modifiers.contains { $0.name.tokenKind == .keyword(.static) }
    }

    fileprivate var isLazy: Bool {
        modifiers.contains { $0.name.tokenKind == .keyword(.lazy) }
    }
}

extension PatternBindingSyntax {
    /// Whether the binding has a getter: accessors other than `willSet` and `didSet` observers,
    /// which a stored property may have.
    var isComputed: Bool {
        switch accessorBlock?.accessors {
        case nil:
            false
        case .getter:
            true
        case .accessors(let accessors):
            accessors.contains { ![.keyword(.willSet), .keyword(.didSet)].contains($0.accessorSpecifier.tokenKind) }
        }
    }

    /// The binding's type annotation, or, for `a` in `var a, b: Int`, the one a later binding of
    /// the same declaration shares with it; `nil` when the type is only inferred.
    fileprivate func declaredType(sharedFrom later: ArraySlice<PatternBindingSyntax>) -> TypeSyntax? {
        if let type = typeAnnotation?.type { return type }
        guard initializer == nil else { return nil }
        for binding in later {
            if let type = binding.typeAnnotation?.type { return type }
            if binding.initializer != nil { return nil }
        }
        return nil
    }
}

extension TypeSyntax {
    /// The type an optional wraps, written `T?`, `T!`, `Optional<T>` or `Swift.Optional<T>`; `nil`
    /// for a type that isn't optional.
    fileprivate var wrappedInOptional: TypeSyntax? {
        if let optional = self.as(OptionalTypeSyntax.self) { return optional.wrappedType }
        if let optional = self.as(ImplicitlyUnwrappedOptionalTypeSyntax.self) { return optional.wrappedType }
        if let identifier = self.as(IdentifierTypeSyntax.self), identifier.name.text == "Optional" {
            return identifier.genericArgumentClause?.onlyType
        }
        if let member = self.as(MemberTypeSyntax.self), member.name.text == "Optional", member.baseType.trimmedDescription == "Swift" {
            return member.genericArgumentClause?.onlyType
        }
        return nil
    }
}

extension GenericArgumentClauseSyntax {
    /// The clause's first argument when it is a type: `Optional`'s only one.
    fileprivate var onlyType: TypeSyntax? {
        guard case .type(let type) = arguments.first?.argument else { return nil }
        return type
    }
}
