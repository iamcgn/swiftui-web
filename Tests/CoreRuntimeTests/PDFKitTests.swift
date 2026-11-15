// PDF renderers and PDFKit (UIKitWebCore's Drawing/PDFRenderer.swift, Sources/PDFKit): pages
// drawn as Basic-Car-Maintenance draws its report come out as a PDF file any viewer opens, and
// PDFKit opens that file again with its pages, text and a thumbnail drawn as recorded, and
// reads another PDF's pages and sizes from its bytes.
#if os(WASI)
import WebFoundation   // the SDK's Foundation would make a second CGFloat and Data
#else
import Foundation
#endif
import Testing
import SwiftUI
import SwiftUIWebCore
import UIKit
import PDFKit

/// One line per drawn string, so string drawing records its text without a host's engine.
private final class LineTextEngine: TextEngine {
    func layout(_ runs: [StyledRun], options: TextLayoutOptions, width: CGFloat?) -> TextLayout {
        let string = runs.map(\.string).joined()
        let size = runs.first?.font.size ?? 13
        let w = CGFloat(string.count) * size * 0.5
        let line = TextLayout.Line(range: string.startIndex..<string.endIndex, width: w, baseline: size, fragments: [TextLayout.Fragment(text: string, run: 0, x: 0, width: w)])
        return TextLayout(size: CGSize(width: w, height: size * 1.2), firstBaseline: size, lastBaseline: size, lines: [line])
    }
    func metrics(for font: ResolvedFont) -> FontMetrics {
        FontMetrics(lineHeight: font.size * 1.2, spacingBelow: 0, spacingAbove: 0, textToText: 0)
    }
}

@Suite @MainActor struct PDFKitTests {
    private let a4 = CGRect(x: 0, y: 0, width: 595.2, height: 841.8)

    private func text(_ data: Data) -> String { String(decoding: data, as: UTF8.self) }

    /// Two pages as the report draws them: a title, a red rule, a half-transparent box.
    private func report() -> UIGraphicsPDFRenderer {
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = ["Title": "Maintenance (2025)", "Author": "Car Owner"]
        return UIGraphicsPDFRenderer(bounds: a4, format: format)
    }

