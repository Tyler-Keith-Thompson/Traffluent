// `import Traffluent` re-exports LinkerSetsRuntime's record type alone, so the set and its
// kinds, which Traffluent reads itself through DiscoveredEvent.all, are out of an adopter's scope.

import Traffluent

@Event(name: "umbrella_opened")
struct UmbrellaOpened {
    var screen: String
}

let kind = LinkerSetKind(rawValue: 0x6576_6E74)
let events = LinkerSet<any Event.Type>(kind: kind).values
