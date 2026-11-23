// The screen-name reading is the same on every Apple platform; these run on the Mac, and the
// SwiftUI values they read need SwiftUI, so elsewhere this target builds empty.
#if os(macOS)
import AutomaticScreenTracking
import SwiftUI
import Testing

@Suite("TypeName")
struct TypeNameTests {
    struct DetailView: View {
        var body: some View { Text("Detail") }
    }

    struct ListView<Item>: View {
        var body: some View { Text("List") }
    }

    struct Item {}

    enum Route {
        case detail(Int)
        case settings
    }

    @Test("Parsing splits a name into its qualified name and its generic arguments, in order")
    func parsing() {
        let text = "SwiftUI.ModifiedContent<MyApp.DetailView, SwiftUI._PaddingLayout>"
        let expected = TypeName(qualifiedName: "SwiftUI.ModifiedContent", arguments: [
            TypeName(qualifiedName: "MyApp.DetailView"),
            TypeName(qualifiedName: "SwiftUI._PaddingLayout"),
        ])

        let actual = TypeName(parsing: text)

        #expect(actual == expected)
    }

    @Test("Parsing keeps dots, commas and angle brackets inside parentheses in the name, and a function's arrow")
    func parentheses() {
        let text = "SwiftUI.(unknown context at $1dbb9a8a4).AnyViewStorage<(Swift.Int, Swift.String) -> MyApp.DetailView>"
        let expected = TypeName(qualifiedName: "SwiftUI.(unknown context at $1dbb9a8a4).AnyViewStorage", arguments: [
            TypeName(qualifiedName: "(Swift.Int, Swift.String) -> MyApp.DetailView"),
        ])

        let actual = TypeName(parsing: text)

        #expect(actual == expected)
    }

    @Test("Parsing the empty string gives an empty name")
    func empty() {
        let expected = TypeName(qualifiedName: "")

        let actual = TypeName(parsing: "")

        #expect(actual == expected)
    }

    @Test("Parsing text that isn't a type's name still gives a name, without trapping")
    func malformed() {
        let texts = [">", "<", ",", "A<", "A<B", "A<B,", "A>>B<<C", "((", "))", "A<(B>", "-><->"]

        for text in texts {
            _ = TypeName(parsing: text)
        }
    }

    @Test("Nesting past 64 generic arguments is kept as text, without exhausting the stack")
    func deepNesting() {
        let text = String(repeating: "A<", count: 100_000) + "B" + String(repeating: ">", count: 100_000)
        let expectedDepth = 64

        var actual = TypeName(parsing: text)
        var depth = 0
        while let argument = actual.arguments.first {
            actual = argument
            depth += 1
        }

        #expect(depth == expectedDepth)
    }

    @Test("The module is the first component, and the base name the last, outside parentheses")
    func components() {
        let name = TypeName(parsing: "SwiftUI.(unknown context at $1dbb9a8a4).AnyViewStorage")
        let expectedModule = "SwiftUI"
        let expectedBaseName = "AnyViewStorage"

        let actualModule = name.module
        let actualBaseName = name.baseName

        #expect(actualModule == expectedModule)
        #expect(actualBaseName == expectedBaseName)
    }

    @Test("A tuple or function type has no module, and its whole name is its base name, dots and all")
    func tupleComponents() {
        let tuple = TypeName(parsing: "(Swift.Int, Swift.String)")
        let function = TypeName(parsing: "(Swift.Int) -> MyApp.DetailView")
        let expectedModule = ""
        let expectedBaseName = "(Swift.Int, Swift.String)"

        let actualTupleModule = tuple.module
        let actualFunctionModule = function.module
        let actualBaseName = tuple.baseName

        #expect(actualTupleModule == expectedModule)
        #expect(actualFunctionModule == expectedModule)
        #expect(actualBaseName == expectedBaseName)
    }

    @Test("A type declared in a function is named without the discriminator String(reflecting:) adds")
    func localType() {
        let name = TypeName(parsing: "MyApp.(CheckoutView in _4F1A2B3C)")
        let expected = "CheckoutView"

        let actual = name.baseName

        #expect(actual == expected)
    }

    @Test("A description is the base name, and the arguments' the same way")
    func description() {
        let name = TypeName(parsing: "MyApp.Outer.ListView<MyApp.Item, Swift.Optional<Swift.Int>>")
        let expected = "ListView<Item, Optional<Int>>"

        let actual = name.description

        #expect(actual == expected)
    }

    @Test("A screen name skips SwiftUI's wrappers for the first app type inside them")
    func screenNameSkipsWrappers() {
        let name = TypeName(parsing: "SwiftUI.ModifiedContent<SwiftUI.ModifiedContent<MyApp.DetailView, SwiftUI._PaddingLayout>, MyApp.CardStyle>")
        let expected = "DetailView"

        let actual = name.screenName

        #expect(actual == expected)
    }

    @Test("A navigation destination's screen name is its content's, its last argument, not the presented value's type")
    func screenNameOfDestination() {
        let name = TypeName(parsing: "SwiftUI.ParameterizedLazyView<MyApp.Route, MyApp.DetailView>")
        let expected = "DetailView"

        let actual = name.screenName

        #expect(actual == expected)
    }

    @Test("A conditional, every SwiftUI type, a tuple and an empty name have no screen name")
    func noScreenName() {
        let texts = [
            "SwiftUI._ConditionalContent<MyApp.DetailView, MyApp.SettingsView>",
            "SwiftUI.ModifiedContent<SwiftUI.Text, SwiftUI._PaddingLayout>",
            "(MyApp.DetailView, MyApp.SettingsView)",
            "",
        ]

        for text in texts {
            let actual = TypeName(parsing: text).screenName

            #expect(actual == nil, "\(text)")
        }
    }

    @Test("A view's screen name is its own type's, without its module")
    func viewScreenName() {
        let view = DetailView()
        let expected = "DetailView"

        let actual = TypeName.screenName(ofView: view)

        #expect(actual == expected)
    }

    @Test("A modified view's screen name is the modified view's")
    func modifiedViewScreenName() {
        let view = DetailView().padding().background(Color.red)
        let expected = "DetailView"

        let actual = TypeName.screenName(ofView: view)

        #expect(actual == expected)
    }

    @Test("An AnyView's screen name is that of the view it erases")
    func anyViewScreenName() {
        let view = AnyView(AnyView(DetailView().padding()))
        let expected = "DetailView"

        let actual = TypeName.screenName(ofView: view)

        #expect(actual == expected)
    }

    @Test("A generic view's screen name has its arguments")
    func genericViewScreenName() {
        let view = ListView<Item>()
        let expected = "ListView<Item>"

        let actual = TypeName.screenName(ofView: view)

        #expect(actual == expected)
    }

    @Test("A conditional's screen name is that of the branch it took")
    func conditionalScreenName() {
        @ViewBuilder func view(showsDetail: Bool) -> some View {
            if showsDetail {
                Text("Settings")
            } else {
                DetailView()
            }
        }
        let expected = "DetailView"

        let actual = TypeName.screenName(ofView: view(showsDetail: false))

        #expect(actual == expected)
    }

    @Test("A view of SwiftUI's alone has no screen name")
    func swiftUIViewScreenName() {
        let view = AnyView(Text("Home").padding())

        let actual = TypeName.screenName(ofView: view)

        #expect(actual == nil)
    }
}
#endif