    private func draw(_ context: UIGraphicsPDFRendererContext) {
        let engine = UIKitScene.shared.textEngine
        UIKitScene.shared.textEngine = LineTextEngine()
        defer { UIKitScene.shared.textEngine = engine }
        // Drawing before the first page goes nowhere, as in UIKit.
        "lost".draw(at: CGPoint(x: 10, y: 10), withAttributes: [.font: UIFont.systemFont(ofSize: 12)])
        context.beginPage()
        "Oil change".draw(at: CGPoint(x: 20, y: 50), withAttributes: [.font: UIFont.systemFont(ofSize: 14), .foregroundColor: UIColor.black])
        context.cgContext.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        context.fill(CGRect(x: 20, y: 80, width: 100, height: 2))
        context.beginPage()
        "Café".draw(at: CGPoint(x: 20, y: 50), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 18)])
        context.cgContext.setFillColor(red: 0, green: 0, blue: 1, alpha: 0.5)
        context.fill(CGRect(x: 20, y: 100, width: 50, height: 50))
    }

    @Test func pagesComeOutAsAPDFFile() throws {
        let data = report().pdfData { draw($0) }
        let pdf = text(data)
        #expect(pdf.hasPrefix("%PDF-1.4\n") && pdf.hasSuffix("%%EOF\n"))
        #expect(pdf.contains("/Type /Pages /Kids [") && pdf.contains("/Count 2 >>"))
        #expect(pdf.contains("/MediaBox [0 0 595.2 841.8]"))
        // The page is flipped to UIKit's top-left origin, and the glyphs back upright.
        #expect(pdf.contains("1 0 0 -1 0 841.8 cm\n"))
        #expect(pdf.contains("(Oil change) Tj") && !pdf.contains("(lost) Tj"))
        #expect(pdf.contains("(Caf\\351) Tj"))
        #expect(pdf.contains("/BaseFont /Helvetica /Encoding /WinAnsiEncoding") && pdf.contains("/BaseFont /Helvetica-Bold "))
        #expect(pdf.contains("1 0 0 rg\n"))
        #expect(pdf.contains("/A500 gs\n0 0 1 rg\n") && pdf.contains("/A500 << /ca 0.5 /CA 0.5 >>"))
        #expect(pdf.contains("/Title (Maintenance \\(2025\\))") && pdf.contains("/Author (Car Owner)"))

        // The cross-reference table points at each object, and startxref at the table.
        let bytes = [UInt8](data)
        let tail = String(decoding: bytes.suffix(40), as: UTF8.self)
        let xref = try #require(Int(tail.split(separator: "\n").dropLast().last.map(String.init) ?? ""))
        #expect(String(decoding: bytes[xref..<(xref + 4)], as: UTF8.self) == "xref")
        let table = String(decoding: bytes[xref...], as: UTF8.self).split(separator: "\n")
        #expect(table[2] == "0000000000 65535 f ")
        let offset = try #require(Int(String(table[3].prefix(10))))
        #expect(String(decoding: bytes[offset..<(offset + 7)], as: UTF8.self) == "1 0 obj")
    }

    @Test func pdfKitOpensTheFileAsDrawn() throws {
        let renderer = report()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("report-\(UUID().uuidString).pdf")
        try renderer.writePDF(to: url) { draw($0) }
        let document = try #require(PDFDocument(url: url))
        #expect(document.documentURL == url && document.pageCount == 2 && !document.isLocked)
        #expect(document.documentAttributes?["Title"] as? String == "Maintenance (2025)")
        let first = try #require(document.page(at: 0))
        #expect(document.page(at: 2) == nil && document.index(for: first) == 0 && first.label == "1")
        #expect(first.bounds(for: .mediaBox) == a4)
        #expect(first.string == "Oil change" && document.string == "Oil change\nCafé")

        // The thumbnail fits the page's proportions inside the size asked for, on white.
        let thumbnail = first.thumbnail(of: CGSize(width: 390, height: 422), for: .mediaBox)
        #expect(thumbnail.size == CGSize(width: 298, height: 422))
        let commands = try #require(thumbnail.drawing?.commands)
        #expect(commands.contains(.fillRect(a4, RGBA(red: 1, green: 1, blue: 1, alpha: 1))))
        #expect(commands.contains { if case .drawText("Oil change", _, _, _) = $0 { return true }; return false })

        // Unchanged, the document gives back its data; changed, it writes its pages afresh.
        let saved = try Data(contentsOf: url)
        #expect(document.dataRepresentation() == saved)
        document.removePage(at: 0)
        let rewritten = try #require(document.dataRepresentation().flatMap { PDFDocument(data: $0) })
        #expect(rewritten.pageCount == 1 && rewritten.page(at: 0)?.string == "Café")
        try? FileManager.default.removeItem(at: url)
    }

    @Test func noPagesAndPagesOfTheirOwnSize() throws {
        let empty = UIGraphicsPDFRenderer(bounds: a4).pdfData { _ in }
        #expect(PDFDocument(data: empty)?.pageCount == 0)
        let data = UIGraphicsPDFRenderer(bounds: a4).pdfData { context in
            context.beginPage(withBounds: CGRect(x: 0, y: 0, width: 200, height: 100), pageInfo: [:])
            #expect(context.pdfContextBounds.size == CGSize(width: 200, height: 100))
            context.beginPage()
        }
        let document = try #require(PDFDocument(data: data))
        #expect(document.page(at: 0)?.bounds(for: .cropBox).size == CGSize(width: 200, height: 100))
        #expect(document.page(at: 1)?.bounds(for: .mediaBox) == a4 && document.page(at: 1)?.string == nil)
    }

    @Test func anotherPDFsPagesAndSizes() throws {
        // Two pages, the first with a box of its own, the second inheriting the tree's.
        let foreign = """
        %PDF-1.7
        1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj
        2 0 obj << /Type/Pages /Kids [3 0 R 4 0 R] /Count 2 /MediaBox [0 0 612 792] >> endobj
        3 0 obj << /Type /Page /Parent 2 0 R /MediaBox [ 0 0 300.5 400 ] >> endobj
        4 0 obj << /Type/Page /Parent 2 0 R >> endobj
        5 0 obj << /Title (A \\(small\\) file) /Producer (\\376\\377\\000H\\000i) >> endobj
        trailer << /Root 1 0 R /Info 5 0 R >>
        %%EOF
        """
        let document = try #require(PDFDocument(data: Data(foreign.utf8)))
        #expect(document.majorVersion == 1 && document.minorVersion == 7)
        #expect(document.pageCount == 2)
        #expect(document.page(at: 0)?.bounds(for: .mediaBox).size == CGSize(width: 300.5, height: 400))
        #expect(document.page(at: 1)?.bounds(for: .mediaBox).size == CGSize(width: 612, height: 792))
        #expect(document.documentAttributes?["Title"] as? String == "A (small) file")
        #expect(document.documentAttributes?["Producer"] as? String == "Hi")
        #expect(PDFDocument(data: Data("not a pdf".utf8)) == nil)

        // A page made from a drawn image keeps the drawing; a new page is US Letter.
        let image = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 30)).image { $0.fill(CGRect(x: 0, y: 0, width: 40, height: 30)) }
        let page = try #require(PDFPage(image: image))
        #expect(page.bounds(for: .mediaBox).size == CGSize(width: 40, height: 30))
        #expect(PDFPage().bounds(for: .mediaBox).size == CGSize(width: 612, height: 792))
        let made = PDFDocument()
        made.insert(page, at: 0)
        #expect(made.pageCount == 1 && page.document === made && page.label == "1")
        let reopened = try #require(made.dataRepresentation().flatMap { PDFDocument(data: $0) })
        #expect(reopened.page(at: 0)?.bounds(for: .mediaBox).size == CGSize(width: 40, height: 30))
    }
}
