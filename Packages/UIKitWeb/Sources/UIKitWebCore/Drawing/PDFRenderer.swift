// PDF contexts (Docs/elements/UIKit/Drawing.md, "PDF renderers and PDFKit"): `UIGraphicsPDFRenderer` runs
// drawing code a page at a time, each `beginPage()` starting a page with a recording context as
// the current one, and hands back the pages as a PDF file. Basic-Car-Maintenance's report draws
// its rows through it and opens the file in PDFKit for a thumbnail to share.
//
// The file is a real PDF any viewer opens: each page's recording is written as PDF operators
// (paths, fills, strokes, clips, transforms and opacity, text in the standard Helvetica, Times
// and Courier faces, gradients as their middle colour). Images, shadows, filters and blurs have
// no operators here and are left out of the file. The process keeps each page's recording too,
// under a marker in the file's information, so a `PDFDocument` opened on that data draws the
// pages exactly as they were recorded.
#if os(WASI)
import WebFoundation
#else
import Foundation
#endif

/// The document information a PDF renderer writes (`kCGPDFContextTitle` and the rest: "Title",
/// "Author", "Subject", "Keywords", "Creator").
public final class UIGraphicsPDFRendererFormat: @unchecked Sendable {
    public var documentInfo: [String: Any] = [:]
    public init() {}
    public static func `default`() -> UIGraphicsPDFRendererFormat { UIGraphicsPDFRendererFormat() }
}

/// What a PDF renderer's drawing block receives: the current page's context and the page calls.
@preconcurrency @MainActor
public final class UIGraphicsPDFRendererContext {
    let format: UIGraphicsPDFRendererFormat
    let defaultBounds: CGRect
    private(set) var pages: [_PDFPage] = []
    private var recorder: UIGraphicsRecordingContext?
    /// Whether the recorder draws a page (not drawing made before the first page).
    private var recordsPage = false
    private var pageBounds: CGRect

    init(format: UIGraphicsPDFRendererFormat, bounds: CGRect) {
        self.format = format
        defaultBounds = bounds
        pageBounds = bounds
    }

    /// The current page's context. Drawing made before the first `beginPage()` goes nowhere.
    public var cgContext: UIGraphicsRecordingContext {
        if let recorder { return recorder }
        let idle = UIGraphicsRecordingContext(origin: .zero, scale: 1, canvasSize: pageBounds.size)
        recorder = idle
        UIGraphicsPushContext(idle)
        return idle
    }

    /// The current page's bounds.
    public var pdfContextBounds: CGRect { pageBounds }

    /// Ends the page in progress and starts one the renderer's size.
    public func beginPage() { beginPage(withBounds: defaultBounds, pageInfo: [:]) }

    /// Ends the page in progress and starts one of `bounds`, its origin at the page's top left.
    public func beginPage(withBounds bounds: CGRect, pageInfo: [String: Any]) {
        endPage()
        pageBounds = bounds
        let page = UIGraphicsRecordingContext(origin: CGPoint(x: -bounds.minX, y: -bounds.minY), scale: 1, canvasSize: bounds.size)
        recorder = page
        recordsPage = true
        UIGraphicsPushContext(page)
    }

    /// Links an area of the page to a web address (kept by the recording only).
    public func setURL(_ url: URL, for rect: CGRect) {}
    public func addDestination(withName name: String, at point: CGPoint) {}
    public func setDestinationWithName(_ name: String, for rect: CGRect) {}

    public func fill(_ rect: CGRect) { cgContext.fill(rect) }
    public func fill(_ rect: CGRect, blendMode: CGBlendMode) { cgContext.withBlendMode(blendMode) { cgContext.fill(rect) } }
    public func stroke(_ rect: CGRect) { cgContext.stroke(rect) }
    public func stroke(_ rect: CGRect, blendMode: CGBlendMode) { cgContext.withBlendMode(blendMode) { cgContext.stroke(rect) } }
    public func clip(to rect: CGRect) { cgContext.clip(to: rect) }

    /// Closes the page in progress, keeping its recording if it is a page.
    func endPage() {
        guard let recorder else { return }
        if UIGraphicsGetCurrentContext() === recorder { UIGraphicsPopContext() }
        recorder.finish()
        if recordsPage { pages.append(_PDFPage(size: pageBounds.size, commands: recorder.commands)) }
        self.recorder = nil
        recordsPage = false
    }
}

