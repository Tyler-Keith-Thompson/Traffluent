import Events
import Foundation
import StandardContext
import Testing
import Trackers

@Suite("StandardContext: the device", .timeLimit(.minutes(1)))
struct DeviceEnricherTests {
    struct Tapped: Event {
        var number: Int
    }

    @Test("The device enricher sets DeviceKey to the value it was made with, on every record")
    func setsTheGivenValue() async throws {
        let expected = DeviceKey.Value(model: "iPhone17,1", formFactor: .phone)
        let sut = Tracker(enrichers: [.device(expected)])

        sut.track(Tapped(number: 1))
        sut.track(Tapped(number: 2))
        await sut.finish()

        var actual: [DeviceKey.Value?] = []
        for await record in sut.records {
            actual.append(record.context[DeviceKey.self])
        }
        #expect(actual == [expected, expected])
    }

    @Test("Made with no device, the enricher sets nothing")
    func noDeviceNoKey() async throws {
        let sut = Tracker(enrichers: [.device(nil)])

        sut.track(Tapped(number: 1))
        await sut.finish()

        var records = sut.records.makeAsyncIterator()
        let actual = try #require(await records.next()).context[DeviceKey.self]
        #expect(actual == nil)
    }

    @Test(
        "An iOS app's form factor comes from the model: iPad is a pad, RealityDevice a vision, any other a phone",
        arguments: [
            ("iPhone17,1", DeviceKey.Value.FormFactor.phone),
            ("iPod9,1", .phone),
            ("", .phone),
            ("iPad16,3", .pad),
            ("RealityDevice14,1", .vision),
            ("AniPad", .phone),
        ]
    )
    func iOSFormFactor(model: String, expected: DeviceKey.Value.FormFactor) {
        let actual = DeviceKey.Value.FormFactor(iOSModel: model)

        #expect(actual == expected)
    }

    #if os(macOS)
    @Test("On a Mac the device is a Mac, its model the Mac's (hw.model), not its processor")
    func macDevice() throws {
        let processors: Set<String> = ["arm64", "arm64e", "x86_64"]

        let actual = try #require(DeviceKey.Value.current)

        #expect(actual.formFactor == .mac)
        #expect(actual.model.contains("Mac"))
        #expect(!processors.contains(actual.model))
    }
    #endif

    #if os(Linux)
    @Test("On Linux there is no device, and the device enricher sets nothing")
    func linuxHasNoDevice() async throws {
        let sut = Tracker(enrichers: [.device()])

        sut.track(Tapped(number: 1))
        await sut.finish()

        var records = sut.records.makeAsyncIterator()
        let actual = try #require(await records.next()).context[DeviceKey.self]
        #expect(DeviceKey.Value.current == nil)
        #expect(actual == nil)
    }
    #endif
}
