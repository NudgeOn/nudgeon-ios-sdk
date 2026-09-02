import XCTest
@testable import OndaDemo

final class DemoConfigurationTests: XCTestCase {
    func testEnvironmentOverridesInfoDictionary() {
        let configuration = DemoConfiguration.load(
            environment: [
                "ONDA_SDK_KEY": "pk_environment",
                "ONDA_API_HOST": "https://events.example.com",
                "ONDA_APP_GROUP": "group.io.onda.environment",
            ],
            infoDictionary: [
                "OndaSDKKey": "pk_info",
                "OndaAPIHost": "https://info.example.com",
                "OndaAppGroup": "group.io.onda.info",
            ]
        )

        XCTAssertEqual(configuration.sdkKey, "pk_environment")
        XCTAssertEqual(configuration.apiHost, URL(string: "https://events.example.com"))
        XCTAssertEqual(
            configuration.appGroup,
            "group.io.onda.info",
            "App Group must come from the shared build setting/Info.plist, not a process-only environment override"
        )
    }

    func testRejectsSecretKeyAndInvalidHost() {
        let configuration = DemoConfiguration.load(
            environment: [
                "ONDA_SDK_KEY": "sk_must_never_ship_in_an_app",
                "ONDA_API_HOST": "file:///tmp/not-an-api",
            ],
            infoDictionary: [:]
        )

        XCTAssertEqual(configuration.sdkKey, DemoConfiguration.placeholderSDKKey)
        XCTAssertEqual(configuration.apiHost, DemoConfiguration.localAPIHost)
    }

    func testEmptyAppGroupBecomesNil() {
        let configuration = DemoConfiguration.load(
            environment: [:],
            infoDictionary: ["OndaAppGroup": "   "]
        )

        XCTAssertNil(configuration.appGroup)
    }
}
