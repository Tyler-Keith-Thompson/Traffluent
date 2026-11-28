import EventMacros
import Foundation
import Instrumentation
import Persistence
import PropertyBased
import PropertyJSON
import Sessions
import Testing
import TraffluentTestSupport

// Private: its events share their names with other events of this test target, and @Event
// leaves a private type's events out of the link check of names (DefiningEvents, Limits).
@Suite("EventRecord: pseudonymous identity and deduplication ID")
private struct PseudonymousIdentityTests {
    @Event(name: "opened")
    struct Opened {}

    @Test("A record with a session is identified by its session")
    func session() throws {
        let session = UUID(uuidString: "00000000-0000-4000-8000-00000000000A")!
        var context = ServiceContext.topLevel
        context[SessionKey.self] = session
        let sut = EventRecord(event: Opened(), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil, context: context)
        let expected = PseudonymousIdentity.session(session)

        let actual = sut.pseudonymousIdentity

        #expect(actual == expected)
        #expect(actual.uuid == session)
    }

    @Test("A record with no session, from a tracker without the sessions enricher, is identified by its own identifier")
    func noSession() throws {
        let id = UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF")!
        let sut = EventRecord(id: id, event: Opened(), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil, isRedelivered: true)
        let expected = PseudonymousIdentity.record(id)

        let actual = sut.pseudonymousIdentity

        #expect(actual == expected)
        #expect(actual.uuid == id)
    }

    @Test("A record a store recovers after a relaunch has the identity, and the deduplication ID, it had when it was stored")
    func recoveredIdentity() throws {
        let directory = NSTemporaryDirectory() + "PseudonymousIdentityTests-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: directory) }
        let session = UUID(uuidString: "019A2B3C-4D5E-7F60-8172-839405A6B7C8")!
        var context = ServiceContext.topLevel
        context[SessionKey.self] = session
        let stored = EventRecord(event: Opened(), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil, context: context)
        _ = try SegmentStore(events: [Opened.self], directory: .init(directory)).append(stored)
        let expected = PseudonymousIdentity.session(session)

        let sut = try #require(try SegmentStore(events: [Opened.self], directory: .init(directory)).takeRecoveredRecords().first)

        #expect(sut.pseudonymousIdentity == expected)
        #expect(sut.deduplicationID == stored.deduplicationID)
    }

    @Test("The deduplication ID is the record's identifier in lowercase, which a redelivered record keeps")
    func deduplicationID() throws {
        let id = UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF")!
        let first = EventRecord(id: id, event: Opened(), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil)
        let redelivered = EventRecord(id: id, event: Opened(), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil, isRedelivered: true)
        let expected = "6f9619ff-8b86-d011-b42d-00c04fc964ff"

        let actualFirst = first.deduplicationID
        let actualRedelivered = redelivered.deduplicationID

        #expect(actualFirst == expected)
        #expect(actualRedelivered == expected)
    }

    @Test("For any record, the identity is its session when it has one and its own identifier otherwise, and the deduplication ID never changes with the session", .tags(.randomized))
    func identityModel() async {
        await propertyCheck(count: 200, input: Gen.uint64(), Gen.uint64().optional) { id, session in
            try check(id: id, session: session)
        }

        func check(id: UInt64, session: UInt64?) throws {
            let recordID = UUID(uuid: uuid(id))
            var context = ServiceContext.topLevel
            context[SessionKey.self] = session.map { UUID(uuid: uuid($0)) }
            let sut = EventRecord(id: recordID, event: Opened(), timestamp: Date(timeIntervalSince1970: 0), sourceLocation: nil, context: context)
            // The naive reference: the session's UUID if set, else the record's.
            let expectedUUID = session.map { UUID(uuid: uuid($0)) } ?? recordID
            let expectedIsSession = session != nil
            let expectedDeduplicationID = recordID.uuidString.lowercased()

            let actual = sut.pseudonymousIdentity

            let actualIsSession = if case .session = actual { true } else { false }
            #expect(actual.uuid == expectedUUID)
            #expect(actualIsSession == expectedIsSession)
            #expect(sut.deduplicationID == expectedDeduplicationID)
        }

        func uuid(_ value: UInt64) -> uuid_t {
            let bytes = withUnsafeBytes(of: value.bigEndian) { Array($0) }
            return (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], 0x40 | (bytes[6] & 0x0F), bytes[7], 0x80, 0, 0, 0, 0, 0, 0, 1)
        }
    }
}
