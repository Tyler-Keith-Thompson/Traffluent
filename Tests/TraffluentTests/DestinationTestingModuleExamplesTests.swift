// The example of the DestinationTesting module's landing article
// (Sources/DestinationTesting/DestinationTesting.docc/DestinationTesting.md), verbatim, so the
// article cannot drift from the code.

import DestinationTesting
import Foundation
import HTTPDestinations
import PostHogEncoding
import Testing

@Suite("DestinationTesting module examples", .timeLimit(.minutes(1)))
struct DestinationTestingModuleExamplesTests {
    @Test(arguments: ConformanceCheck.allCases)
    func postHogConformance(check: ConformanceCheck) async throws {
        let host = try #require(URL(string: "https://posthog.example.com"))
        let conformance = DestinationConformance(limit: PostHogBatchEncoder.batchLimit) { setup in
            try HTTPDestination.postHog(projectToken: "phc_test", host: host, plan: setup.plan, transport: setup.transport, backoff: setup.backoff)
        }
        try await conformance.expect(check)
    }
}