/// Runs drawing code a page at a time and returns the pages as a PDF.
@preconcurrency @MainActor
public final class UIGraphicsPDFRenderer {
    public let format: UIGraphicsPDFRendererFormat
    public let bounds: CGRect
    public let allowsImageOutput = false

    public init(bounds: CGRect, format: UIGraphicsPDFRendererFormat) {
        self.bounds = bounds
        self.format = format
    }
    public convenience init(bounds: CGRect) { self.init(bounds: bounds, format: .default()) }

    /// The PDF of the pages `actions` draws.
    public func pdfData(actions: (UIGraphicsPDFRendererContext) -> Void) -> Data {
        Data(render(actions))
    }

    /// Writes the PDF of the pages `actions` draws to `url`.
    public func writePDF(to url: URL, withActions actions: (UIGraphicsPDFRendererContext) -> Void) throws {
        try Data(render(actions)).write(to: url)
    }

    private func render(_ actions: (UIGraphicsPDFRendererContext) -> Void) -> [UInt8] {
        let context = UIGraphicsPDFRendererContext(format: format, bounds: bounds)
        actions(context)
        context.endPage()
        var info: [String: String] = [:]
        for (key, value) in format.documentInfo {
            if let text = value as? String { info[key] = text }
            else if let list = value as? [String] { info[key] = list.joined(separator: ", ") }
        }
        return _PDFDrawings.write(pages: context.pages, info: info)
    }
}

/// One page of a PDF this process wrote: its size and what was drawn on it, top left first.
public struct _PDFPage: Sendable {
    public var size: CGSize
    public var commands: [DisplayCommand]
    public init(size: CGSize, commands: [DisplayCommand]) {
        self.size = size
        self.commands = commands
    }
}

/// The pages of the PDFs this process wrote, by the marker each file carries in its
/// information, so PDFKit draws a file of ours as it was recorded.
public enum _PDFDrawings {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var written: [String: [_PDFPage]] = [:]
    nonisolated(unsafe) private static var order: [String] = []
    nonisolated(unsafe) private static var next = 0
    /// The information key that carries the marker.
    public static let markerKey = "SwiftUIWebDrawing"

    /// The pages written under `marker`, or nil for a file this process did not write.
    public static func pages(forMarker marker: String) -> [_PDFPage]? {
        lock.lock(); defer { lock.unlock() }
        return written[marker]
    }

    /// Writes `pages` as a PDF, keeping their recordings under a new marker (the 32 newest).
    public static func write(pages: [_PDFPage], info: [String: String]) -> [UInt8] {
        lock.lock()
        next += 1
        let marker = "swiftui-web-\(next)"
        written[marker] = pages
        order.append(marker)
        if order.count > 32 { written[order.removeFirst()] = nil }
        lock.unlock()
        var info = info
        info[markerKey] = marker
        return PDFWriter(pages: pages, info: info).bytes()
    }
}

// MARK: - Writing

/// Writes pages of display commands as a PDF 1.4 file.
struct PDFWriter {
    let pages: [_PDFPage]
    let info: [String: String]

    private var fonts: [String] = []
    private var alphas: [Int] = []

    init(pages: [_PDFPage], info: [String: String]) {
        self.pages = pages
        self.info = info
    }

    func bytes() -> [UInt8] {
        var writer = self
        let streams = pages.map { writer.content(for: $0) }
        return writer.assemble(streams)
    }

