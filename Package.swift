// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NudgeOnSDK",
    // macOS는 단위 테스트 호스트용(async/await·Task 가용). 제품 타깃은 iOS 15+.
    platforms: [.iOS(.v15), .macOS(.v12)],
    products: [
        .library(name: "NudgeOnSDK", targets: ["NudgeOnSDK"]),
        // NSE 서브모듈 — 도달(delivered) 트래킹·rich push (PRD-01A 3.1)
        .library(name: "NudgeOnNotificationService", targets: ["NudgeOnNotificationService"]),
    ],
    targets: [
        .target(name: "NudgeOnSDK"),
        .target(name: "NudgeOnNotificationService", dependencies: ["NudgeOnSDK"]),
        .testTarget(name: "NudgeOnSDKTests", dependencies: ["NudgeOnSDK"]),
        // 계약 테스트 — 공용 시나리오(contract-tests/scenarios) × 목 서버 (DEV-sub-05 S-10).
        .testTarget(name: "NudgeOnContractTests", dependencies: ["NudgeOnSDK"]),
    ]
)
