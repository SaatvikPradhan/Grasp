// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GraspKit",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "GraspKit", targets: ["GraspKit"]),
    ],
    targets: [
        .target(name: "GraspKit"),
        .testTarget(
            name: "GraspKitTests",
            dependencies: ["GraspKit"],
            resources: [.copy("Fixtures")]
        ),
    ],
    swiftLanguageModes: [.v5]
)
