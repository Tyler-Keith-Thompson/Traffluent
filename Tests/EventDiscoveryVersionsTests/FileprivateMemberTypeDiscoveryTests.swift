import EventMacros
import Events
import Testing

// An event in a fileprivate member type nested two levels deep in a private type, as a relay or a
// test suite declares an earlier version when @Event refuses a private member type there: the
// type is fileprivate, which the extension @Event adds at file scope can see. It compiles, and its
// record is in the binary. //Tests/CompileFailures:EventInPrivateMemberType holds the private
// member type that doesn't compile.
private struct Relay {
    fileprivate enum Fixtures {
        fileprivate enum EarlierVersions {
            @Event(name: "rated")
            struct Rated {
                var stars: Int
            }
        }
    }
}

@Suite("Events in fileprivate member types")
struct FileprivateMemberTypeDiscoveryTests {
    // Checked by the type rather than by the name alone, which other test targets' events share
    // where a build links several targets into one binary.
    @Test("An event in a fileprivate member type nested two levels deep in a private type is discovered at run time, as its own type")
    func discovered() {
        let expected = ObjectIdentifier(Relay.Fixtures.EarlierVersions.Rated.self)

        let actual = DiscoveredEvent.all.map { ObjectIdentifier($0.type) }

        #expect(actual.contains(expected))
    }
}
