import JSONValues
import PropertyBased
import PropertyJSON
import Testing
import TraffluentTestSupport

@Suite("[String: JSON].flattened(separator:)")
struct FlattenedTests {
    @Test("A hand-worked object flattens nested objects to dotted keys and arrays to indexed ones")
    func handWorked() throws {
        let sut: [String: JSON] = [
            "plan": .string("pro"),
            "device": .object(["model": .string("iPhone17,1"), "formFactor": .string("phone")]),
            "tags": .array([.string("beta"), .string("ios")]),
            "referrer": .null,
            "grid": .array([.array([.integer(1)]), .object(["x": .boolean(true)])]),
        ]
        let expected: [String: JSON] = [
            "plan": .string("pro"),
            "device.model": .string("iPhone17,1"),
            "device.formFactor": .string("phone"),
            "tags.0": .string("beta"),
            "tags.1": .string("ios"),
            "referrer": .null,
            "grid.0.0": .integer(1),
            "grid.1.x": .boolean(true),
        ]

        let actual = try sut.flattened()

        #expect(actual == expected)
    }

    @Test("The separator joins each level's names")
    func separator() throws {
        let sut: [String: JSON] = ["a": .object(["b": .array([.integer(1)])])]
        let expected: [String: JSON] = ["a_b_0": .integer(1)]

        let actual = try sut.flattened(separator: "_")

        #expect(actual == expected)
    }

    @Test("An empty dictionary, and an empty object or array inside one, flatten to nothing")
    func empty() throws {
        let sut: [String: JSON] = ["object": .object([:]), "array": .array([])]
        let expected: [String: JSON] = [:]

        let actualEmpty = try [String: JSON]().flattened()
        let actual = try sut.flattened()

        #expect(actualEmpty == expected)
        #expect(actual == expected)
    }

    @Test("A dictionary already flat is unchanged")
    func alreadyFlat() throws {
        let sut: [String: JSON] = ["a": .integer(1), "b": .number(0.5), "c": .string("x")]
        let expected = sut

        let actual = try sut.flattened()

        #expect(actual == expected)
    }

    @Test("Two values flattening to one key throw FlattenedKeyCollision naming it")
    func collision() {
        let sut: [String: JSON] = ["a.b": .integer(1), "a": .object(["b": .integer(2)])]
        let expected = FlattenedKeyCollision(key: "a.b")

        #expect(throws: expected) {
            try sut.flattened()
        }
    }

    @Test("The same keys with another separator don't collide")
    func noCollisionWithOtherSeparator() throws {
        let sut: [String: JSON] = ["a.b": .integer(1), "a": .object(["b": .integer(2)])]
        let expected: [String: JSON] = ["a.b": .integer(1), "a/b": .integer(2)]

        let actual = try sut.flattened(separator: "/")

        #expect(actual == expected)
    }

    @Test("For any two-level object, every scalar is kept under its path, and nothing else is", .tags(.randomized))
    func pathModel() async {
        await propertyCheck(count: 200, input: Gen.uint8(in: 0 ... 5).array(of: 0 ... 6)) { sizes in
            try check(sizes: sizes)
        }

        func check(sizes: [UInt8]) throws {
            // Member i is an array of sizes[i] integers when i is even, an object of them when odd.
            var sut: [String: JSON] = [:]
            var expected: [String: JSON] = [:]
            for (index, size) in sizes.enumerated() {
                let values = (0 ..< Int(size)).map { JSON.integer(Int64(index * 10 + $0)) }
                if index.isMultiple(of: 2) {
                    sut["m\(index)"] = .array(values)
                    for (offset, value) in values.enumerated() {
                        expected["m\(index).\(offset)"] = value
                    }
                } else {
                    sut["m\(index)"] = .object(Dictionary(uniqueKeysWithValues: values.enumerated().map { ("k\($0.offset)", $0.element) }))
                    for (offset, value) in values.enumerated() {
                        expected["m\(index).k\(offset)"] = value
                    }
                }
            }

            let actual = try sut.flattened()

            #expect(actual == expected)
        }
    }
}
