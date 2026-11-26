# ``Checksums``

The CRC-32 checksum of raw bytes, as zlib, PNG, gzip and Ethernet compute it.

## Overview

``CRC32`` is the reflected CRC with polynomial `0xEDB88320`, and an initial value and final XOR of
`0xFFFFFFFF`. `"123456789"` checksums to `0xCBF43926`, the algorithm's standard check value.
Give it bytes in as many pieces as you like with ``CRC32/update(with:)``: the checksum is the same
as for all of them at once, which ``CRC32/checksum(of:)`` computes in one call.

`SegmentStore`, in the `Persistence` module, checks each frame of its segment files with it as it
reads them back. Reach for it when you need the same check on bytes of your own, such as a store
you write. It detects accidental corruption, and gives no protection against bytes changed on
purpose.

```swift
let header = Data("TRAF".utf8)
let payload = Data("123456789".utf8)
var crc = CRC32()
header.withUnsafeBytes { crc.update(with: $0) }
payload.withUnsafeBytes { crc.update(with: $0) }
let whole = (header + payload).withUnsafeBytes { CRC32.checksum(of: $0) }
let matches = crc.checksum == whole  // true
```

The umbrella guide on this area is
[Persisting Records](https://tyler-keith-thompson.github.io/Traffluent/documentation/traffluent/persistingrecords).

## Topics

### Checksums

- ``CRC32``
