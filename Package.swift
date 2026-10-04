// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "mac-phone-link",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "PhoneLink", targets: ["PhoneLink"]),
        .library(name: "ScrcpyProtocol", targets: ["ScrcpyProtocol"]),
        .library(name: "AdbBridge", targets: ["AdbBridge"]),
        .library(name: "VideoPipeline", targets: ["VideoPipeline"]),
        .library(name: "Streaming", targets: ["Streaming"]),
        .library(name: "Companion", targets: ["Companion"])
    ],
    targets: [
        // Pure-Swift wire format. No platform dependencies so it stays testable
        // everywhere (incl. Linux CI) and has no reason to drift from the spec.
        .target(name: "ScrcpyProtocol"),

        // Thin wrapper around the `adb` executable: discovery, server push,
        // reverse tunnel, and launching scrcpy-server with options.
        .target(name: "AdbBridge"),

        // VideoToolbox-backed H.264/H.265 decode. macOS-only by nature.
        .target(name: "VideoPipeline", dependencies: ["ScrcpyProtocol"]),

        // Session orchestration: TCP transport to the forwarded port, framing,
        // wiring decode + control for one display/app.
        .target(
            name: "Streaming",
            dependencies: ["ScrcpyProtocol", "AdbBridge", "VideoPipeline"]
        ),

        // Companion ("non-display") plane: notifications, media control, ring,
        // battery, clipboard, calls/SMS — modeled on the KDE Connect protocol,
        // which the phone speaks via the KDE Connect Android app. Pure
        // Foundation so it stays testable and portable.
        .target(name: "Companion"),

        // AppKit menu-bar app + per-app mirror windows.
        .executableTarget(
            name: "PhoneLink",
            dependencies: ["Streaming", "AdbBridge", "ScrcpyProtocol", "VideoPipeline", "Companion"]
        ),

        .testTarget(name: "ScrcpyProtocolTests", dependencies: ["ScrcpyProtocol"]),
        .testTarget(name: "CompanionTests", dependencies: ["Companion"])
    ]
)
