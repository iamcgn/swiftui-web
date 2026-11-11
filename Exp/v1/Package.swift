// swift-tools-version: 6.1
import PackageDescription
let package = Package(name: "V1", targets: [
  .target(name: "OSModule"),
  .target(name: "os", dependencies: ["OSModule"], swiftSettings: [.unsafeFlags(["-import-underlying-module"])]),
  .executableTarget(name: "App", dependencies: ["os"]),
])
