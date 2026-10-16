// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "DicyaninPerfProbe",
    platforms: [.visionOS(.v2), .macOS(.v14), .iOS(.v17)],
    products: [.library(name: "DicyaninPerfProbe", targets: ["DicyaninPerfProbe"])],
    targets: [
        .target(name: "DicyaninPerfProbe"),
        .testTarget(name: "DicyaninPerfProbeTests", dependencies: ["DicyaninPerfProbe"]),
    ],
    swiftLanguageModes: [.v5]
)
