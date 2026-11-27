import HTTPDestinations
import HTTPTypes
import PropertyBased
import Testing

@Suite("TransientStatus")
struct TransientStatusTests {
    @Test("A client or server error is a transient status, which keeps it", arguments: [400, 408, 418, 425, 499, 500, 503, 599])
    func failureTaken(code: Int) throws {
        let expected = HTTPResponse.Status(code: code)

        let actual = try TransientStatus(expected)

        #expect(actual.status == expected)
    }

    @Test("The initializer throws InvalidTransientStatus for a status that isn't a client or server error: informational, successful, a redirection or outside 100 through 599", arguments: [0, 99, 100, 199, 200, 204, 299, 300, 399, 600, 999])
    func otherRefused(code: Int) {
        let status = HTTPResponse.Status(code: code)

        #expect(throws: InvalidTransientStatus()) {
            try TransientStatus(status)
        }
    }

    @Test("Two transient statuses of one code are equal, whatever their reason phrases")
    func equalByCode() throws {
        let expected = try TransientStatus(HTTPResponse.Status(code: 418, reasonPhrase: "I'm a teapot"))

        let actual = try TransientStatus(HTTPResponse.Status(code: 418))

        #expect(actual == expected)
    }

    @Test("For any code from 0 to 999, the initializer takes exactly those from 400 to 599, as a naive reference decides")
    func matchesReference() async {
        await propertyCheck(count: 500, input: Gen.int(in: 0 ... 999)) { code in
            let expected = code >= 400 && code < 600

            let actual = (try? TransientStatus(HTTPResponse.Status(code: code))) != nil

            #expect(actual == expected)
        }
    }
}
