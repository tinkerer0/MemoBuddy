// swift-tools-version: 5.9

import PackageDescription

let package = Package(
  name: "MemoPet",
  platforms: [
    .macOS(.v13)
  ],
  products: [
    .executable(name: "MemoPet", targets: ["MemoPet"]),
    .library(name: "MemoPetCore", targets: ["MemoPetCore"]),
  ],
  targets: [
    .target(name: "MemoPetCore"),
    .executableTarget(
      name: "MemoPet",
      dependencies: ["MemoPetCore"],
      resources: [
        .process("Resources")
      ]
    ),
    .testTarget(
      name: "MemoPetCoreTests",
      dependencies: ["MemoPetCore"]
    ),
  ]
)
