// `import Traffluent` re-exports LinkerSetsRuntime's record type alone, so the set and its
// kinds, which Traffluent reads itself through DiscoveredEvent.all, are out of an adopter's scope.
// The two underscored macros, @_DiscoverableEvent and #__eventRecord, are visible through the
// umbrella on purpose: @Event's expansion in an adopter's file calls #__eventRecord, so it must be
// in scope wherever @Event is, and the underscores keep both out of completion and the docs.

import Traffluent

@Event(name: "umbrella_opened")
struct UmbrellaOpened {
    var screen: String
}

let kind = LinkerSetKind(rawValue: 0x6576_6E74)
let events = LinkerSet<any Event.Type>(kind: kind).values
