import Foundation
#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif
import HTTPDestinations
import HTTPTypes
import Testing

@Suite("URLSessionTransport", .timeLimit(.minutes(1)))
struct URLSessionTransportTests {
    @Test("A request no server answers throws failed")
    func noServer() async throws {
        // Port 1 on the loopback interface has no listener, so the connection is refused at
        // once, without reaching the network.
        let url = try #require(URL(string: "http://127.0.0.1:1/batches"))
        let sut = URLSessionTransport()

        let actual = await #expect(throws: HTTPTransportError.self) {
            try await sut.send(HTTPRequest(method: .post, url: url), body: Data("a".utf8))
        }

        guard case .failed = actual else {
            Issue.record("Expected failed, got \(String(describing: actual))")
            return
        }
    }

    @Test("A failure's reason names the error's domain and code, and holds neither the endpoint's URL nor its key")
    func reasonWithoutURL() async throws {
        // Port 1 on the loopback interface has no listener, so the connection is refused at once.
        let url = try #require(URL(string: "http://127.0.0.1:1/v1?key=secret"))
        let sut = URLSessionTransport()
        let expectedDomain = NSURLErrorDomain

        let actual = await #expect(throws: HTTPTransportError.self) {
            try await sut.send(HTTPRequest(method: .post, url: url), body: Data("a".utf8))
        }

        guard case .failed(let reason) = actual else {
            Issue.record("Expected failed, got \(String(describing: actual))")
            return
        }
        #expect(reason.hasPrefix(expectedDomain))
        #expect(Int(reason.split(separator: " ").last ?? "") != nil)
        #expect(!reason.contains("127.0.0.1"))
        #expect(!reason.contains("secret"))
    }

    @Test("A send from a cancelled task throws cancelled")
    func cancelled() async throws {
        let url = try #require(URL(string: "http://127.0.0.1:1/batches"))
        let sut = URLSessionTransport()
        let expected = HTTPTransportError.cancelled
        let sending = Task { () async -> Result<HTTPResponse, HTTPTransportError> in
            withUnsafeCurrentTask { $0?.cancel() }
            do throws(HTTPTransportError) {
                return .success(try await sut.send(HTTPRequest(method: .post, url: url), body: Data("a".utf8)))
            } catch {
                return .failure(error)
            }
        }

        let actual = await sending.value

        #expect(actual == .failure(expected))
    }
}
