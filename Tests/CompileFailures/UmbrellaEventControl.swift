// Must compile: a file that imports Traffluent alone declares @Event structs, whose discovery
// records name LinkerSetsRuntime.LinkerSetRecord, the one type the umbrella re-exports from
// LinkerSetsRuntime, so the check below fails for LinkerSet and LinkerSetKind alone.

import Traffluent

@Event(name: "umbrella_opened")
struct UmbrellaOpened {
    var screen: String
}

struct Shelf {}

extension Shelf {
    @Event(name: "umbrella_shelf_opened")
    struct Opened {
        var screen: String
    }
}
