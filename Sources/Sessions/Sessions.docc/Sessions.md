# ``Sessions``

Put every event a tracker tracks in a session, and sample whole sessions.

## Overview

Sessions are opt-in. Add the sessions enricher to the ones a tracker is built with, and the
tracker's worker sets each record's ``/Events/SessionKey`` to its session's identifier. A session
goes on while each event comes less than the timeout (30 minutes by default) after the one before it,
measured between the records' timestamps. The first event after a longer gap starts a new session.

The enricher tracks ``SessionStarted`` before each session's first event, and ``SessionEnded``
before that from the second session on, carrying the ended session's duration. A run's last session
has no ``SessionEnded``: a session ends only when an event comes after the timeout. Pass `kinds:` to
track only one kind of session event, or neither; every record still carries its key.

A session's identifier is a version 7 UUID: the session's start in Unix milliseconds, then random
bits. The enricher holds it in memory only, and a new tracker, as on the next launch, starts a new
session. A store keeps it beside each record of the session, and it is deleted when the store
deletes the record's bytes (a `SegmentStore`: once its whole segment is delivered), so a record
recovered after a relaunch still carries the session it was tracked in. The key,
``/Events/SessionKey``, is in the `Events` module.

`Sampler.sessions(rate:)` keeps or drops every record of a session alike, its session events with
it, by the record's ``/Events/SessionKey``. It needs the sessions enricher among the tracker's
enrichers.

For the app, device, operating system, locale and network an event was tracked on, use
`StandardContext`. For the app's opens and moves to the background, use `LifecycleTracking`:
its `ApplicationOpened` after a long time in the background starts a new session here, though
neither module knows about the other.

```swift
import Sessions
import Trackers

let tracker = Tracker(enrichers: [try .sessions(timeout: .seconds(15 * 60), kinds: [.started])])
tracker.track(SignedUp(plan: "pro"))  // tracks SessionStarted, then SignedUp, both with the same SessionKey
```

The guide [Sessions and Standard Context](https://tyler-keith-thompson.github.io/Traffluent/documentation/traffluent/sessionsandstandardcontext)
covers sessions beside the standard context, and
[Sampling Events](https://tyler-keith-thompson.github.io/Traffluent/documentation/traffluent/samplingevents)
covers sampling.

## Topics

### Putting events in sessions

- ``Events/Enricher/sessions(kinds:file:fileID:function:line:column:)``
- ``Events/Enricher/sessions(timeout:kinds:file:fileID:function:line:column:)``
- ``SessionEventKind``
- ``NonPositiveSessionTimeout``

### Session events

- ``SessionStarted``
- ``SessionEnded``

### Sampling whole sessions

- ``Trackers/Sampler/sessions(where:rate:)``
