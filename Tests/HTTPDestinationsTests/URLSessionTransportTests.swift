// URLSessionTransport doesn't exist on WASI.
#if !os(WASI)
    import Foundation
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
#endif