    private func assemble(_ streams: [String]) -> [UInt8] {
        // 1 catalog, 2 page tree, 3 resources, then the fonts, each page and its contents, the information.
        let firstFont = 4
        let firstPage = firstFont + fonts.count
        let infoObject = firstPage + 2 * pages.count
        var objects: [String] = []
        objects.append("<< /Type /Catalog /Pages 2 0 R >>")
        let kids = (0..<pages.count).map { "\(firstPage + 2 * $0) 0 R" }.joined(separator: " ")
        objects.append("<< /Type /Pages /Kids [\(kids)] /Count \(pages.count) >>")
        var resources = "<< /ProcSet [/PDF /Text]"
        if !fonts.isEmpty {
            resources += " /Font <<" + fonts.indices.map { " /F\($0) \(firstFont + $0) 0 R" }.joined() + " >>"
        }
        if !alphas.isEmpty {
            resources += " /ExtGState <<" + alphas.map { " /A\($0) << /ca \(pdfNumber(CGFloat($0) / 1000)) /CA \(pdfNumber(CGFloat($0) / 1000)) >>" }.joined() + " >>"
        }
        objects.append(resources + " >>")
        for font in fonts {
            objects.append("<< /Type /Font /Subtype /Type1 /BaseFont /\(font) /Encoding /WinAnsiEncoding >>")
        }
        for (index, page) in pages.enumerated() {
            objects.append("<< /Type /Page /Parent 2 0 R /MediaBox [0 0 \(pdfNumber(page.size.width)) \(pdfNumber(page.size.height))] /Resources 3 0 R /Contents \(firstPage + 2 * index + 1) 0 R >>")
            objects.append("<< /Length \(streams[index].utf8.count) >>\nstream\n\(streams[index])\nendstream")
        }
        var entries = "<< /Producer (SwiftUI Web)"
        for key in info.keys.sorted() { entries += " /\(key) (\(pdfString(info[key] ?? "")))" }
        objects.append(entries + " >>")

        var out: [UInt8] = Array("%PDF-1.4\n%\u{E2}\u{E3}\u{CF}\u{D3}\n".utf8)
        var offsets: [Int] = []
        for (index, object) in objects.enumerated() {
            offsets.append(out.count)
            out += Array("\(index + 1) 0 obj\n\(object)\nendobj\n".utf8)
        }
        let xref = out.count
        var table = "xref\n0 \(objects.count + 1)\n0000000000 65535 f \n"
        for offset in offsets {
            var digits = String(offset)
            while digits.count < 10 { digits = "0" + digits }
            table += "\(digits) 00000 n \n"
        }
        table += "trailer\n<< /Size \(objects.count + 1) /Root 1 0 R /Info \(infoObject) 0 R >>\nstartxref\n\(xref)\n%%EOF\n"
        return out + Array(table.utf8)
    }

    // MARK: A page's operators

    /// What a group start leaves open until its `endGroup`.
    private enum Group { case opacity(Double), maskDrawing, maskContent }

    private mutating func content(for page: _PDFPage) -> String {
        // The recording is top left first, as UIKit draws: flip the page to match.
        var out = "1 0 0 -1 0 \(pdfNumber(page.size.height)) cm\n"
        var groups: [Group] = []
        var opacity: Double { groups.reduce(1) { if case .opacity(let value) = $1 { return $0 * value }; return $0 } }
        var skipping: Bool { groups.contains { if case .maskDrawing = $0 { return true }; return false } }
        for command in page.commands {
            switch command {
            case .beginGroup(let value): groups.append(.opacity(value)); continue
            case .beginShadow, .beginFilter, .beginBlend: groups.append(.opacity(1)); continue
            case .beginMask: groups.append(.maskDrawing); continue
            case .beginMasked:
                if let index = groups.lastIndex(where: { if case .maskDrawing = $0 { return true }; return false }) { groups[index] = .maskContent }
                continue
            case .endGroup: _ = groups.popLast(); continue
            default: break
            }
            if skipping { continue }
            switch command {
            case .save: out += "q\n"
            case .restore: out += "Q\n"
            case .concat(let t):
                out += "\(pdfNumber(t.a)) \(pdfNumber(t.b)) \(pdfNumber(t.c)) \(pdfNumber(t.d)) \(pdfNumber(t.tx)) \(pdfNumber(t.ty)) cm\n"
            case .clipRect(let rect): out += rectOps(rect) + "W n\n"
            case .clipRRect(let rect, let radius): out += pathOps(Path(roundedRect: rect, cornerRadius: radius)) + "W n\n"
            case .clipPath(let path, let eoFill): out += pathOps(path) + (eoFill ? "W* n\n" : "W n\n")
            case .fillRect(let rect, let color): out += paint(color, opacity, fill: true) { $0.rectOps(rect) + "f\n" }
            case .fillRRect(let rect, let radius, let color):
                out += paint(color, opacity, fill: true) { $0.pathOps(Path(roundedRect: rect, cornerRadius: radius)) + "f\n" }
            case .fillPath(let path, let color, let eoFill):
                out += paint(color, opacity, fill: true) { $0.pathOps(path) + (eoFill ? "f*\n" : "f\n") }
            case .fillGradient(let path, let gradient, let eoFill):
                out += paint(middle(of: gradient), opacity, fill: true) { $0.pathOps(path) + (eoFill ? "f*\n" : "f\n") }
            case .strokePath(let path, let style, let color):
                out += paint(color, opacity, fill: false) { $0.strokeOps(style) + $0.pathOps(path) + "S\n" }
            case .strokeGradient(let path, let style, let gradient):
                out += paint(middle(of: gradient), opacity, fill: false) { $0.strokeOps(style) + $0.pathOps(path) + "S\n" }
            case .drawText(let text, let font, let origin, let color):
                out += paint(color, opacity, fill: true) { $0.textOps(text, font, origin) }
            case .drawTextGradient(let text, let font, let origin, let gradient):
                out += paint(middle(of: gradient), opacity, fill: true) { $0.textOps(text, font, origin) }
            default: break   // images, bitmaps and backdrop blurs have no operators here
            }
        }
        return out
    }

