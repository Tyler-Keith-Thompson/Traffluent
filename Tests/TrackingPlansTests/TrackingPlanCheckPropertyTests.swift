// Property tests of the check against a naive reference: any plan checks clean against its own
// export, any one breaking edit of it is reported as exactly the difference the edit makes, the
// same edit with the version raised breaks nothing, and any one compatible edit breaks nothing.

import Events
import PropertyBased
import Testing
import TrackingPlans

@Suite("TrackingPlan: check properties")
struct TrackingPlanCheckPropertyTests {
    // Each schema's type differs from the next one's, so changing a property's type to the next one
    // is always a retyping. (Sensitive<Int> would differ from Int by sensitivity alone, and two
    // integer types next to each other only by their bounds.)
    static let typeNames = ["String", "Int", "Double", "UInt8", "Bool", "Int32", "Date", "UUID", "[String]", "[Int?]", "Coordinate"]

    @Test("Any plan checks clean against its own files", .tags(.randomized))
    func clean() async {
        await propertyCheck(count: 200, input: Gen.int(in: 0 ... 10).array(of: 0 ... 6).array(of: 0 ... 4), Gen.bool.array(of: 24 ... 24), Gen.int(in: 1 ... 3)) { events, optionals, version in
            let schemas = events.enumerated().map { event, types in
                EventSchema(name: "e\(event)", version: version + event, consentCategory: .analytics, properties: types.enumerated().map { index, type in
                    EventSchema.Property(name: "p\(index)", typeName: TrackingPlanCheckPropertyTests.typeNames[type], isOptional: optionals[event * 6 + index])
                })
            }
            let sut = TrackingPlan(schemas: schemas)

            let actual = sut.check(against: sut.files)

            #expect(actual == .matches)
        }
    }

    @Test("Any one breaking edit is reported as its difference, and breaks the plan", .tags(.randomized))
    func breakingEdit() async {
        await propertyCheck(count: 300, input: Gen.int(in: 0 ... 10).array(of: 1 ... 6).array(of: 1 ... 4), Gen.bool.array(of: 24 ... 24), Gen.int(in: 0 ... 5), Gen.int(in: 0 ... 99), Gen.int(in: 0 ... 99)) { events, optionals, edit, eventChoice, propertyChoice in
            var committed = events.enumerated().map { event, types in
                EventSchema(name: "e\(event)", version: 1, consentCategory: .analytics, properties: types.enumerated().map { index, type in
                    EventSchema.Property(name: "p\(index)", typeName: TrackingPlanCheckPropertyTests.typeNames[type], isOptional: optionals[event * 6 + index])
                })
            }
            let event = eventChoice % committed.count
            let property = propertyChoice % committed[event].properties.count
            var current = committed
            let name = committed[event].name
            let propertyName = committed[event].properties[property].name
            // A retyping's line goes on to give both schemas, which the edit doesn't spell out, so
            // each edit's expected line is a prefix.
            let expectedPrefix: String
            switch edit {
            case 0:
                current[event].name += "_renamed"
                expectedPrefix = TrackingPlanDifference.eventRemoved(event: name, version: 1).description
            case 1:
                committed[event].properties[property].isOptional = false
                committed[event].properties[property].hasDefaultValue = true
                current[event].properties[property].isOptional = false
                expectedPrefix = TrackingPlanDifference.defaultValueRemoved(event: name, version: 1, property: propertyName).description
            case 2:
                let type = TrackingPlanCheckPropertyTests.typeNames.firstIndex(of: committed[event].properties[property].typeName) ?? 0
                current[event].properties[property].typeName = TrackingPlanCheckPropertyTests.typeNames[(type + 1) % TrackingPlanCheckPropertyTests.typeNames.count]
                expectedPrefix = "\(name) v1: property \"\(propertyName)\" changed type from "
            case 3:
                committed[event].properties[property].isOptional = true
                current[event].properties[property].isOptional = false
                expectedPrefix = TrackingPlanDifference.propertyMadeRequired(event: name, version: 1, property: propertyName).description
            case 4:
                committed[event].properties[property].typeName = "Sensitive<Int>"
                committed[event].properties[property].isOptional = false
                current[event].properties[property].typeName = "Int"
                current[event].properties[property].isOptional = false
                expectedPrefix = TrackingPlanDifference.sensitivePropertyMadeRequired(event: name, version: 1, property: propertyName).description
            default:
                current[event].properties.append(EventSchema.Property(name: "added", typeName: "Int", isOptional: false))
                expectedPrefix = TrackingPlanDifference.requiredPropertyAdded(event: name, version: 1, property: "added").description
            }
            let committedFiles = TrackingPlan(schemas: committed).files

            let actual = TrackingPlan(schemas: current).check(against: committedFiles)

            let breaking = actual.differences.filter(\.isBreaking)
            #expect(breaking.count == 1)
            #expect(breaking.first?.description.hasPrefix(expectedPrefix) == true)
            #expect(actual == .breaking(actual.differences))
        }
    }

