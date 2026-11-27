# ``JSONValues``

A JSON value that renders to the same bytes on every platform and Swift release.

## Overview

``JSON`` is the value the library's JSON writers build: the documents of a tracking plan, and the
request bodies of the collector's, PostHog's and your own vendor's encoders. Its ``JSON/minified``
text has no whitespace and sorts object keys by their UTF-8 bytes, which is how JavaScript's
`JSON.stringify` writes it. Fixtures and committed plans can be compared byte for byte, and they
stay the same when the toolchain changes.

A number is a ``JSON/integer(_:)`` when it is a whole number that fits an `Int64`, and a
``JSON/number(_:)`` otherwise. ``JSON/number(exactly:)`` picks the case for a `Double`, and returns
`nil` for a NaN or an infinity, which have no JSON form. A ``JSON/number(_:)`` built from one
directly renders as `null`, as `JSON.stringify` writes it.

`import Traffluent` leaves this module out, so a file that imports the umbrella can declare or
import a `JSON` type of its own without qualifying it. A vendor module imports it beside
`PropertyJSON`, whose readers return it.

```swift
import JSONValues

let body: JSON = .object([
    "event": .string("signed_up"),
    "at": JSON.number(exactly: 1_500) ?? .null,
    "ratio": JSON.number(exactly: 0.25) ?? .null,
    "tags": .array([.string("pro"), .boolean(true)]),
])
let text = body.minified  // {"at":1500,"event":"signed_up","ratio":0.25,"tags":["pro",true]}
```

The guide [Writing a Vendor Destination](https://tyler-keith-thompson.github.io/Traffluent/documentation/traffluent/writingavendordestination)
builds request bodies with it.

## Topics

### JSON values

- ``JSON``
