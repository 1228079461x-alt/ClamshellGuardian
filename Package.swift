// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "ClamshellGuardian",
    defaultLocalization: "zh-Hans",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "ClamshellGuardianCore", targets: ["ClamshellGuardianCore"]),
        .executable(name: "ClamshellGuardianHelper", targets: ["ClamshellGuardianHelper"]),
        .executable(name: "ClamshellGuardianApp", targets: ["ClamshellGuardianApp"])
    ],
    targets: [
        .target(
            name: "ClamshellGuardianCore"
        ),
        .executableTarget(
            name: "ClamshellGuardianHelper",
            dependencies: ["ClamshellGuardianCore"],
            linkerSettings: [
                .linkedFramework("IOKit")
            ]
        ),
        .executableTarget(
            name: "ClamshellGuardianApp",
            dependencies: ["ClamshellGuardianCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("IOKit"),
                .linkedFramework("Network"),
                .linkedFramework("CoreWLAN")
            ]
        ),
        .executableTarget(
            name: "ClamshellGuardianPolicyTests",
            dependencies: ["ClamshellGuardianCore"],
            path: "Tests/ClamshellGuardianCoreTests"
        )
    ],
    swiftLanguageVersions: [.v5]
)
