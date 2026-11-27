import Foundation
import HTTPDestinations
import PostHogEncoding
import Testing
import TrackingPlans

@Suite("HTTPDestination.postHog: setup errors")
struct PostHogSetupErrorTests {
    @Test("The factory throws emptyProjectToken for a token that is empty or only whitespace", arguments: ["", " ", " \n\t"])
    func emptyProjectToken(token: String) throws {
        let host = try #require(URL(string: "https://us.i.posthog.com"))
        let plan = try TrackingPlan(schemas: [])

        #expect(throws: PostHogSetupError.emptyProjectToken) {
            try HTTPDestination.postHog(projectToken: token, host: host, plan: plan)
        }
    }

    @Test("The factory accepts a one-character token, the shortest that isn't empty")
    func shortestToken() throws {
        let host = try #require(URL(string: "https://us.i.posthog.com"))
        let plan = try TrackingPlan(schemas: [])

        #expect(throws: Never.self) {
            try HTTPDestination.postHog(projectToken: "p", host: host, plan: plan)
        }
    }

    @Test("The factory throws personalAPIKey for a personal API key, whitespace around it trimmed, and accepts project tokens and tokens that only resemble one", arguments: [
        ("phx_", true), ("phx_abc", true), (" phx_abc", true), ("\nphx_abc\t", true), ("phc_abc", false), ("phx", false), ("PHX_abc", false), ("x phx_abc", false),
    ])
    func personalAPIKey(token: String, throwsError: Bool) throws {
        let host = try #require(URL(string: "https://us.i.posthog.com"))
        let plan = try TrackingPlan(schemas: [])
        let expected: PostHogSetupError? = throwsError ? .personalAPIKey : nil

        let actual: PostHogSetupError?
        do {
            _ = try HTTPDestination.postHog(projectToken: token, host: host, plan: plan)
            actual = nil
        } catch {
            actual = error
        }

        #expect(actual == expected)
    }

    @Test("The factory throws invalidHost for a host that isn't https, has no host name, a user name or password, a query or fragment, or a path ending in batch", arguments: [
        "http://us.i.posthog.com", "ftp://us.i.posthog.com", "https:///batch", "https:///posthog", "https://us.i.posthog.com?x=1", "https://us.i.posthog.com?", "https://us.i.posthog.com#x",
        "us.i.posthog.com", "https://user@us.i.posthog.com", "https://user:secret@us.i.posthog.com", "https://:secret@us.i.posthog.com",
        "https://us.i.posthog.com/batch", "https://us.i.posthog.com/batch/", "https://example.com/posthog/batch//",
    ])
    func invalidHost(host: String) throws {
        let url = try #require(URL(string: host))
        let plan = try TrackingPlan(schemas: [])

        #expect(throws: PostHogSetupError.invalidHost) {
            try HTTPDestination.postHog(projectToken: "phc_test", host: url, plan: plan)
        }
    }

    @Test("The factory accepts an https host in any case, with or without a path or port, an IPv6 address, and a path that only resembles the endpoint's", arguments: [
        "https://us.i.posthog.com", "HTTPS://eu.i.posthog.com", "https://example.com:8443/posthog/", "https://h", "https://[::1]", "https://[2001:db8::1]:8443/posthog",
        "https://example.com/batches", "https://example.com/batch/posthog", "https://example.com/Batch",
    ])
    func validHost(host: String) throws {
        let url = try #require(URL(string: host))
        let plan = try TrackingPlan(schemas: [])

        #expect(throws: Never.self) {
            try HTTPDestination.postHog(projectToken: "phc_test", host: url, plan: plan)
        }
    }

    @Test("A token is checked before the host, so an empty token on an http host throws emptyProjectToken")
    func tokenCheckedFirst() throws {
        let url = try #require(URL(string: "http://us.i.posthog.com"))
        let plan = try TrackingPlan(schemas: [])

        #expect(throws: PostHogSetupError.emptyProjectToken) {
            try HTTPDestination.postHog(projectToken: "", host: url, plan: plan)
        }
    }
}
