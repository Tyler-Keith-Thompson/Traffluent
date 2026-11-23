import Events
import Testing

@Suite("EventSchema")
struct EventSchemaTests {
    @Test("A schema holds the name, version and properties it was made with, in order")
    func holdsItsParts() {
        let expectedProperties = [
            EventSchema.Property(name: "plan", typeName: "String", isOptional: false),
            EventSchema.Property(name: "seats", typeName: "Int", isOptional: true),
        ]

        let sut = EventSchema(name: "signed_up", version: 2, properties: expectedProperties)

        #expect(sut.name == "signed_up")
        #expect(sut.version == 2)
        #expect(sut.properties == expectedProperties)
    }

    @Test("A property holds its name, type name and optionality")
    func propertyHoldsItsParts() {
        let sut = EventSchema.Property(name: "seats", typeName: "Int", isOptional: true)

        #expect(sut.name == "seats")
        #expect(sut.typeName == "Int")
        #expect(sut.isOptional)
    }

    @Test("Schemas that differ in any part are unequal")
    func equality() {
        let property = EventSchema.Property(name: "plan", typeName: "String", isOptional: false)
        let sut = EventSchema(name: "signed_up", version: 1, properties: [property])
        let others = [
            EventSchema(name: "signed_in", version: 1, properties: [property]),
            EventSchema(name: "signed_up", version: 2, properties: [property]),
            EventSchema(name: "signed_up", version: 1, properties: []),
            EventSchema(name: "signed_up", version: 1, properties: [EventSchema.Property(name: "tier", typeName: "String", isOptional: false)]),
            EventSchema(name: "signed_up", version: 1, properties: [EventSchema.Property(name: "plan", typeName: "Int", isOptional: false)]),
            EventSchema(name: "signed_up", version: 1, properties: [EventSchema.Property(name: "plan", typeName: "String", isOptional: true)]),
        ]

        #expect(sut == EventSchema(name: "signed_up", version: 1, properties: [property]))
        for other in others {
            #expect(sut != other)
        }
    }
}
