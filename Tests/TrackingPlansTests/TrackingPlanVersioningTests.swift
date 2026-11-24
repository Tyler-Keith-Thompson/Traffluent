// The check against a plan exported from one release's @Event declarations, run on the next
// release's: a breaking change at the same version fails, naming the event, the property and the
// change; the same change with the version raised, and a compatible change that keeps it, don't.

import EventMacros
import Testing
import TrackingPlans

@Suite("TrackingPlan: versioning @Event declarations")
struct TrackingPlanVersioningTests {
    @Event(name: "checkout_started")
    struct Released {
        var cartSize: Int
        var coupon: String?
        var screen: String
    }

    @Event(name: "checkout_started")
    struct Retyped {
        var cartSize: Double
        var coupon: String?
        var screen: String
    }

    @Event(name: "checkout_started", version: 2)
    struct RetypedVersion2 {
        var cartSize: Double
        var coupon: String?
        var screen: String
    }

    @Event(name: "checkout_started")
    struct CouponRequired {
        var cartSize: Int
        var coupon: String
        var screen: String
    }

    @Event(name: "checkout_started")
    struct CurrencyRequired {
        var cartSize: Int
        var coupon: String?
        var screen: String
        var currency: String
    }

    @Event(name: "checkout_started")
    struct Compatible {
        var cartSize: Int
        var coupon: String?
        var referrer: String?
        var currency: String = "USD"
    }

    // Each schema with the line the check reports for it.
    static let breakingChanges: [(EventSchema, String)] = [
        (Retyped.schema, #"checkout_started v1: property "cartSize" changed type from {"type": "integer"} to {"type": "number"}"#),
        (CouponRequired.schema, #"checkout_started v1: property "coupon" was optional and is now required"#),
        (CurrencyRequired.schema, #"checkout_started v1: required property "currency" was added without a default value"#),
    ]

    @Test("Each breaking change at the same version fails the check, its line naming the event, the property and the change", arguments: breakingChanges)
    func breakingAtSameVersion(current: EventSchema, expectedLine: String) {
        let committed = TrackingPlan(schemas: [Released.schema]).files
        let sut = TrackingPlan(schemas: [current])

        let actual = sut.check(against: committed)

        #expect(actual == .breaking(actual.differences))
        #expect(actual.description.split(separator: "\n").contains { $0 == "  - " + expectedLine })
    }

    @Test("The same breaking change with the version raised passes the check, which reports only the raise")
    func breakingWithRaisedVersion() {
        let committed = TrackingPlan(schemas: [Released.schema]).files
        let sut = TrackingPlan(schemas: [RetypedVersion2.schema])
        let expected = TrackingPlanCheck.outOfDate([.versionRaised(event: "checkout_started", committed: 1, current: 2)])

        let actual = sut.check(against: committed)

        #expect(actual == expected)
    }

    @Test("Compatible changes at the same version pass the check: an optional property added, one with a default value added, one removed")
    func compatibleAtSameVersion() {
        let committed = TrackingPlan(schemas: [Released.schema]).files
        let sut = TrackingPlan(schemas: [Compatible.schema])
        let expected = TrackingPlanCheck.outOfDate([
            .defaultedPropertyAdded(event: "checkout_started", version: 1, property: "currency"),
            .optionalPropertyAdded(event: "checkout_started", version: 1, property: "referrer"),
            .propertyRemoved(event: "checkout_started", version: 1, property: "screen"),
        ])

        let actual = sut.check(against: committed)

        #expect(actual == expected)
    }
}
