// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OndaSDK",
    platforms: [.iOS(.v15)],
    products: [
        .library(name: "OndaSDK", targets: ["OndaSDK"]),
        // NSE 서브모듈 — 도달(delivered) 트래킹·rich push (PRD-01A 3.1)
        .library(name: "OndaNotificationService", targets: ["OndaNotificationService"]),
    ],
    targets: [
        .target(name: "OndaSDK"),
        .target(name: "OndaNotificationService", dependencies: ["OndaSDK"]),
        .testTarget(name: "OndaSDKTests", dependencies: ["OndaSDK"]),
    ]
)