    /// A painting operation in `color`, its alpha through an ExtGState when not opaque.
    private mutating func paint(_ color: RGBA, _ opacity: Double, fill: Bool, _ ops: (inout PDFWriter) -> String) -> String {
        let alpha = Int((color.alpha * opacity * 1000).rounded())
        guard alpha > 0 else { return "" }
        let colour = "\(pdfNumber(CGFloat(color.red))) \(pdfNumber(CGFloat(color.green))) \(pdfNumber(CGFloat(color.blue))) \(fill ? "rg" : "RG")\n"
        let body = ops(&self)
        guard alpha < 1000 else { return "q\n" + colour + body + "Q\n" }
        if !alphas.contains(alpha) { alphas.append(alpha) }
        return "q\n/A\(alpha) gs\n" + colour + body + "Q\n"
    }

    private func rectOps(_ rect: CGRect) -> String {
        "\(pdfNumber(rect.minX)) \(pdfNumber(rect.minY)) \(pdfNumber(rect.width)) \(pdfNumber(rect.height)) re\n"
    }

    private func pathOps(_ path: Path) -> String {
        var out = ""
        var current = CGPoint.zero
        var start = CGPoint.zero
        func point(_ p: CGPoint) -> String { "\(pdfNumber(p.x)) \(pdfNumber(p.y))" }
        path.forEach { element in
            switch element {
            case .move(let p): out += "\(point(p)) m\n"; current = p; start = p
            case .line(let p): out += "\(point(p)) l\n"; current = p
            case .quadCurve(let p, let c):
                let c1 = CGPoint(x: current.x + (c.x - current.x) * 2 / 3, y: current.y + (c.y - current.y) * 2 / 3)
                let c2 = CGPoint(x: p.x + (c.x - p.x) * 2 / 3, y: p.y + (c.y - p.y) * 2 / 3)
                out += "\(point(c1)) \(point(c2)) \(point(p)) c\n"; current = p
            case .curve(let p, let c1, let c2): out += "\(point(c1)) \(point(c2)) \(point(p)) c\n"; current = p
            case .closeSubpath: out += "h\n"; current = start
            }
        }
        return out
    }

    private func strokeOps(_ style: StrokeStyle) -> String {
        var out = "\(pdfNumber(style.lineWidth)) w \(style.lineCap.rawValue) J \(style.lineJoin.rawValue) j \(pdfNumber(style.miterLimit)) M\n"
        out += "[" + style.dash.map { pdfNumber($0) }.joined(separator: " ") + "] \(pdfNumber(style.dashPhase)) d\n"
        return out
    }

    private mutating func textOps(_ text: String, _ font: DisplayFont, _ origin: CGPoint) -> String {
        let name = Self.standardFace(font)
        let index: Int
        if let found = fonts.firstIndex(of: name) { index = found } else { index = fonts.count; fonts.append(name) }
        // The text matrix flips back so the glyphs stand upright on the flipped page.
        return "BT\n/F\(index) \(pdfNumber(font.size)) Tf \(pdfNumber(font.letterSpacing)) Tc\n1 0 0 -1 \(pdfNumber(origin.x)) \(pdfNumber(origin.y)) Tm\n(\(pdfString(text))) Tj\nET\n"
    }

