import JavaScriptKit
import JavaScriptEventLoop

JavaScriptEventLoop.installGlobalExecutor()

let global = JSObject.global
let document = global.document.object!
let performance = global.performance.object!
let canvas = document.getElementById!("c").object!
let dpr = global.devicePixelRatio.number ?? 1
let width = 1200.0, height = 800.0
canvas.width = .number(width * dpr)
canvas.height = .number(height * dpr)
canvas.style.object!.width = .string("\(Int(width))px")
canvas.style.object!.height = .string("\(Int(height))px")
let ctx = canvas.getContext!("2d").object!

// Display-list opcodes (spike subset of Docs/decisions/0002-display-list.md)
enum Op: Double { case fillRRect = 1, drawText = 2, beginGroup = 3, endGroup = 4 }

let rectCount = 3000
let textCount = 500
let strings: [String] = (0..<textCount).map { "Label \($0) — Hello, World" }
let stringsJS = JSObject.global.Array.function!.new()
for s in strings { _ = stringsJS.push!(s) }

// Deterministic pseudo-random layout so every frame has the same cost.
var seed: UInt64 = 0x9E3779B97F4A7C15
@MainActor func rnd() -> Double { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Double(seed >> 11) / Double(UInt64(1) << 53) }   // NOTE: Int is 32-bit on wasm32; `1 << 53` overflows to 0 there
let rects: [(Double, Double, Double, Double, Double, Double, Double)] = (0..<rectCount).map { _ in
    (rnd() * width, rnd() * height, 20 + rnd() * 80, 12 + rnd() * 40, rnd() * 255, rnd() * 255, rnd() * 255)
}
let texts: [(Double, Double)] = (0..<textCount).map { _ in (rnd() * width, rnd() * height) }

func fmt(_ v: Double) -> String { let r = (v * 100).rounded() / 100; return String(describing: r) }
var frame = 0
var stats: [String: Double] = ["build": 0, "typedArray": 0, "paint": 0, "total": 0]
let sampleFrames = 120
var ops: [Double] = []
ops.reserveCapacity(rectCount * 10 + textCount * 4 + 16)

@MainActor func buildDisplayList(_ t: Double) {
    ops.removeAll(keepingCapacity: true)
    let dx = (t / 16).truncatingRemainder(dividingBy: 100)
    // One translucent group around the first 300 rects to exercise OffscreenCanvas compositing.
    ops.append(Op.beginGroup.rawValue); ops.append(0.6)
    for (i, r) in rects.enumerated() {
        if i == 300 { ops.append(Op.endGroup.rawValue) }
        ops.append(Op.fillRRect.rawValue)
        ops.append(r.0 + dx); ops.append(r.1); ops.append(r.2); ops.append(r.3); ops.append(6)
        ops.append(r.4); ops.append(r.5); ops.append(r.6); ops.append(0.9)
    }
    for (i, p) in texts.enumerated() {
        ops.append(Op.drawText.rawValue); ops.append(Double(i)); ops.append(p.0 + dx); ops.append(p.1)
    }
}

var rafClosure: JSClosure!
@MainActor func tick() {
    let t0 = performance.now!().number!
    buildDisplayList(t0)
    let t1 = performance.now!().number!
    let buffer = JSTypedArray<Double>(ops)
    let t2 = performance.now!().number!
    let paintMs = global.paintDisplayList!(ctx, buffer, stringsJS, dpr, width, height).number!
    let t3 = performance.now!().number!
    if frame >= 10 && frame < 10 + sampleFrames {   // skip warm-up
        stats["build"]! += t1 - t0
        stats["typedArray"]! += t2 - t1
        stats["paint"]! += paintMs
        stats["total"]! += t3 - t0
    }
    frame += 1
    if frame == 10 + sampleFrames {
        let n = Double(sampleFrames)
        let measure = global.measureTextBenchmark!(ctx, stringsJS, 1000).number!
        let report = """
        [spike05] dpr=\(dpr) rects=\(rectCount) texts=\(textCount) ops=\(ops.count) doubles
        [spike05] avg ms/frame: build(wasm)=\(fmt(stats["build"]! / n)) typedArray=\(fmt(stats["typedArray"]! / n)) decode+paint(js)=\(fmt(stats["paint"]! / n)) total=\(fmt(stats["total"]! / n))
        [spike05] measureText x1000: \(fmt(measure)) ms
        """
        _ = global.console.object!.log!(report)
        document.getElementById!("out").object!.textContent = .string(report)
    }
    _ = global.requestAnimationFrame!(rafClosure)
}
rafClosure = JSClosure { _ in MainActor.assumeIsolated { tick() }; return .undefined }

let clickClosure = JSClosure { args in
    MainActor.assumeIsolated {
        let e = args[0].object!
        let x = e.offsetX.number!, y = e.offsetY.number!
        _ = global.console.object!.log!("[spike05] click at \(x), \(y) (points)")
    }
    return .undefined
}
_ = canvas.addEventListener!("click", clickClosure)
_ = global.requestAnimationFrame!(rafClosure)
