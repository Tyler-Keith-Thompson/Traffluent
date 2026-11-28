// Must not compile: an @Event struct in a type that is a private member of another type. The
// conformance @Event adds is an extension, which Swift places at file scope, where a private member
// type can't be seen (swiftlang/swift#77023), so the macro reports it at the attribute, saying which
// type to make fileprivate. EventDiscoveryVersionsTests declares the same struct in a fileprivate
// member type, which compiles and is discovered.

import EventMacros

private struct Suite {
    private enum EarlierVersions {
        @Event(name: "rated")
        struct Rated {
            var stars: Int
        }
    }
}
