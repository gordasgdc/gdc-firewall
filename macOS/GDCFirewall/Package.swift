// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "GDCFirewall",
    defaultLocalization: "ro",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "GDCFirewall",
            path: "Sources/GDCFirewall",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "GDCFirewallTests",
            dependencies: ["GDCFirewall"],
            path: "Tests/GDCFirewallTests"
        )
    ]
)
