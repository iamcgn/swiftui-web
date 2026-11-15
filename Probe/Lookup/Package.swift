// swift-tools-version: 6.0
// Probe (never merged): how unqualified and scoped lookup treat a typealias in a re-exporting
// module beside the struct it names, reached through a second re-exporting module.
import PackageDescription
let t: [(String, [String])] = [
    ("E", []), ("W", ["E"]), ("F1", ["W"]), ("S", ["W"]), ("X", ["W"]), ("F2a", ["X"]), ("F2b", ["X"]), ("S2", ["X"]),
    ("F7", ["X"]), ("F9", ["W"]), ("W5", []), ("X5", ["W5"]), ("F5", ["X5"]), ("F11", ["W5"]),
    ("C1", ["F1", "S"]), ("C2", ["F2a", "S2"]), ("C2s", ["F2a"]), ("C7", ["F7", "S2"]), ("C7s", ["F7"]),
    ("C9", ["F9", "S"]), ("C9s", ["F9"]), ("C5s", ["F5"]), ("C11s", ["F11"]),
    ("E12", []), ("W12", ["E12"]), ("F12", ["W12"]), ("S12", ["W12"]), ("C12", ["F12", "S12"]), ("C12s", ["F12"]), ("C12m", ["F12", "S12"]),
]
let package = Package(
    name: "Lookup",
    products: t.map { .library(name: $0.0, targets: [$0.0]) },
    targets: t.map { .target(name: $0.0, dependencies: $0.1.map { .target(name: $0) }, swiftSettings: $0.0 == "C12m" ? [.enableUpcomingFeature("MemberImportVisibility")] : []) }
)
