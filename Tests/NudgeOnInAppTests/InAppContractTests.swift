import XCTest
@testable import NudgeOnInApp
final class InAppContractTests: XCTestCase {
    func testArtifactIntegrityAndCompatibility() throws {
        let html = "<html>Test</html>"
        func artifact(hash: String, version: Int = 1) throws -> InAppArtifact {
            let object: [String: Any] = ["id":"test", "revision_id":"revision", "expires_at":"2030-01-01T00:00:00Z", "html":html, "artifact_sha256":hash,
                "manifest":["format_version":version,"bridge_version":1,"display":["type":"transparent","backdrop_opacity":0.4],"actions":[:]]]
            return try JSONDecoder().decode(InAppArtifact.self, from: JSONSerialization.data(withJSONObject: object))
        }
        try artifact(hash: InAppArtifact.sha256(html)).validate()
        XCTAssertThrowsError(try artifact(hash: "tampered").validate())
        XCTAssertThrowsError(try artifact(hash: InAppArtifact.sha256(html), version: 2).validate())
    }
    func testNormalTerminationDoesNotBecomeFailureAndLegacyServersStillReceiveSupportedEvents() {
        let normal = InAppTermination.event(reason: "background", failure: false, shown: true, lifecycleEvents: true)
        XCTAssertEqual(normal.kind, "cancelled")
        XCTAssertEqual(normal.detail, "background")
        XCTAssertEqual(InAppTermination.event(reason: "WEBVIEW_ERROR", failure: true, shown: true, lifecycleEvents: true).kind, "failed")
        XCTAssertEqual(InAppTermination.event(reason: "background", failure: false, shown: true, lifecycleEvents: false).kind, "dismiss")
        XCTAssertEqual(InAppTermination.event(reason: "host_blocked", failure: false, shown: false, lifecycleEvents: false).detail, "HOST_BLOCKED")
    }
}
