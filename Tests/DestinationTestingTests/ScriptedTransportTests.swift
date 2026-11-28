import DestinationTesting
import Foundation
import HTTPDestinations
import HTTPTypes
import Testing

@Suite("ScriptedTransport")
struct ScriptedTransportTests {
    @Test("The nth request gets the script's nth answer, and every request past its end its last")
    func scriptInOrder() async throws {
        let sut = ScriptedTransport([.status(.serviceUnavailable), .status(.tooManyRequests), .status(.ok)])
        let request = HTTPRequest(method: .post, scheme: "https", authority: "example.com", path: "/")
        let expected: [HTTPResponse.Status] = [.serviceUnavailable, .tooManyRequests, .ok, .ok]
        var actual: [HTTPResponse.Status] = []

        for _ in expected {
            actual.append(try await sut.send(request, body: Data()).head.status)
        }

        #expect(actual == expected)
    }

    @Test("A copy of a transport shares its requests and its place in the script")
    func copiesShareRequests() async throws {
        let sut = ScriptedTransport([.status(.serviceUnavailable), .status(.ok)])
        let copy = sut
        let request = HTTPRequest(method: .post, scheme: "https", authority: "example.com", path: "/")
        let expectedBodies = [Data([1]), Data([2])]
        let expectedStatus = HTTPResponse.Status.ok

        _ = try await copy.send(request, body: Data([1]))
        let actualStatus = try await sut.send(request, body: Data([2])).head.status

        #expect(sut.requests.map(\.body) == expectedBodies)
        #expect(copy.requests.map(\.body) == expectedBodies)
        #expect(actualStatus == expectedStatus)
    }

    @Test("An empty script answers every request with 200")
    func emptyScript() async throws {
        let sut = ScriptedTransport([])
        let request = HTTPRequest(method: .post, scheme: "https", authority: "example.com", path: "/")
        let expected: [HTTPResponse.Status] = [.ok, .ok]
        var actual: [HTTPResponse.Status] = []

        for _ in expected {
            actual.append(try await sut.send(request, body: Data()).head.status)
        }

        #expect(actual == expected)
    }

    @Test("A scripted status answers with an empty body, and a scripted response with its body")
    func responseBodies() async throws {
        let body = Data(#"{"status":0}"#.utf8)
        let sut = ScriptedTransport([.status(.ok), .response(.accepted, body: body)])
        let request = HTTPRequest(method: .post, scheme: "https", authority: "example.com", path: "/")
        let expected = [
            HTTPTransportResponse(head: HTTPResponse(status: .ok), body: Data()),
            HTTPTransportResponse(head: HTTPResponse(status: .accepted), body: body),
        ]
        var actual: [HTTPTransportResponse] = []

        for _ in expected {
            actual.append(try await sut.send(request, body: Data()))
        }

        #expect(actual == expected)
    }

    @Test("A scripted noResponse throws failed, and the next answer follows it")
    func noResponse() async throws {
        let sut = ScriptedTransport([.noResponse, .status(.ok)])
        let request = HTTPRequest(method: .post, scheme: "https", authority: "example.com", path: "/")
        let expected = HTTPResponse.Status.ok

        await #expect(throws: HTTPTransportError.failed(reason: "scripted: no response")) {
            try await sut.send(request, body: Data())
        }
        let actual = try await sut.send(request, body: Data()).head.status

        #expect(actual == expected)
    }

    @Test("Every request is kept, in order, with its body, a failed one too")
    func requestsKept() async throws {
        let sut = ScriptedTransport([.noResponse, .status(.ok)])
        let request = HTTPRequest(method: .post, scheme: "https", authority: "example.com", path: "/")
        let expected = [Data("a".utf8), Data("b".utf8)]

        _ = try? await sut.send(request, body: expected[0])
        _ = try await sut.send(request, body: expected[1])

        let actual = sut.requests.map(\.body)
        #expect(actual == expected)
        #expect(sut.requests.map(\.request) == [request, request])
    }
}
