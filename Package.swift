// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "CodexPetEnergy",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "CodexPetEnergy", targets: ["CodexPetEnergy"]),
    ],
    targets: [
        .executableTarget(name: "CodexPetEnergy"),
        .testTarget(name: "CodexPetEnergyTests", dependencies: ["CodexPetEnergy"]),
    ]
)
