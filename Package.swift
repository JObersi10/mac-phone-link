// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PhoneLinkProtos",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "PhoneLinkProtos", targets: ["PhoneLinkProtos"]),
        .library(name: "DCGAuth", targets: ["DCGAuth"]),
        .library(name: "DCGTransport", targets: ["DCGTransport"]),
        .library(name: "PhoneLinkUI", targets: ["PhoneLinkUI"]),
        .library(name: "PhoneLinkVideo", targets: ["PhoneLinkVideo"]),
        .library(name: "PhoneLinkPairing", targets: ["PhoneLinkPairing"]),
        .library(name: "NanoTransport", targets: ["NanoTransport"]),
        .library(name: "LANTransport", targets: ["LANTransport"]),
        .executable(name: "proto-check", targets: ["ProtoCheck"]),
        .executable(name: "PhoneLinkApp", targets: ["PhoneLinkApp"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.28.2"),
        .package(url: "https://github.com/AzureAD/microsoft-authentication-library-for-objc.git", from: "1.5.0"),
        .package(url: "https://github.com/moozzyk/SignalR-Client-Swift.git", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "PhoneLinkProtos",
            dependencies: [.product(name: "SwiftProtobuf", package: "swift-protobuf")],
            path: "Sources/PhoneLinkProtos"
        ),
        .target(
            name: "DCGAuth",
            dependencies: [.product(name: "MSAL", package: "microsoft-authentication-library-for-objc")],
            path: "Sources/DCGAuth"
        ),
        .target(
            name: "DCGTransport",
            dependencies: [
                "PhoneLinkProtos",
                "DCGAuth",
                .product(name: "SignalRClient", package: "SignalR-Client-Swift"),
            ],
            path: "Sources/DCGTransport"
        ),
        .target(
            name: "PhoneLinkUI",
            dependencies: ["PhoneLinkProtos", "DCGTransport", "PhoneLinkVideo", "NanoTransport", "PhoneLinkPairing"],
            path: "Sources/PhoneLinkUI"
        ),
        .target(
            name: "PhoneLinkVideo",
            dependencies: [],
            path: "Sources/PhoneLinkVideo"
        ),
        .executableTarget(
            name: "PhoneLinkApp",
            dependencies: [
                "PhoneLinkUI",
                "DCGAuth",
                "PhoneLinkPairing",
                .product(name: "MSAL", package: "microsoft-authentication-library-for-objc"),
            ],
            path: "Sources/PhoneLinkApp"
        ),
        .target(
            name: "PhoneLinkPairing",
            dependencies: [],
            path: "Sources/PhoneLinkPairing"
        ),
        .target(
            name: "NanoTransport",
            dependencies: ["PhoneLinkProtos"],
            path: "Sources/NanoTransport"
        ),
        .target(
            name: "LANTransport",
            dependencies: [],
            path: "Sources/LANTransport"
        ),
        .executableTarget(
            name: "ProtoCheck",
            dependencies: ["PhoneLinkProtos"],
            path: "Sources/ProtoCheck"
        ),
        .testTarget(
            name: "PhoneLinkProtosTests",
            dependencies: ["PhoneLinkProtos", "DCGTransport", "PhoneLinkUI", "PhoneLinkVideo", "PhoneLinkPairing", "NanoTransport", "LANTransport"],
            path: "Tests/PhoneLinkProtosTests"
        ),
    ]
)
