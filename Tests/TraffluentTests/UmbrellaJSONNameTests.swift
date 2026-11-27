// `import Traffluent` declares no top-level `JSON`, so a file that imports the umbrella can name a
// `JSON` of its own unqualified. This file declares one and imports no other module of the
// library. A declaration in the file's own module shadows an imported one, so the case this file
// can't show, a `JSON` imported from another module beside the umbrella, is pinned in Bazel by
// //Tests/CompileFailures:UmbrellaBesideOtherJSONControl and its counterpart.

import Testing
import Traffluent

/// An app's own JSON type, named as SwiftyJSON's and GenericJSON's are.
private struct JSON: Equatable {
    var text: String
}

@Suite("The umbrella import and an app's own JSON", .timeLimit(.minutes(1)))
struct UmbrellaJSONNameTests {
    @Test("A file that imports Traffluent names its own top-level JSON without qualification")
    func ownJSONUnqualified() {
        let expected = JSON(text: "{}")

        let actual = JSON(text: "{}")

        #expect(actual == expected)
    }
}