    @Test("Any one breaking edit with the event's version raised breaks nothing: the check reports the raise", .tags(.randomized))
    func breakingEditWithRaisedVersion() async {
        await propertyCheck(count: 300, input: Gen.int(in: 0 ... 10).array(of: 1 ... 6).array(of: 1 ... 4), Gen.bool.array(of: 24 ... 24), Gen.int(in: 0 ... 4), Gen.int(in: 0 ... 99), Gen.int(in: 0 ... 99)) { events, optionals, edit, eventChoice, propertyChoice in
            var committed = events.enumerated().map { event, types in
                EventSchema(name: "e\(event)", version: 1, consentCategory: .analytics, properties: types.enumerated().map { index, type in
                    EventSchema.Property(name: "p\(index)", typeName: TrackingPlanCheckPropertyTests.typeNames[type], isOptional: optionals[event * 6 + index])
                })
            }
            let event = eventChoice % committed.count
            let property = propertyChoice % committed[event].properties.count
            var current = committed
            switch edit {
            case 0:
                committed[event].properties[property].isOptional = false
                committed[event].properties[property].hasDefaultValue = true
                current[event].properties[property].isOptional = false
            case 1:
                let type = TrackingPlanCheckPropertyTests.typeNames.firstIndex(of: committed[event].properties[property].typeName) ?? 0
                current[event].properties[property].typeName = TrackingPlanCheckPropertyTests.typeNames[(type + 1) % TrackingPlanCheckPropertyTests.typeNames.count]
            case 2:
                committed[event].properties[property].isOptional = true
                current[event].properties[property].isOptional = false
            case 3:
                committed[event].properties[property].typeName = "Sensitive<Int>"
                committed[event].properties[property].isOptional = false
                current[event].properties[property].typeName = "Int"
                current[event].properties[property].isOptional = false
            default:
                current[event].properties.append(EventSchema.Property(name: "added", typeName: "Int", isOptional: false))
            }
            current[event].version = 2
            let expected = TrackingPlanDifference.versionRaised(event: committed[event].name, committed: 1, current: 2)
            let committedFiles = TrackingPlan(schemas: committed).files

            let actual = TrackingPlan(schemas: current).check(against: committedFiles)

            #expect(actual == .outOfDate([expected]))
        }
    }

    @Test("Any one compatible edit keeps the version and breaks nothing: the check reports it as the difference it is", .tags(.randomized))
    func compatibleEdit() async {
        await propertyCheck(count: 300, input: Gen.int(in: 0 ... 10).array(of: 1 ... 6).array(of: 1 ... 4), Gen.bool.array(of: 24 ... 24), Gen.int(in: 0 ... 4), Gen.int(in: 0 ... 99), Gen.int(in: 0 ... 99)) { events, optionals, edit, eventChoice, propertyChoice in
            var committed = events.enumerated().map { event, types in
                EventSchema(name: "e\(event)", version: 1, consentCategory: .analytics, properties: types.enumerated().map { index, type in
                    EventSchema.Property(name: "p\(index)", typeName: TrackingPlanCheckPropertyTests.typeNames[type], isOptional: optionals[event * 6 + index])
                })
            }
            let event = eventChoice % committed.count
            let property = propertyChoice % committed[event].properties.count
            var current = committed
            let name = committed[event].name
            let propertyName = committed[event].properties[property].name
            let expected: TrackingPlanDifference
            switch edit {
            case 0:
                current[event].properties.append(EventSchema.Property(name: "added", typeName: "Int", isOptional: true))
                expected = .optionalPropertyAdded(event: name, version: 1, property: "added")
            case 1:
                current[event].properties.append(EventSchema.Property(name: "added", typeName: "Int", isOptional: false, hasDefaultValue: true))
                expected = .defaultedPropertyAdded(event: name, version: 1, property: "added")
            case 2:
                current[event].properties.remove(at: property)
                expected = .propertyRemoved(event: name, version: 1, property: propertyName)
            case 3:
                committed[event].properties[property].typeName = "Int"
                committed[event].properties[property].isOptional = false
                current[event].properties[property].typeName = "Sensitive<Int>"
                current[event].properties[property].isOptional = false
                expected = .sensitivityChanged(event: name, version: 1, property: propertyName, isSensitive: true)
            default:
                committed[event].properties[property].isOptional = false
                current[event].properties[property].isOptional = false
                current[event].properties[property].hasDefaultValue = true
                expected = .defaultValueAdded(event: name, version: 1, property: propertyName)
            }
            let committedFiles = TrackingPlan(schemas: committed).files

            let actual = TrackingPlan(schemas: current).check(against: committedFiles)

            #expect(actual == .outOfDate([expected]))
        }
    }
}
