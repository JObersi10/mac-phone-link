// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PhoneLinkProtos",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .library(name: "PhoneLinkProtos", targets: ["PhoneLinkProtos"]),
        .executable(name: "proto-check", targets: ["ProtoCheck"]),
    ],
    dependencies: [
        // Apple's runtime + plugin. CI invokes the `protoc-gen-swift` plugin via Homebrew;
        // this package dependency provides the SwiftProtobuf runtime the generated code needs.
        .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.28.2"),
    ],
    targets: [
        .target(
            name: "PhoneLinkProtos",
            dependencies: [
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
            ],
            path: "Sources/PhoneLinkProtos"
            // Generated *.pb.swift land in Sources/PhoneLinkProtos/Generated/ (CI step).
        ),
        .executableTarget(
            name: "ProtoCheck",
            dependencies: ["PhoneLinkProtos"],
            path: "Sources/ProtoCheck"
        ),
    ]
)
