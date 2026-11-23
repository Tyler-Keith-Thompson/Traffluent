// Exit tests, in a file of their own: each runs its body in a child process, which iOS, tvOS,
// watchOS and visionOS cannot start.

import Events
import Testing
import TrackingPlans
import TraffluentTestSupport

@Suite("TrackingPlan: traps", .timeLimit(.minutes(1)))
struct TrackingPlanExitTests {
    @Test("The plain spelling traps on a schema with no name", .tags(.precondition))
    func emptyName() async {
        await #expect(processExitsWith: .failure) {
            _ = TrackingPlan(schemas: [EventSchema(name: "", version: 1, consentCategory: .analytics, properties: [])])
        }
    }

    @Test("The plain spelling traps on a schema listing a property twice", .tags(.precondition))
    func duplicateProperty() async {
        await #expect(processExitsWith: .failure) {
            let property = EventSchema.Property(name: "plan", typeName: "String", isOptional: false)
            _ = TrackingPlan(schemas: [EventSchema(name: "signed_up", version: 1, consentCategory: .analytics, properties: [property, property])])
        }
    }

    @Test("The plain spelling traps on two schemas sharing a file", .tags(.precondition))
    func duplicateEvent() async {
        await #expect(processExitsWith: .failure) {
            _ = TrackingPlan(schemas: ["SignedUp", "signedup"].map {
                EventSchema(name: $0, version: 1, consentCategory: .analytics, properties: [])
            })
        }
    }
}
