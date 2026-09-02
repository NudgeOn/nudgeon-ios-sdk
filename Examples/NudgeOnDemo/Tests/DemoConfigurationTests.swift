import XCTest
@testable import NudgeOnDemo

final class DemoConfigurationTests: XCTestCase {
    func testEnvironmentOverridesInfoDictionary() {
        let configuration = DemoConfiguration.load(
            environment: [
                "NUDGEON_SDK_KEY": "pk_environment",
                "NUDGEON_API_HOST": "https://events.example.com",
                "NUDGEON_APP_GROUP": "group.io.nudgeon.environment",
            ],
            infoDictionary: [
                "NudgeOnSDKKey": "pk_info",
                "NudgeOnAPIHost": "https://info.example.com",
                "NudgeOnAppGroup": "group.io.nudgeon.info",
            ]
        )

        XCTAssertEqual(configuration.sdkKey, "pk_environment")
        XCTAssertEqual(configuration.apiHost, URL(string: "https://events.example.com"))
        XCTAssertEqual(
            configuration.appGroup,
            "group.io.nudgeon.info",
            "App Group must come from the shared build setting/Info.plist, not a process-only environment override"
        )
    }

    func testRejectsSecretKeyAndInvalidHost() {
        let configuration = DemoConfiguration.load(
            environment: [
                "NUDGEON_SDK_KEY": "sk_must_never_ship_in_an_app",
                "NUDGEON_API_HOST": "file:///tmp/not-an-api",
            ],
            infoDictionary: [:]
        )

        XCTAssertEqual(configuration.sdkKey, DemoConfiguration.placeholderSDKKey)
        XCTAssertEqual(configuration.apiHost, DemoConfiguration.localAPIHost)
    }

    func testEmptyAppGroupBecomesNil() {
        let configuration = DemoConfiguration.load(
            environment: [:],
            infoDictionary: ["NudgeOnAppGroup": "   "]
        )

        XCTAssertNil(configuration.appGroup)
    }
}
