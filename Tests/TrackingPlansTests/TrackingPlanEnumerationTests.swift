// How a raw-value enum property exports, validates and is checked: its raw value's schema with an
// `enum` of its raw values, compared as a constraint. Each test is self-contained.

import EventMacros
import Foundation
import JSONSchema
import PropertyBased
import Testing
import TrackingPlans
import TraffluentTestSupport

/// An enum declared outside the events, whose cases the plan reads from allCases.
enum PlanTestsPriority: Int, Codable, CaseIterable {
    case low
    case high = 7
}

/// An enum declared outside the events that isn't CaseIterable, so the plan can't know its values.
enum PlanTestsChannel: String, Codable {
    case email
}

@Suite("TrackingPlan: raw-value enums")
struct TrackingPlanEnumerationTests {
    @Event(name: "checkout_failed")
    struct CheckoutFailed {
        enum Reason: String, Codable {
            case paymentDeclined
            case outOfStock = "out_of_stock"
        }
        typealias Reasons = [Reason]
        typealias Kind = Reason
        var reason: Reason
        var previous: Reason?
        var history: [Reason]
        var gaps: [Reason?]
        var secret: Sensitive<Reason>
        var hidden: [Sensitive<Reason>]
        var aliased: Reasons
        var kind: Kind
        var priority: PlanTestsPriority
        var channel: PlanTestsChannel
        var status: UInt8Status
    }

    enum UInt8Status: UInt8, Codable, CaseIterable {
        case queued = 3
    }

