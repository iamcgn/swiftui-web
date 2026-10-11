// Measures the layout size of every SF Symbol in the system catalog (CoreGlyphs's
// symbol_order.plist, plus the legacy aliases of name_aliases.strings) at the twelve variants of `SystemSymbolMetricsTable` — the macOS text-style
// point sizes at the regular weight, 13 pt semibold and bold, 13 pt at the small and large image
// scales — through SwiftUI in an offscreen `NSHostingView`, the way the `symbol/catalog-*`
// goldens are measured (a text on each row's baseline gives the descent). Writes
// `Fixtures/Goldens/symbol/metrics-full.txt`: one line per symbol, `name` then
// `width height descent` per variant, half points.
//
//     xcrun swiftc -O scripts/symbol-metrics-full.swift -o .build/symbol-metrics-full && .build/symbol-metrics-full
import AppKit
import SwiftUI

struct ProbeKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) { value.merge(nextValue()) { $1 } }
}

@MainActor final class Collector { var frames: [String: CGRect] = [:] }

extension View {
    func probe(_ name: String) -> some View {
        background(GeometryReader { g in Color.clear.preference(key: ProbeKey.self, value: [name: g.frame(in: .named("root"))]) })
    }
}

struct Variant {
    let key: String
    let size: CGFloat
    let weight: Font.Weight?
    let scale: Image.Scale
    var metricsKey: String { "system:\(Int(size)):\(weight == .bold ? 700 : weight == .semibold ? 600 : 400):default||Star" }
}

let variants: [Variant] = [10, 11, 12, 13, 15, 17, 22, 26].map { Variant(key: "\($0)", size: CGFloat($0), weight: nil, scale: .medium) } + [
    Variant(key: "13-semibold", size: 13, weight: .semibold, scale: .medium), Variant(key: "13-bold", size: 13, weight: .bold, scale: .medium),
    Variant(key: "13-small", size: 13, weight: nil, scale: .small), Variant(key: "13-large", size: 13, weight: nil, scale: .large),
]

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let glyphs = "/System/Library/CoreServices/CoreGlyphs.bundle/Contents/Resources/"
// The catalog's names, then the legacy aliases SwiftUI still accepts (`doc` for `document`),
// skipping the hashed internal ones.
let catalog = NSArray(contentsOfFile: glyphs + "symbol_order.plist") as? [String] ?? []
let aliases = (NSDictionary(contentsOfFile: glyphs + "name_aliases.strings") as? [String: String] ?? [:]).keys
    .filter { $0.count < 32 && !$0.hasPrefix("_") && !catalog.contains($0) }.sorted()
let order = catalog + aliases
let metricsFile = root.appendingPathComponent("Fixtures/Goldens/text-metrics.json")
let metrics = ((try? JSONSerialization.jsonObject(with: Data(contentsOf: metricsFile))) as? [String: Any])?["entries"] as? [String: [String: Any]] ?? [:]
func firstBaseline(_ variant: Variant) -> CGFloat {
    CGFloat((metrics[variant.metricsKey]?["firstBaseline"] as? Double) ?? Double(variant.size))
}

/// Lays out `names` in rows of ten at `variant` and returns each symbol's (width, height, descent).
@MainActor func measure(_ names: [String], _ variant: Variant) -> [String: (CGFloat, CGFloat, CGFloat)] {
    let collector = Collector()
    let rows = stride(from: 0, to: names.count, by: 10).map { Array(names[$0..<min($0 + 10, names.count)]) }
    let view = AnyView(VStack(alignment: .leading, spacing: 4) {
        ForEach(Array(rows.enumerated()), id: \.offset) { row in
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Star").probe("row\(row.offset)")
                ForEach(row.element, id: \.self) { name in Image(systemName: name).probe(name) }
            }
        }
    }
    .font(.system(size: variant.size))
    .fontWeight(variant.weight)
    .imageScale(variant.scale)
    .coordinateSpace(name: "root")
    .onPreferenceChange(ProbeKey.self) { collector.frames = $0 }
    .environment(\.locale, Locale(identifier: "en_US"))
    .dynamicTypeSize(.large))
    let hosting = NSHostingView(rootView: view)
    hosting.frame = CGRect(x: 0, y: 0, width: 1400, height: 2400)
    let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = hosting
    hosting.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.02))
    var result: [String: (CGFloat, CGFloat, CGFloat)] = [:]
    let baseline = firstBaseline(variant)
    for (index, row) in rows.enumerated() {
        guard let text = collector.frames["row\(index)"] else { continue }
        let rowBaseline = text.minY + baseline
        for name in row {
            guard let frame = collector.frames[name] else { continue }
            func half(_ v: CGFloat) -> CGFloat { (v * 2).rounded() / 2 }
            result[name] = (half(frame.width), half(frame.height), half(frame.maxY - rowBaseline))
        }
    }
    return result
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
Task { @MainActor in
    var table: [String: [CGFloat]] = [:]
    let batch = 200
    for variant in variants {
        for start in stride(from: 0, to: order.count, by: batch) {
            let names = Array(order[start..<min(start + batch, order.count)])
            let measured = measure(names, variant)
            for name in names {
                guard let m = measured[name] else { continue }
                table[name, default: []] += [m.0, m.1, m.2]
            }
        }
        FileHandle.standardError.write("\(variant.key): \(table.count) symbols\n".data(using: .utf8)!)
    }
    func fmt(_ v: CGFloat) -> String { v == v.rounded() ? String(Int(v)) : String(format: "%g", Double(v)) }
    var lines: [String] = []
    for name in order {
        guard let values = table[name], values.count == variants.count * 3 else { continue }
        lines.append(([name] + values.map(fmt)).joined(separator: " "))
    }
    let out = root.appendingPathComponent("Fixtures/Goldens/symbol/metrics-full.txt")
    try! (lines.joined(separator: "\n") + "\n").write(to: out, atomically: true, encoding: .utf8)
    print("wrote \(lines.count) symbols to \(out.path)")
    exit(0)
}
app.run()
