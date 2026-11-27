import DiscoveryFixtures
import EventMacros
import Events
import Sessions
import Testing
import TrackingPlans

@Event(name: "discovery_plan_viewed")
struct DiscoveryPlanViewed {
    var plan: String
}

/// A hand-written event, which the plan describes only when its schema is listed.
struct DiscoveryPlannedByHand: Event, Codable {
    static let name = "discovery_planned_by_hand"
    static let schema = EventSchema(name: name, version: schemaVersion, consentCategory: consentCategory, properties: [])
}

/// A hand-written event of a discovered one's name and version.
struct DiscoveryPlanClash: Event, Codable {
    static let name = "discovery_plan_viewed"
    static let schema = EventSchema(name: name, version: schemaVersion, consentCategory: consentCategory, properties: [])
}

@Suite("Tracking plans of every discovered event")
struct DiscoveredTrackingPlanTests {
    @Test("TrackingPlan() describes the events of this module, of another module and of the library")
    func everyEvent() throws {
        let expected = [DiscoveryPlanViewed.schema, FixtureOpened.schema, SessionStarted.schema]

        let actual = try TrackingPlan().schemas

        #expect(expected.allSatisfy(actual.contains))
        #expect(!actual.contains { $0.name == DiscoveryPlannedByHand.name })
    }

    @Test("TrackingPlan() is the plan of DiscoveredEvent.all's schemas")
    func discoveredSchemas() throws {
        let expected = try TrackingPlan(schemas: DiscoveredEvent.all.map(\.schema))

        let actual = try TrackingPlan()

        #expect(actual == expected)
    }

    @Test("A hand-written event's schema listed beside the discovered ones is described too")
    func handWrittenListed() throws {
        let expected = DiscoveryPlannedByHand.schema

        let actual = try TrackingPlan(schemas: DiscoveredEvent.all.map(\.schema) + [DiscoveryPlannedByHand.schema]).schemas

        #expect(actual.contains(expected))
    }

    @Test("A hand-written schema of a discovered event's name and version makes the list throw duplicateEvent")
    func duplicate() {
        let schemas = DiscoveredEvent.all.map(\.schema) + [DiscoveryPlanClash.schema]
        let expected = TrackingPlanError.duplicateEvent("discovery_plan_viewed", version: 1, firstType: nil, secondType: nil)

        #expect(throws: expected) {
            try TrackingPlan(schemas: schemas)
        }
    }
}
