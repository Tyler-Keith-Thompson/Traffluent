// Property tests against a naive reference: a constraint accepts exactly the values its keyword's
// definition does, and a refined value is made exactly when every constraint accepts it.

import Events
import PropertyBased
import Testing
import TraffluentTestSupport

@Suite("Refined: properties")
struct RefinedPropertyTests {
    enum Bounded: Refinement {
        static let constraints: [Constraint<Int>] = [.minimum(-50), .maximum(50)]
    }

    enum Short: Refinement {
        static let constraints: [Constraint<[Int]>] = [.minItems(2), .maxItems(5)]
    }

    @Test("A length or a count bound accepts what counting does", .tags(.randomized))
    func lengths() async {
        await propertyCheck(count: 300, input: Gen.uint8().array(of: 0 ... 12), Gen.int(in: 0 ... 12)) { bytes, bound in
            let text = String(decoding: bytes.map { $0 % 128 }, as: UTF8.self)
            let scalars = text.unicodeScalars.count

            #expect(Constraint<String>.minLength(bound).isSatisfied(by: text) == (scalars >= bound))
            #expect(Constraint<String>.maxLength(bound).isSatisfied(by: text) == (scalars <= bound))
            #expect(Constraint<[UInt8]>.minItems(bound).isSatisfied(by: bytes) == (bytes.count >= bound))
            #expect(Constraint<[UInt8]>.maxItems(bound).isSatisfied(by: bytes) == (bytes.count <= bound))
        }
    }

    @Test("A numeric bound accepts what comparing does", .tags(.randomized))
    func bounds() async {
        await propertyCheck(count: 300, input: Gen.int(in: -1000 ... 1000), Gen.int(in: -1000 ... 1000)) { value, bound in
            let double = Double(value) / 8
            let doubleBound = Double(bound) / 8

            #expect(Constraint<Int>.minimum(bound).isSatisfied(by: value) == (value >= bound))
            #expect(Constraint<Int>.maximum(bound).isSatisfied(by: value) == (value <= bound))
            #expect(Constraint<Double>.minimum(doubleBound).isSatisfied(by: double) == (double >= doubleBound))
            #expect(Constraint<Double>.maximum(doubleBound).isSatisfied(by: double) == (double <= doubleBound))
        }
    }

    @Test("A pattern of one letter class accepts a string that holds one of its letters", .tags(.randomized))
    func pattern() async {
        await propertyCheck(count: 200, input: Gen.uint8().array(of: 0 ... 8)) { bytes in
            let text = String(decoding: bytes.map { 0x61 + $0 % 6 }, as: UTF8.self)
            let sut = Constraint<String>.pattern("[a-c]", example: "a")

            #expect(sut.isSatisfied(by: text) == text.contains { "abc".contains($0) })
        }
    }

    @Test("A refined value is made exactly when every constraint accepts it, else the first broken throws", .tags(.randomized))
    func refined() async {
        await propertyCheck(count: 300, input: Gen.int(in: -100 ... 100), Gen.int(in: 0 ... 8)) { value, count in
            let elements = Array(repeating: value, count: count)
            let expectedNumber: UnsatisfiedConstraint? = value < -50 ? .minimum : value > 50 ? .maximum : nil
            let expectedCount: UnsatisfiedConstraint? = count < 2 ? .minItems : count > 5 ? .maxItems : nil

            let actualNumber = Result { () throws(UnsatisfiedConstraint) in try Refined<Int, Bounded>(checked: value) }
            let actualCount = Result { () throws(UnsatisfiedConstraint) in try Refined<[Int], Short>(checked: elements) }

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