    @Test("Each enum property exports as its raw value's schema with an enum of its raw values, null among them where it is allowed, and a typealias, or an enum declared elsewhere that isn't CaseIterable, as a type the plan can't map")
    func document() throws {
        let sut = try TrackingPlan(schemas: [CheckoutFailed.schema])
        let expected: JSONValue = [
            "reason": ["type": "string", "enum": ["paymentDeclined", "out_of_stock"]],
            "previous": ["type": ["string", "null"], "enum": ["paymentDeclined", "out_of_stock", .null]],
            "history": ["type": "array", "items": ["type": "string", "enum": ["paymentDeclined", "out_of_stock"]]],
            "gaps": ["type": "array", "items": ["type": ["string", "null"], "enum": ["paymentDeclined", "out_of_stock", .null]]],
            "secret": ["type": "string", "enum": ["paymentDeclined", "out_of_stock"], "x-traffluent-sensitive": true],
            "hidden": ["type": "array", "items": ["type": ["string", "null"], "enum": ["paymentDeclined", "out_of_stock", .null], "x-traffluent-sensitive": true]],
            "aliased": ["x-traffluent-swift-type": "Reasons"],
            "kind": ["x-traffluent-swift-type": "Kind"],
            "priority": ["type": "integer", "enum": [0, 7]],
            "channel": ["x-traffluent-swift-type": "PlanTestsChannel"],
            "status": ["type": "integer", "minimum": 0, "maximum": 255, "enum": [3]],
        ]

        let document = try JSONValue.parse(String(decoding: try #require(sut.files.first { $0.path.hasSuffix(".schema.json") }).contents, as: UTF8.self))
        let actual = document.object?["properties"]

        #expect(actual == expected)
    }

    @Test("The example holds each enum's first raw value, and the document accepts it")
    func example() throws {
        let sut = try TrackingPlan(schemas: [CheckoutFailed.schema])
        let expected: JSONValue = [
            "reason": "paymentDeclined",
            "previous": "paymentDeclined",
            "history": ["paymentDeclined"],
            "gaps": ["paymentDeclined"],
            "secret": "paymentDeclined",
            "hidden": ["paymentDeclined"],
            "aliased": .null,
            "kind": .null,
            "priority": 0,
            "channel": .null,
            "status": 3,
        ]
        let document = try #require(sut.files.first { $0.path.hasSuffix(".schema.json") })
        let example = try #require(sut.files.first { $0.path.hasSuffix(".example.json") })
        let schema = try Schema(instance: String(decoding: document.contents, as: UTF8.self))

        let actual = try JSONValue.parse(String(decoding: example.contents, as: UTF8.self))
        let validation = try schema.validate(instance: String(decoding: example.contents, as: UTF8.self))

        #expect(actual == expected)
        #expect(validation.isValid)
    }

    @Test("The document rejects a raw value that matches no case, and an optional enum accepts null")
    func validation() throws {
        let sut = try TrackingPlan(schemas: [CheckoutFailed.schema])
        let document = try #require(sut.files.first { $0.path.hasSuffix(".schema.json") })
        let schema = try Schema(instance: String(decoding: document.contents, as: UTF8.self))
        let valid = #"{"reason": "out_of_stock", "previous": null, "history": [], "gaps": [null, "out_of_stock"], "secret": "out_of_stock", "hidden": [null, "paymentDeclined"], "aliased": [], "kind": "anything", "priority": 7, "channel": "fax", "status": 3}"#
        let invalid = #"{"reason": "outOfStock", "previous": null, "history": [], "gaps": [null, "out_of_stock"], "secret": "out_of_stock", "hidden": [null, "paymentDeclined"], "aliased": [], "kind": "anything", "priority": 7, "channel": "fax", "status": 3}"#

        let actualValid = try schema.validate(instance: valid)
        let actualInvalid = try schema.validate(instance: invalid)

        #expect(actualValid.isValid)
        #expect(!actualInvalid.isValid)
    }

    enum ABC: String, CaseIterable {
        case a, b, c
    }

    enum AB: String, CaseIterable {
        case a, b
    }

    enum AC: String, CaseIterable {
        case a, c
    }

    enum BA: String, CaseIterable {
        case b, a
    }

    enum Levels: Int, CaseIterable {
        case zero, one
    }

    enum Level: Int, CaseIterable {
        case zero
    }

    @Test("Removing or renaming a case, or listing cases where none were, is breaking", arguments: [
        (EventSchema.Enumeration(cases: ABC.allCases), EventSchema.Enumeration(cases: AB.allCases), #"["a", "b", "c"]"# as String?, #"["a", "b"]"# as String?),
        (EventSchema.Enumeration(cases: AB.allCases), EventSchema.Enumeration(cases: AC.allCases), #"["a", "b"]"#, #"["a", "c"]"#),
        (EventSchema.Enumeration(cases: [AB]()), EventSchema.Enumeration(cases: AB.allCases), nil, #"["a", "b"]"#),
        (EventSchema.Enumeration(cases: Levels.allCases), EventSchema.Enumeration(cases: Level.allCases), "[0, 1]", "[0]"),
    ])
    func tightened(committed: EventSchema.Enumeration?, current: EventSchema.Enumeration?, before: String?, after: String?) throws {
        let committedPlan = try TrackingPlan(schemas: [EventSchema(name: "failed", version: 1, consentCategory: .analytics, properties: [
            EventSchema.Property(name: "reason", typeName: committed?.typeName ?? "", isOptional: false, enumeration: committed),
        ])])
        let sut = try TrackingPlan(schemas: [EventSchema(name: "failed", version: 1, consentCategory: .analytics, properties: [
            EventSchema.Property(name: "reason", typeName: current?.typeName ?? "", isOptional: false, enumeration: current),
        ])])
        let expected = TrackingPlanCheck.breaking([
            .constraintTightened(event: "failed", version: 1, property: "reason", keyword: "enum", committed: before, current: after),
        ])

        let actual = sut.check(against: committedPlan.files)

        #expect(actual == expected)
    }

    enum Stock: String, Codable, CaseIterable {
        case paymentDeclined
        case outOfStock
    }

    @Test("Turning a String property into an enum is breaking, from a pattern or from no constraint at all")
    func stringBecomesEnum() throws {
        let committedPlan = try TrackingPlan(schemas: [EventSchema(name: "failed", version: 1, consentCategory: .analytics, properties: [
            EventSchema.Property(name: "reason", typeName: "String", isOptional: false, keywords: [.pattern("^(paymentDeclined|outOfStock)$", example: "paymentDeclined")]),
            EventSchema.Property(name: "plain", typeName: "String", isOptional: false),
        ])])
        let sut = try TrackingPlan(schemas: [EventSchema(name: "failed", version: 1, consentCategory: .analytics, properties: [
            EventSchema.Property(name: "reason", typeName: "Stock", isOptional: false, enumeration: EventSchema.Enumeration(cases: Stock.allCases)),
            EventSchema.Property(name: "plain", typeName: "Stock", isOptional: false, enumeration: EventSchema.Enumeration(cases: Stock.allCases)),
        ])])
        let expected = TrackingPlanDifference.constraintTightened(event: "failed", version: 1, property: "reason", keyword: "enum", committed: nil, current: #"["paymentDeclined", "outOfStock"]"#)
        let expectedPlain = TrackingPlanDifference.constraintTightened(event: "failed", version: 1, property: "plain", keyword: "enum", committed: nil, current: #"["paymentDeclined", "outOfStock"]"#)

        let actual = sut.check(against: committedPlan.files)

        guard case .breaking(let differences) = actual else {
            Issue.record("Expected a breaking check, got \(actual)")
            return
        }
        #expect(differences.contains(expected))
        #expect(differences.contains(expectedPlain))
    }

    @Test("A type the plan couldn't map that becomes an enum it lists is breaking, as any value was allowed")
    func anyValueBecomesEnum() throws {
        let committedPlan = try TrackingPlan(schemas: [EventSchema(name: "failed", version: 1, consentCategory: .analytics, properties: [
            EventSchema.Property(name: "reason", typeName: "Stock", isOptional: false),
        ])])
        let sut = try TrackingPlan(schemas: [EventSchema(name: "failed", version: 1, consentCategory: .analytics, properties: [
            EventSchema.Property(name: "reason", typeName: "Stock", isOptional: false, enumeration: EventSchema.Enumeration(cases: Stock.allCases)),
        ])])
        let expected = TrackingPlanCheck.breaking([
            .propertyRetyped(event: "failed", version: 1, property: "reason", committed: #"{"x-traffluent-swift-type": "Stock"}"#, current: #"{"type": "string"}"#),
        ])

        let actual = sut.check(against: committedPlan.files)

        #expect(actual == expected)
    }

    @Test("Adding a case, or no longer listing them, only leaves the plan out of date", arguments: [
        (EventSchema.Enumeration(cases: AB.allCases), EventSchema.Enumeration(cases: ABC.allCases), #"["a", "b"]"# as String?, #"["a", "b", "c"]"# as String?),
        (EventSchema.Enumeration(cases: AB.allCases), EventSchema.Enumeration(cases: [AB]()), #"["a", "b"]"#, nil),
        (EventSchema.Enumeration(cases: Level.allCases), EventSchema.Enumeration(cases: Levels.allCases), "[0]", "[0, 1]"),
    ])
    func loosened(committed: EventSchema.Enumeration?, current: EventSchema.Enumeration?, before: String?, after: String?) throws {
        let committedPlan = try TrackingPlan(schemas: [EventSchema(name: "failed", version: 1, consentCategory: .analytics, properties: [
            EventSchema.Property(name: "reason", typeName: committed?.typeName ?? "", isOptional: false, enumeration: committed),
        ])])
        let sut = try TrackingPlan(schemas: [EventSchema(name: "failed", version: 1, consentCategory: .analytics, properties: [
            EventSchema.Property(name: "reason", typeName: current?.typeName ?? "", isOptional: false, enumeration: current),
        ])])
        let expected = TrackingPlanCheck.outOfDate([
            .constraintLoosened(event: "failed", version: 1, property: "reason", keyword: "enum", committed: before, current: after),
        ])

        let actual = sut.check(against: committedPlan.files)

        #expect(actual == expected)
    }

    @Test("An optional enum's null isn't a raw value: adding a case to one is loosened, with null in neither list")
    func optionalCaseAdded() throws {
        let committedPlan = try TrackingPlan(schemas: [EventSchema(name: "failed", version: 1, consentCategory: .analytics, properties: [
            EventSchema.Property(name: "reason", typeName: "AB", isOptional: true, enumeration: EventSchema.Enumeration(cases: AB.allCases)),
        ])])
        let sut = try TrackingPlan(schemas: [EventSchema(name: "failed", version: 1, consentCategory: .analytics, properties: [
            EventSchema.Property(name: "reason", typeName: "ABC", isOptional: true, enumeration: EventSchema.Enumeration(cases: ABC.allCases)),
        ])])
        let expected = TrackingPlanCheck.outOfDate([
            .constraintLoosened(event: "failed", version: 1, property: "reason", keyword: "enum", committed: #"["a", "b"]"#, current: #"["a", "b", "c"]"#),
        ])

        let actual = sut.check(against: committedPlan.files)

        #expect(actual == expected)
    }

    @Test("Removing a case of an array's elements is breaking as a tightened enum, not a retyping")
    func arrayCaseRemoved() throws {
        let committedPlan = try TrackingPlan(schemas: [EventSchema(name: "failed", version: 1, consentCategory: .analytics, properties: [
            EventSchema.Property(name: "reasons", typeName: "[ABC]", isOptional: false, enumeration: EventSchema.Enumeration(cases: ABC.allCases)),
        ])])
        let sut = try TrackingPlan(schemas: [EventSchema(name: "failed", version: 1, consentCategory: .analytics, properties: [
            EventSchema.Property(name: "reasons", typeName: "[AB]", isOptional: false, enumeration: EventSchema.Enumeration(cases: AB.allCases)),
        ])])
        let expected = TrackingPlanCheck.breaking([
            .constraintTightened(event: "failed", version: 1, property: "reasons", keyword: "enum", committed: #"["a", "b", "c"]"#, current: #"["a", "b"]"#),
        ])

        let actual = sut.check(against: committedPlan.files)

        #expect(actual == expected)
    }

    @Test("Reordering the cases changes no raw value: the plan's files are only out of date")
    func reordered() throws {
        let committedPlan = try TrackingPlan(schemas: [EventSchema(name: "failed", version: 1, consentCategory: .analytics, properties: [
            EventSchema.Property(name: "reason", typeName: "AB", isOptional: false, enumeration: EventSchema.Enumeration(cases: AB.allCases)),
        ])])
        let sut = try TrackingPlan(schemas: [EventSchema(name: "failed", version: 1, consentCategory: .analytics, properties: [
            EventSchema.Property(name: "reason", typeName: "BA", isOptional: false, enumeration: EventSchema.Enumeration(cases: BA.allCases)),
        ])])
        let expected = TrackingPlanCheck.outOfDate([.fileOutOfDate(path: "failed.v1.example.json"), .fileOutOfDate(path: "failed.v1.schema.json")])

        let actual = sut.check(against: committedPlan.files)

        #expect(actual == expected)
    }

    @Test("An enum declared in the event, renamed case and all, reaches the check through @Event's schema")
    func renamedThroughMacro() throws {
        let committedPlan = try TrackingPlan(schemas: [Committed.schema])
        let sut = try TrackingPlan(schemas: [Renamed.schema])
        let expected = TrackingPlanCheck.breaking([
            .constraintTightened(event: "checkout_failed", version: 1, property: "reason", keyword: "enum", committed: #"["paymentDeclined", "outOfStock"]"#, current: #"["paymentDeclined", "soldOut"]"#),
        ])

        let actual = sut.check(against: committedPlan.files)

        #expect(actual == expected)
    }

    enum Tagged<Tag>: String, CaseIterable {
        case a
    }

    @Test("A generic enum is found by its name and generic arguments, its module and enclosing types left out")
    func genericEnum() throws {
        let enumeration = EventSchema.Enumeration(cases: Tagged<Int>.allCases)
        let sut = try TrackingPlan(schemas: [EventSchema(name: "tagged", version: 1, consentCategory: .analytics, properties: [
            EventSchema.Property(name: "tag", typeName: "Plans.Tagged<Int>", isOptional: false, enumeration: enumeration),
            EventSchema.Property(name: "other", typeName: "Tagged<String>", isOptional: false, enumeration: enumeration),
        ])])
        let expected: JSONValue = [
            "tag": ["type": "string", "enum": ["a"]],
            "other": ["x-traffluent-swift-type": "Tagged<String>"],
        ]

        let document = try JSONValue.parse(String(decoding: try #require(sut.files.first { $0.path.hasSuffix(".schema.json") }).contents, as: UTF8.self))
        let actual = document.object?["properties"]

        #expect(actual == expected)
    }

    @Test("Removing a case of a nested array's elements is breaking as a tightened enum, not a retyping")
    func nestedArrayCaseRemoved() throws {
        let committedPlan = try TrackingPlan(schemas: [EventSchema(name: "failed", version: 1, consentCategory: .analytics, properties: [
            EventSchema.Property(name: "reasons", typeName: "[[ABC]]", isOptional: false, enumeration: EventSchema.Enumeration(cases: ABC.allCases)),
        ])])
        let sut = try TrackingPlan(schemas: [EventSchema(name: "failed", version: 1, consentCategory: .analytics, properties: [
            EventSchema.Property(name: "reasons", typeName: "[[AB]]", isOptional: false, enumeration: EventSchema.Enumeration(cases: AB.allCases)),
        ])])
        let expected = TrackingPlanCheck.breaking([
            .constraintTightened(event: "failed", version: 1, property: "reasons", keyword: "enum", committed: #"["a", "b", "c"]"#, current: #"["a", "b"]"#),
        ])

        let actual = sut.check(against: committedPlan.files)

        #expect(actual == expected)
    }

    /// A raw-representable value of any raw value, so a test can make an enumeration of any cases.
    struct AnyCase: RawRepresentable {
        var rawValue: String
    }

    @Test("Any change to the raw values is tightened when a committed one is gone, loosened when they were only added to, and no enum difference when they are the same set", .tags(.randomized))
    func classification() async throws {
        await propertyCheck(count: 300, input: Gen.int(in: 0 ... 4).array(of: 1 ... 6), Gen.int(in: 0 ... 4).array(of: 1 ... 6)) { committedIndices, currentIndices in
            let names = ["a", "b", "c", "d", "e"]
            let committed = committedIndices.map { AnyCase(rawValue: names[$0]) }
            let current = currentIndices.map { AnyCase(rawValue: names[$0]) }
            let committedPlan = try TrackingPlan(schemas: [EventSchema(name: "failed", version: 1, consentCategory: .analytics, properties: [
                EventSchema.Property(name: "reason", typeName: "AnyCase", isOptional: false, enumeration: EventSchema.Enumeration(cases: committed)),
            ])])
            let sut = try TrackingPlan(schemas: [EventSchema(name: "failed", version: 1, consentCategory: .analytics, properties: [
                EventSchema.Property(name: "reason", typeName: "AnyCase", isOptional: false, enumeration: EventSchema.Enumeration(cases: current)),
            ])])
            // The naive reference: the two lists as sets, each value written once in first-seen order.
            let committedSet = Set(committed.map(\.rawValue))
            let currentSet = Set(current.map(\.rawValue))
            var seenCommitted = Set<String>()
            var seenCurrent = Set<String>()
            let before = "[" + committed.map(\.rawValue).filter { seenCommitted.insert($0).inserted }.map { "\"\($0)\"" }.joined(separator: ", ") + "]"
            let after = "[" + current.map(\.rawValue).filter { seenCurrent.insert($0).inserted }.map { "\"\($0)\"" }.joined(separator: ", ") + "]"
            let expected: [TrackingPlanDifference] = committedSet == currentSet ? []
                : committedSet.isSubset(of: currentSet)
                ? [.constraintLoosened(event: "failed", version: 1, property: "reason", keyword: "enum", committed: before, current: after)]
                : [.constraintTightened(event: "failed", version: 1, property: "reason", keyword: "enum", committed: before, current: after)]
            let expectedBreaking = !committedSet.isSubset(of: currentSet)
            func isFileDifference(_ difference: TrackingPlanDifference) -> Bool {
                if case .fileOutOfDate = difference { return true }
                return false
            }

            let check = sut.check(against: committedPlan.files)

            let actual = check.differences.filter { !isFileDifference($0) }
            let actualBreaking = check.differences.contains(where: \.isBreaking)
            #expect(actual == expected)
            #expect(actualBreaking == expectedBreaking)
        }
    }

    @Event(name: "checkout_failed")
    struct Committed {
        enum Reason: String, Codable {
            case paymentDeclined
            case outOfStock
        }
        var reason: Reason
    }

    @Event(name: "checkout_failed")
    struct Renamed {
        enum Reason: String, Codable {
            case paymentDeclined
            case soldOut
        }
        var reason: Reason
    }
}
