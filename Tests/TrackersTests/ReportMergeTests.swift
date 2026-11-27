import Events
import Foundation
import Testing
import Trackers

@Suite("Merging unread reports: counts saturate")
struct ReportMergeTests {
    @Test("A rejection report merged onto a count of Int.max stays at Int.max")
    func rejectionAtMax() {
        let violation = ConstraintViolation(property: "query", keyword: .minLength(1))
        let sut = RejectionReport(eventName: "Searched", violation: violation, recordCount: Int.max, timestamps: Date(timeIntervalSince1970: 1) ... Date(timeIntervalSince1970: 2))
        let later = RejectionReport(eventName: "Searched", violation: violation, recordCount: 1, timestamps: Date(timeIntervalSince1970: 3) ... Date(timeIntervalSince1970: 3))
        let expected = RejectionReport(eventName: "Searched", violation: violation, recordCount: Int.max, timestamps: Date(timeIntervalSince1970: 1) ... Date(timeIntervalSince1970: 3))

        let actual = sut.merged(with: later)

        #expect(actual == expected)
    }

    @Test("A rejection report's merged count is the sum up to Int.max, and Int.max past it")
    func rejectionBoundary() {
        let violation = ConstraintViolation(property: "query", keyword: .minLength(1))
        let time = Date(timeIntervalSince1970: 1)
        let sut = RejectionReport(eventName: "Searched", violation: violation, recordCount: Int.max - 2, timestamps: time ... time)
        let one = RejectionReport(eventName: "Searched", violation: violation, recordCount: 1, timestamps: time ... time)
        let three = RejectionReport(eventName: "Searched", violation: violation, recordCount: 3, timestamps: time ... time)
        let expectedBelow: Int = Int.max - 1
        let expectedSaturated: Int = Int.max

        let actualBelow = sut.merged(with: one).recordCount
        let actualSaturated = sut.merged(with: three).recordCount

        #expect(actualBelow == expectedBelow)
        #expect(actualSaturated == expectedSaturated)
    }

    @Test("A rejection report merged with a negative count stops at Int.min")
    func rejectionAtMin() {
        let violation = ConstraintViolation(property: "query", keyword: .minLength(1))
        let time = Date(timeIntervalSince1970: 1)
        let sut = RejectionReport(eventName: "Searched", violation: violation, recordCount: Int.min + 1, timestamps: time ... time)
        let minusOne = RejectionReport(eventName: "Searched", violation: violation, recordCount: -1, timestamps: time ... time)
        let minusTwo = RejectionReport(eventName: "Searched", violation: violation, recordCount: -2, timestamps: time ... time)
        let expectedExact: Int = Int.min
        let expectedSaturated: Int = Int.min

        let actualExact = sut.merged(with: minusOne).recordCount
        let actualSaturated = sut.merged(with: minusTwo).recordCount

        #expect(actualExact == expectedExact)
        #expect(actualSaturated == expectedSaturated)
    }

    @Test("A sampling drop report merged onto a count of Int.max stays at Int.max")
    func samplingAtMax() {
        let sut = SamplingDropReport(eventName: "Scrolled", recordCount: Int.max, timestamps: Date(timeIntervalSince1970: 2) ... Date(timeIntervalSince1970: 3))
        let later = SamplingDropReport(eventName: "Scrolled", recordCount: 1, timestamps: Date(timeIntervalSince1970: 1) ... Date(timeIntervalSince1970: 1))
        let expected = SamplingDropReport(eventName: "Scrolled", recordCount: Int.max, timestamps: Date(timeIntervalSince1970: 1) ... Date(timeIntervalSince1970: 3))

        let actual = sut.merged(with: later)

        #expect(actual == expected)
    }

    @Test("A sampling drop report's merged count is the sum up to Int.max, and Int.max past it")
    func samplingBoundary() {
        let time = Date(timeIntervalSince1970: 1)
        let sut = SamplingDropReport(eventName: "Scrolled", recordCount: Int.max - 1, timestamps: time ... time)
        let one = SamplingDropReport(eventName: "Scrolled", recordCount: 1, timestamps: time ... time)
        let two = SamplingDropReport(eventName: "Scrolled", recordCount: 2, timestamps: time ... time)
        let expectedExact: Int = Int.max
        let expectedSaturated: Int = Int.max
        let expectedBelow: Int = Int.max - 1

        let actualExact = sut.merged(with: one).recordCount
        let actualSaturated = sut.merged(with: two).recordCount
        let actualBelow = SamplingDropReport(eventName: "Scrolled", recordCount: Int.max - 3, timestamps: time ... time).merged(with: two).recordCount

        #expect(actualExact == expectedExact)
        #expect(actualSaturated == expectedSaturated)
        #expect(actualBelow == expectedBelow)
    }

    @Test("A held-record-limit report merged onto a count of Int.max stays at Int.max")
    func consentAtMax() {
        let sut = ConsentDropReport.heldRecordLimit(recordCount: Int.max, timestamps: Date(timeIntervalSince1970: 1) ... Date(timeIntervalSince1970: 2))
        let later = ConsentDropReport.heldRecordLimit(recordCount: 1, timestamps: Date(timeIntervalSince1970: 3) ... Date(timeIntervalSince1970: 3))
        let expected: ConsentDropReport? = .heldRecordLimit(recordCount: Int.max, timestamps: Date(timeIntervalSince1970: 1) ... Date(timeIntervalSince1970: 3))

        let actual = sut.merging(later)

        #expect(actual == expected)
    }

    @Test("A held-record-limit report's merged count is the sum up to Int.max, and Int.max past it")
    func consentBoundary() {
        let time = Date(timeIntervalSince1970: 1)
        let sut = ConsentDropReport.heldRecordLimit(recordCount: Int.max - 2, timestamps: time ... time)
        let one = ConsentDropReport.heldRecordLimit(recordCount: 1, timestamps: time ... time)
        let three = ConsentDropReport.heldRecordLimit(recordCount: 3, timestamps: time ... time)
        let expectedBelow: ConsentDropReport? = .heldRecordLimit(recordCount: Int.max - 1, timestamps: time ... time)
        let expectedSaturated: ConsentDropReport? = .heldRecordLimit(recordCount: Int.max, timestamps: time ... time)

        let actualBelow = sut.merging(one)
        let actualSaturated = sut.merging(three)

        #expect(actualBelow == expectedBelow)
        #expect(actualSaturated == expectedSaturated)
    }
}
