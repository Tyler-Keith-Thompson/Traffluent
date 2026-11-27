public import EventMacros

/// An event declared in this module, which no test names until it reads `DiscoveredEvent.all`.
@Event(name: "fixture_opened", version: 2)
public struct FixtureOpened {
    public var screen: String

    public init(screen: String) {
        self.screen = screen
    }
}
