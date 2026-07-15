// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SkillsManagerCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SkillsManagerCore", targets: ["SkillsManagerCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.1.0")
    ],
    targets: [
        .target(name: "SkillsManagerCore", dependencies: ["Yams"]),
        .testTarget(
            name: "SkillsManagerCoreTests",
            dependencies: ["SkillsManagerCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
