// swift-tools-version: 5.9
import PackageDescription

// Depends on the macOS app's MemoPetCore package by relative path so this
// tool always reads/writes with the exact same code the shipped macOS app
// uses (no reimplementation drift). Never points at a fixture other than
// what the caller passes on the command line; never touches
// `~/Library/Application Support/MemoPet` on its own.
let package = Package(
  name: "swift-reader",
  platforms: [
    .macOS(.v13)
  ],
  dependencies: [
    .package(path: "../../../memo_pet")
  ],
  targets: [
    .executableTarget(
      name: "swift-reader",
      dependencies: [
        .product(name: "MemoPetCore", package: "memo_pet")
      ]
    )
  ]
)
