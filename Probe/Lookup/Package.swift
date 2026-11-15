// swift-tools-version: 6.0
// Probe (never merged): how unqualified and scoped lookup treat a typealias in a re-exporting
// module beside the struct it names, reached through a second re-exporting module.
import PackageDescription
let t: [(String, [String])] = [
    ("E", []), ("W", ["E"]), ("F1", ["W"]), ("S", ["W"]), ("X", ["W"]), ("F2a", ["X"]), ("F2b", ["X"]), ("S2", ["X"]),
    ("C1", ["F1", "S"]), ("C1b", ["F1"]), ("C1s", ["F1"]),
    ("C2", ["F2a", "S2"]), ("C2b", ["F2a"]), ("C2s", ["F2a"]),
    ("C3", ["F2b", "S2"]), ("C3b", ["F2b"]), ("C3s", ["F2b"]),
    ("C4", ["S2", "W"]),
]
let package = Package(
    name: "Lookup",
    products: t.map { .library(name: $0.0, targets: [$0.0]) },
    targets: t.map { .target(name: $0.0, dependencies: $0.1.map { .target(name: $0) }) }
)
