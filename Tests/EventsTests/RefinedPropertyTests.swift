// Property tests against a naive reference: a constraint accepts exactly the values its keyword's
// definition does, and a refined value is made exactly when every constraint accepts it.

import Events
import PropertyBased
import Testing
import TraffluentTestSupport

@Suite("Refined: properties")
struct RefinedPropertyTests {
    enum Bounded: Refinement {
        static var constraints: [Constraint<Int>] {
            get throws(InvalidConstraint) { try [.minimum(-50), .maximum(50)] }
        }
    }

    enum Short: Refinement {
        static var constraints: [Constraint<[Int]>] {
            get throws(InvalidConstraint) { try [.minItems(2), .maxItems(5)] }
        }
    }

    @Test("A length or a count bound accepts what counting does", .tags(.randomized))
    func lengths() async throws {
        await propertyCheck(count: 300, input: Gen.uint8().array(of: 0 ... 12), Gen.int(in: 0 ... 12)) { bytes, bound in
            let text = String(decoding: bytes.map { $0 % 128 }, as: UTF8.self)
            let scalars = text.unicodeScalars.count
            let minLength = try Constraint<String>.minLength(bound)
            let maxLength = try Constraint<String>.maxLength(bound)
            let minItems = try Constraint<[UInt8]>.minItems(bound)
            let maxItems = try Constraint<[UInt8]>.maxItems(bound)

            #expect(minLength.isSatisfied(by: text) == (scalars >= bound))
            #expect(maxLength.isSatisfied(by: text) == (scalars <= bound))
            #expect(minItems.isSatisfied(by: bytes) == (bytes.count >= bound))
            #expect(maxItems.isSatisfied(by: bytes) == (bytes.count <= bound))
        }
    }

    @Test("A numeric bound accepts what comparing does", .tags(.randomized))
    func bounds() async throws {
        await propertyCheck(count: 300, input: Gen.int(in: -1000 ... 1000), Gen.int(in: -1000 ... 1000)) { value, bound in
            let double = Double(value) / 8
            let doubleBound = Double(bound) / 8
            let minimum = try Constraint<Int>.minimum(bound)
            let maximum = try Constraint<Int>.maximum(bound)
            let doubleMinimum = try Constraint<Double>.minimum(doubleBound)
            let doubleMaximum = try Constraint<Double>.maximum(doubleBound)

            #expect(minimum.isSatisfied(by: value) == (value >= bound))
            #expect(maximum.isSatisfied(by: value) == (value <= bound))
            #expect(doubleMinimum.isSatisfied(by: double) == (double >= doubleBound))
            #expect(doubleMaximum.isSatisfied(by: double) == (double <= doubleBound))
        }
    }

    @Test("A pattern of one letter class accepts a string that holds one of its letters", .tags(.randomized))
    func pattern() async throws {
        await propertyCheck(count: 200, input: Gen.uint8().array(of: 0 ... 8)) { bytes in
            let text = String(decoding: bytes.map { 0x61 + $0 % 6 }, as: UTF8.self)
            let sut = try Constraint<String>.pattern("[a-c]", example: "a")

            #expect(sut.isSatisfied(by: text) == text.contains { "abc".contains($0) })
        }
    }

    @Test("A refined value is made exactly when every constraint accepts it, else the first broken throws", .tags(.randomized))
    func refined() async {
        await propertyCheck(count: 300, input: Gen.int(in: -100 ... 100), Gen.int(in: 0 ... 8)) { value, count in
            let elements = Array(repeating: value, count: count)
            let expectedNumber: UnsatisfiedConstraint? = value < -50 ? .minimum : value > 50 ? .maximum : nil
            let expectedCount: UnsatisfiedConstraint? = count < 2 ? .minItems : count > 5 ? .maxItems : nil

            let actualNumber = Result { () throws(UnsatisfiedConstraint) in try Refined<Int, Bounded>(value) }
            let actualCount = Result { () throws(UnsatisfiedConstraint) in try Refined<[Int], Short>(elements) }

            #expect(actualNumber.failure == expectedNumber)
            #expect(actualNumber.success?.value == (expectedNumber == nil ? value : nil))
            #expect(actualCount.failure == expectedCount)
        }
    }
}

extension Result {
    fileprivate var failure: Failure? {
        if case .failure(let error) = self { return error }
        return nil
    }

    fileprivate var success: Success? {
        if case .success(let value) = self { return value }
        return nil
    }
}
