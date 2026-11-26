// Property tests against a naive reference: any schemas' documents list each property exactly once,
// require exactly the ones that are neither optional nor Sensitive, and are valid JSON Schema 2020-12.

import Events
import Foundation
import JSONSchema
import PropertyBased
import Testing
import TrackingPlans
import TraffluentTestSupport

@Suite("TrackingPlan: properties")
struct TrackingPlanPropertyTests {
    static let typeNames = ["String", "Int", "UInt8", "Int32", "Double", "Bool", "Date", "UUID", "[String]", "Sensitive<Int>", "Coordinate", "[Int: Int]"]

    @Test("Any schema's document lists every property once and requires exactly the non-optional ones that aren't Sensitive, in order", .tags(.randomized))
    func propertiesAndRequired() async throws {
        await propertyCheck(count: 200, input: Gen.int(in: 0 ... 11).array(of: 0 ... 12), Gen.bool.array(of: 12 ... 12), Gen.int(in: 1 ... 5)) { types, optionals, version in
            let properties = types.enumerated().map { index, type in
                EventSchema.Property(name: "p\(index)", typeName: TrackingPlanPropertyTests.typeNames[type], isOptional: optionals[index])
            }
            let sut = try TrackingPlan(schemas: [EventSchema(name: "event", version: version, consentCategory: .analytics, properties: properties)])
            let expectedNames = Set(properties.map(\.name))
            let expectedRequired = properties.filter { !$0.isOptional && !$0.typeName.hasPrefix("Sensitive<") }.map(\.name)
            let text = String(decoding: sut.files.last { $0.path.hasSuffix(".schema.json") }?.contents ?? [], as: UTF8.self)
            let document = try? JSONValue.parse(text)

            let actualNames = document?.object?["properties"]?.object.map { Array($0.keys) } ?? []
            let actualRequired = document?.object?["required"]?.array?.compactMap(\.string)

            #expect(actualNames.count == expectedNames.count)
            #expect(Set(actualNames) == expectedNames)
            #expect(actualRequired == expectedRequired)
            #expect(text.hasSuffix("}\n"))
        }
    }

    @Test("Any plan's documents are valid against draft 2020-12's meta-schema", .tags(.randomized))
    func metaSchema() async throws {
        let remotes = try Draft202012MetaSchema.documents.mapValues { try JSONValue.parse($0) }
        let metaSchema = try Schema(
            rawSchema: try #require(remotes[Draft202012MetaSchema.id]),
            context: Context(dialect: .draft2020_12, remoteSchema: remotes),
            baseURI: try #require(URL(string: Draft202012MetaSchema.id))
        )
        await propertyCheck(count: 100, input: Gen.int(in: 0 ... 11).array(of: 0 ... 6), Gen.bool.array(of: 6 ... 6), Gen.uint8().array(of: 1 ... 8)) { types, optionals, name in
            let properties = types.enumerated().map { index, type in
                EventSchema.Property(name: "p\(index)", typeName: TrackingPlanPropertyTests.typeNames[type], isOptional: optionals[index])
            }
            let sut = try TrackingPlan(schemas: [EventSchema(name: String(decoding: name, as: UTF8.self), version: 1, consentCategory: .analytics, properties: properties)])
            let document = try? JSONValue.parse(String(decoding: sut.files.last { $0.path.hasSuffix(".schema.json") }?.contents ?? [], as: UTF8.self))

            let actual = document.map { metaSchema.validate($0) }

            #expect(actual?.isValid == true)
        }
    }
}