    /// The standard face nearest `font`: Courier for monospaced families, Times for serif ones,
    /// Helvetica otherwise, bold from semibold up.
    static func standardFace(_ font: DisplayFont) -> String {
        let family = Array(font.family.lowercased().utf8)
        let bold = font.weight >= 600
        if hasRun(family, "mono") || hasRun(family, "courier") || hasRun(family, "menlo") {
            return bold ? (font.italic ? "Courier-BoldOblique" : "Courier-Bold") : (font.italic ? "Courier-Oblique" : "Courier")
        }
        if (hasRun(family, "serif") && !hasRun(family, "sans")) || hasRun(family, "times") || hasRun(family, "georgia") || hasRun(family, "new york") {
            return bold ? (font.italic ? "Times-BoldItalic" : "Times-Bold") : (font.italic ? "Times-Italic" : "Times-Roman")
        }
        return bold ? (font.italic ? "Helvetica-BoldOblique" : "Helvetica-Bold") : (font.italic ? "Helvetica-Oblique" : "Helvetica")
    }

    /// Whether `needle` runs inside `haystack`, byte for byte.
    static func hasRun(_ haystack: [UInt8], _ needle: StaticString) -> Bool {
        let bytes = needle.withUTF8Buffer { Array($0) }
        guard !bytes.isEmpty, haystack.count >= bytes.count else { return false }
        for start in 0...(haystack.count - bytes.count) where haystack[start] == bytes[0] {
            var match = true
            for offset in 1..<bytes.count where haystack[start + offset] != bytes[offset] { match = false; break }
            if match { return true }
        }
        return false
    }

    /// The gradient's colour halfway along it.
    private func middle(of gradient: DisplayGradient) -> RGBA {
        let stops = gradient.stops.sorted { $0.location < $1.location }
        guard let first = stops.first else { return RGBA(red: 0, green: 0, blue: 0, alpha: 0) }
        guard let after = stops.firstIndex(where: { $0.location >= 0.5 }) else { return stops[stops.count - 1].color }
        guard after > 0 else { return first.color }
        let a = stops[after - 1], b = stops[after]
        let t = b.location > a.location ? (0.5 - a.location) / (b.location - a.location) : 0
        func mix(_ x: Double, _ y: Double) -> Double { x + (y - x) * t }
        return RGBA(red: mix(a.color.red, b.color.red), green: mix(a.color.green, b.color.green),
                    blue: mix(a.color.blue, b.color.blue), alpha: mix(a.color.alpha, b.color.alpha))
    }
}

/// A number as PDF writes it: at most three decimals, no exponent.
func pdfNumber(_ value: CGFloat) -> String {
    guard value.isFinite else { return "0" }
    let scaled = Int((Double(value) * 1000).rounded())
    if scaled % 1000 == 0 { return String(scaled / 1000) }
    let magnitude = abs(scaled)
    var fraction = String(magnitude % 1000)
    while fraction.count < 3 { fraction = "0" + fraction }
    while fraction.last == "0" { fraction.removeLast() }
    return "\(scaled < 0 ? "-" : "")\(magnitude / 1000).\(fraction)"
}

/// A PDF literal string's contents in WinAnsi: brackets and backslashes escaped, other
/// characters past ASCII as octal codes, and characters WinAnsi lacks as question marks.
func pdfString(_ text: String) -> String {
    var out = ""
    for scalar in text.unicodeScalars {
        let code: UInt32
        switch scalar.value {
        case 0x28, 0x29, 0x5C: out += "\\" + String(Character(scalar)); continue
        case 0x0A, 0x0D, 0x09: out += " "; continue
        case 0x20..<0x7F: out += String(Character(scalar)); continue
        case 0xA0...0xFF: code = scalar.value
        case 0x20AC: code = 0x80
        case 0x2026: code = 0x85
        case 0x2018: code = 0x91
        case 0x2019: code = 0x92
        case 0x201C: code = 0x93
        case 0x201D: code = 0x94
        case 0x2022: code = 0x95
        case 0x2013: code = 0x96
        case 0x2014: code = 0x97
        default: out += "?"; continue
        }
        out += "\\" + String(code / 64) + String((code / 8) % 8) + String(code % 8)
    }
    return out
}
