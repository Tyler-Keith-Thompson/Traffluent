import Destinations
import Events
import ExampleEvents
import ExampleServer
import Hummingbird
import HummingbirdTesting
import Pipelines
import Synchronization
import Testing

@Suite("The server example's routes and tracking", .timeLimit(.minutes(1)))
struct RequestTrackingMiddlewareTests {
    final class Recorder: Destination {
        let served = Mutex<[RequestServed]>([])

        func receive(_ batch: [EventRecord]) async {
            served.withLock { $0.append(contentsOf: batch.compactMap { $0.event as? RequestServed }) }
        }
    }

    @Test("A request for / is answered with the greeting")
    func greeting() async throws {
        let sut = Application(router: buildRouter(pipeline: Pipeline()))
        let expected = "Hello from Traffluent"

        let actual = try await sut.test(.router) { client in
            try await client.execute(uri: "/", method: .get) { response in
                String(buffer: response.body)
            }
        }

        #expect(actual == expected)
    }

    @Test("A served request is tracked with its path and the response's status")
    func tracksSuccess() async throws {
        let recorder = Recorder()
        let pipeline = Pipeline(recorder)
        let sut = Application(router: buildRouter(pipeline: pipeline))
        let expected = [RequestServed(path: "/items/7", status: 200)]

        try await sut.test(.router) { client in
            try await client.execute(uri: "/items/7?color=red", method: .get) { _ in }
        }
        pipeline.finish()
        try await pipeline.run().execute()

        let actual = recorder.served.withLock { $0 }
        #expect(actual == expected)
    }

    @Test("A request a route rejects is tracked with the error's status")
    func tracksFailure() async throws {
        let recorder = Recorder()
        let pipeline = Pipeline(recorder)
        let sut = Application(router: buildRouter(pipeline: pipeline))
        let expectedStatus = HTTPResponse.Status.badRequest
        let expected = [RequestServed(path: "/items/seven", status: 400)]

        let actualStatus = try await sut.test(.router) { client in
            try await client.execute(uri: "/items/seven", method: .get) { response in
                response.status
            }
        }
        pipeline.finish()
        try await pipeline.run().execute()

        let actual = recorder.served.withLock { $0 }
        #expect(actualStatus == expectedStatus)
        #expect(actual == expected)
    }

    @Test("Every request is tracked, in the order served")
    func tracksEach() async throws {
        let recorder = Recorder()
        let pipeline = Pipeline(recorder)
        let sut = Application(router: buildRouter(pipeline: pipeline))
        let expected = [
            RequestServed(path: "/", status: 200),
            RequestServed(path: "/items/1", status: 200),
        ]

        try await sut.test(.router) { client in
            try await client.execute(uri: "/", method: .get) { _ in }
            try await client.execute(uri: "/items/1", method: .get) { _ in }
        }
        pipeline.finish()
        try await pipeline.run().execute()

        let actual = recorder.served.withLock { $0 }
        #expect(actual == expected)
    }

    @Test("A middleware error without an HTTP status is tracked as 500")
    func tracksUnknownError() async throws {
        struct Broken: Error {}
        let recorder = Recorder()
        let pipeline = Pipeline(recorder)
        let router = Router()
        router.add(middleware: RequestTrackingMiddleware(pipeline: pipeline))
        router.get("/broken") { _, _ -> String in throw Broken() }
        let sut = Application(router: router)
        let expected = [RequestServed(path: "/broken", status: 500)]

        try await sut.test(.router) { client in
            try await client.execute(uri: "/broken", method: .get) { _ in }
        }
        pipeline.finish()
        try await pipeline.run().execute()

        let actual = recorder.served.withLock { $0 }
        #expect(actual == expected)
    }
}
