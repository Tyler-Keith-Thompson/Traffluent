import Destinations
import Events
import ExampleEvents
import Testing
import Trackers

@Suite("Example events", .timeLimit(.minutes(1)))
struct ExampleEventsTests {
    @Test("Each example event is recorded under its type's name")
    func names() {
        let expected = ["AppLaunched", "ButtonTapped", "RequestServed"]

        let actual = [AppLaunched.name, ButtonTapped.name, RequestServed.name]

        #expect(actual == expected)
    }

    @Test("AppLaunched describes the platform it names")
    func appLaunchedDescription() {
        let expected = "AppLaunched(platform: ExampleEvents.Platform.linux)"

        let actual = String(describing: AppLaunched(platform: .linux))

        #expect(actual == expected)
    }

    @Test("ButtonTapped describes the button's label")
    func buttonTappedDescription() {
        let expected = #"ButtonTapped(label: "Subscribe")"#

        let actual = String(describing: ButtonTapped(label: "Subscribe"))

        #expect(actual == expected)
    }

    @Test("RequestServed describes its path and status")
    func requestServedDescription() {
        let expected = #"RequestServed(path: "/items/7", status: 200)"#

        let actual = String(describing: RequestServed(path: "/items/7", status: 200))

        #expect(actual == expected)
    }

    @Test("A delivery hands the example events to its destination in the order tracked")
    func delivered() async throws {
        let recorder = InMemoryDestination()
        let tracker = Tracker()
        let sut = tracker.records.batch().deliver(to: recorder)
        let expected = [
            "AppLaunched AppLaunched(platform: ExampleEvents.Platform.mac)",
            #"ButtonTapped ButtonTapped(label: "Share")"#,
            #"RequestServed RequestServed(path: "/", status: 404)"#,
        ]

        tracker.track(AppLaunched(platform: .mac))
        tracker.track(ButtonTapped(label: "Share"))
        tracker.track(RequestServed(path: "/", status: 404))
        await tracker.finish()
        try await sut.execute()

        let actual = recorder.records.map { "\($0.name) \($0.event)" }
        #expect(actual == expected)
    }

    @Test("The current platform is the one the tests run on")
    @MainActor
    func currentPlatform() {
        #if os(macOS)
            let expected = Platform.mac
        #elseif os(Linux)
            let expected = Platform.linux
        #else
            let expected = Platform.other
        #endif

        let actual = Platform.current

        #expect(actual == expected)
    }
}
