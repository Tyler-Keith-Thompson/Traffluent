# ``Sessions``

Put every event a tracker tracks in a session, and sample whole sessions.

## Overview

Sessions are opt-in. Add the sessions enricher to the ones a tracker is built with, and the
tracker's worker sets each record's ``SessionKey`` to its session's identifier. A session goes on
while each event comes less than the timeout (30 minutes by default) after the one before it,
measured between the records' timestamps. The first event after a longer gap starts a new session.

The enricher tracks ``SessionStarted`` before each session's first event, and ``SessionEnded``
before that from the second session on, carrying the ended session's duration. A run's last session
has no ``SessionEnded``: a session ends only when an event comes after the timeout. Pass `kinds:` to
track only one kind of session event, or neither; every record still carries its key.

A session's identifier is a version 7 UUID: the session's start in Unix milliseconds, then random
bits. It is held in the enricher's memory only, never written to disk, and a new tracker, as on the
next launch, starts a new session. Records a store kept from an earlier run carry no key.

`Sampler.sessions(rate:)` keeps or drops every record of a session alike, its session events with
it, by the record's ``SessionKey``. It needs the sessions enricher among the tracker's enrichers.

For the app, device, operating system, locale and network an event was tracked on, use
`StandardContext`. For the app's opens and moves to the background, use `LifecycleTracking`:
its `ApplicationOpened` after a long time in the background starts a new session here, though
neither module knows about the other.

```swift
import Sessions
import Trackers

let tracker = Tracker(enrichers: [.sessions(timeout: .seconds(15 * 60), kinds: [.started])])
tracker.track(SignedUp(plan: "pro"))  // tracks SessionStarted, then SignedUp, both with the same SessionKey
```

The guide [Sessions and Standard Context](https://tyler-keith-thompson.github.io/Traffluent/documentation/traffluent/sessionsandstandardcontext)
covers sessions beside the standard context, and
[Sampling Events](https://tyler-keith-thompson.github.io/Traffluent/documentation/traffluent/samplingevents)
covers sampling.

## Topics

### Putting events in sessions

- ``Events/Enricher/sessions(timeout:kinds:file:fileID:function:line:column:)``
- ``Events/Enricher/sessions(checkedTimeout:kinds:file:fileID:function:line:column:)``
- ``SessionEventKind``
- ``NonPositiveSessionTimeout``

### Reading a record's session

- ``SessionKey``

### Session events

- ``SessionStarted``
- ``SessionEnded``

### Sampling whole sessions

- ``Trackers/Sampler/sessions(where:rate:)``
