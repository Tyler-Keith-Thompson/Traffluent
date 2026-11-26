// EventSchema.Enumeration: the raw values of a type's cases, given or read at run time, and the
// types that have none. Each test is self-contained.

import Events
import PropertyBased
import Testing
import TraffluentTestSupport

@Suite("EventSchema.Enumeration")
struct EventSchemaEnumerationTests {
    enum Reason: String, CaseIterable {
        case declined
        case outOfStock = "out_of_stock"
    }

    enum Priority: Int8, CaseIterable {
        case low = -1
        case high = 5
    }

    enum Channel: String {
        case email
    }

    enum Ratio: Double, CaseIterable {
        case half = 0.5
    }

    enum Large: UInt64, CaseIterable {
        case small = 1
        case huge = 9_223_372_036_854_775_808
    }

    enum Largest: UInt64, CaseIterable {
        case largest = 9_223_372_036_854_775_807
    }

    enum Extreme: Int64, CaseIterable {
        case lowest = -9_223_372_036_854_775_808
        case highest = 9_223_372_036_854_775_807
    }

    struct Code: RawRepresentable, Codable {
        var rawValue: String
    }

    enum Plain: CaseIterable {
        case a
    }

    enum Scale: Double {
        case one = 1
    }

    struct Holder {
        var reason: Reason
        var priority: Priority?
        var channels: [Channel]
        var secret: Sensitive<Reason>
        var nested: [Sensitive<Priority>?]?
        var ratio: Ratio
        var plain: Plain
        var scale: Scale
        var text: String
        var count: Int
        var code: Code
        var large: Large
    }

    struct AnyCase: RawRepresentable {
        var rawValue: String
    }

    @Test("Given cases, an enumeration holds their raw values in order, the enum's name and its raw type's")
    func givenCases() throws {
        let expectedRawValues: [EventSchema.Enumeration.RawValue] = [.string("declined"), .string("out_of_stock")]

        let actual = try #require(EventSchema.Enumeration(cases: Reason.allCases))

        #expect(actual.rawValues == expectedRawValues)
        #expect(actual.typeName == "Reason")
        #expect(actual.rawTypeName == "String")
    }

    @Test("An integer enum's raw values are integers, negative ones included")
    func integerCases() throws {
        let expectedRawValues: [EventSchema.Enumeration.RawValue] = [.integer(-1), .integer(5)]

        let actual = try #require(EventSchema.Enumeration(cases: Priority.allCases))

        #expect(actual.rawValues == expectedRawValues)
        #expect(actual.rawTypeName == "Int8")
    }

    @Test("A raw value repeated is listed once, where it first appears")
    func repeatedCases() throws {
        let expectedRawValues: [EventSchema.Enumeration.RawValue] = [.string("out_of_stock"), .string("declined")]

        let actual = try #require(EventSchema.Enumeration(cases: [Reason.outOfStock, .declined, .outOfStock]))

        #expect(actual.rawValues == expectedRawValues)
    }

    @Test("Given no cases, the raw values are unknown, and the raw type still known")
    func noCases() throws {
        let actual = try #require(EventSchema.Enumeration(cases: [Reason]()))

        #expect(actual.rawValues == nil)
        #expect(actual.rawTypeName == "String")
    }

    @Test("A UInt64 raw value past Int64.max leaves the raw values unknown; Int64.max itself is listed")
    func integerBeyondInt64() throws {
        let expectedLargest: [EventSchema.Enumeration.RawValue] = [.integer(Int64.max)]

        let large = try #require(EventSchema.Enumeration(cases: Large.allCases))
        let largest = try #require(EventSchema.Enumeration(cases: Largest.allCases))

        #expect(large.rawValues == nil)
        #expect(large.rawTypeName == "UInt64")
        #expect(largest.rawValues == expectedLargest)
    }

    @Test("Int64's range is listed to both ends: Int64.min and Int64.max")
    func integerBounds() throws {
        let expectedRawValues: [EventSchema.Enumeration.RawValue] = [.integer(Int64.min), .integer(Int64.max)]

        let actual = try #require(EventSchema.Enumeration(cases: Extreme.allCases))

        #expect(actual.rawValues == expectedRawValues)
    }

    @Test("A raw value that is neither a String nor a standard integer gives no enumeration")
    func unmappedRawType() {
        let actual = EventSchema.Enumeration(cases: Ratio.allCases)

        #expect(actual == nil)
    }

    @Test("Read at run time, a CaseIterable enum's cases are listed, through Optional, arrays and Sensitive")
    func runTime() throws {
        let expectedReason: [EventSchema.Enumeration.RawValue] = [.string("declined"), .string("out_of_stock")]
        let expectedPriority: [EventSchema.Enumeration.RawValue] = [.integer(-1), .integer(5)]

        let reason = try #require(EventSchema.Enumeration(of: \Holder.reason))
        let priority = try #require(EventSchema.Enumeration(of: \Holder.priority))
        let secret = try #require(EventSchema.Enumeration(of: \Holder.secret))
        let nested = try #require(EventSchema.Enumeration(of: \Holder.nested))

        #expect(reason.rawValues == expectedReason)
        #expect(priority.rawValues == expectedPriority)
        #expect(secret.rawValues == expectedReason)
        #expect(nested.rawValues == expectedPriority)
        #expect(nested.typeName == "Priority")
    }

    @Test("Read at run time, a raw-value type that isn't CaseIterable, an enum or a struct, has no enumeration, and neither has one whose raw values aren't all known")
    func runTimeWithoutCases() {
        let channels = EventSchema.Enumeration(of: \Holder.channels)
        let code = EventSchema.Enumeration(of: \Holder.code)
        let large = EventSchema.Enumeration(of: \Holder.large)

        #expect(channels == nil)
        #expect(code == nil)
        #expect(large == nil)
    }

    @Test("Read at run time, a type that isn't a raw-value enum the plan maps has no enumeration")
    func runTimeNone() {
        #expect(EventSchema.Enumeration(of: \Holder.ratio) == nil)
        #expect(EventSchema.Enumeration(of: \Holder.plain) == nil)
        #expect(EventSchema.Enumeration(of: \Holder.scale) == nil)
        #expect(EventSchema.Enumeration(of: \Holder.text) == nil)
        #expect(EventSchema.Enumeration(of: \Holder.count) == nil)
    }

    @Test("A schema property keeps the enumeration it is given, and has none by default")
    func propertyEnumeration() {
        let expected = EventSchema.Enumeration(cases: Reason.allCases)

        let actual = EventSchema.Property(name: "reason", typeName: "Reason", isOptional: false, enumeration: expected)
        let unset = EventSchema.Property(name: "reason", typeName: "String", isOptional: false)

        #expect(actual.enumeration == expected)
        #expect(expected != nil)
        #expect(unset.enumeration == nil)
    }

    @Test("Any list of cases gives their raw values each once, in first-seen order", .tags(.randomized))
    func rawValuesProperty() async {
        await propertyCheck(count: 300, input: Gen.int(in: 0 ... 5).array(of: 1 ... 10)) { indices in
            let names = ["a", "b", "c", "d", "e", "f"]
            let cases = indices.map { AnyCase(rawValue: names[$0]) }
            var expected: [EventSchema.Enumeration.RawValue] = []
            for index in indices where !expected.contains(.string(names[index])) {
                expected.append(.string(names[index]))
            }

            let actual = EventSchema.Enumeration(cases: cases)?.rawValues

            #expect(actual == expected)
        }
    }
}
