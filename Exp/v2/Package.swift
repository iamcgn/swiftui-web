// swift-tools-version: 6.1
import PackageDescription
let package = Package(name: "V2", targets: [
  .target(name: "OSModule"),
  .target(name: "os", dependencies: ["OSModule"], swiftSettings: []),
  .executableTarget(name: "App", dependencies: ["os"]),
])
