// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AppAttestClient",
    platforms: [
        .iOS(.v15),
        .macOS(.v12),
        .tvOS(.v15),
        .visionOS(.v1)
    ],
    products: [
        .library(name: "AppAttestClient", targets: ["AppAttestClient"])
    ],
    targets: [
        .target(name: "AppAttestClient"),
        .testTarget(name: "AppAttestClientTests", dependencies: ["AppAttestClient"])
    ]
)
