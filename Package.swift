// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DexcomKit",
    platforms: [
        .iOS(.v18),
        // macOS is included so `swift test` runs natively on development
        // machines and CI runners; CoreBluetooth is available on macOS.
        .macOS(.v15),
    ],
    products: [
        .library(name: "DexcomKit", targets: ["DexcomKit"])
    ],
    targets: [
        .target(name: "DexcomKit"),
        .testTarget(name: "DexcomKitTests", dependencies: ["DexcomKit"]),
    ],
    swiftLanguageModes: [.v6]
)
