// Pure parsing, the same on every Apple platform; run on the Mac with the rest of this target.
#if os(macOS)
import AutomaticScreenTracking
import PropertyBased
import Testing
import TraffluentTestSupport

@Suite("TypeName properties")
struct TypeNamePropertyTests {
    @Test("Parsing a name written from a tree of SwiftUI wrappers around an app's view gives the tree back, and its screen name is the view's", .tags(.randomized))
    func roundTrip() async {
        await propertyCheck(count: 300, input: Gen.int(in: 0 ... 4).array(of: 0 ... 8), Gen.int(in: 0 ... 99)) { wrappers, number in
            // The naive reference: the tree built directly, and written out by hand.
            let view = TypeName(qualifiedName: "MyApp.Screen\(number)")
            let expectedName = "Screen\(number)"
            var expected = view
            for wrapper in wrappers {
                switch wrapper {
                case 0: expected = TypeName(qualifiedName: "SwiftUI.ModifiedContent", arguments: [expected, TypeName(qualifiedName: "SwiftUI._PaddingLayout")])
                case 1: expected = TypeName(qualifiedName: "Swift.Optional", arguments: [expected])
                case 2: expected = TypeName(qualifiedName: "SwiftUI.ParameterizedLazyView", arguments: [TypeName(qualifiedName: "Swift.Int"), expected])
                case 3: expected = TypeName(qualifiedName: "SwiftUI.(unknown context at $1dbb9a8a4).AnyViewStorage", arguments: [expected])
                default: expected = TypeName(qualifiedName: "SwiftUI.TupleView", arguments: [TypeName(qualifiedName: "(SwiftUI.Text, SwiftUI.Text)"), expected])
                }
            }
            func written(_ name: TypeName) -> String {
                name.arguments.isEmpty ? name.qualifiedName : "\(name.qualifiedName)<\(name.arguments.map(written).joined(separator: ", "))>"
            }

            let actual = TypeName(parsing: written(expected))

            #expect(actual == expected)
            #expect(actual.screenName == expectedName)
        }
    }
}
#endif
