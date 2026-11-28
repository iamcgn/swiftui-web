// A `DataRepresentation` whose exporter waits (IceCubes' media image fetches its bytes before
// handing them on): the export runs where it can wait, and the synchronous paths skip it.
import Foundation
import Testing
import SwiftUI
import SwiftUIWebCore

#if !os(WASI)
private struct FetchedImage: Transferable {
    let bytes: [UInt8]
    func fetchData() async -> Data {
        await Task.yield()
        return Data(bytes)
    }
    static var transferRepresentation: some TransferRepresentation<FetchedImage> {
        DataRepresentation(exportedContentType: .jpeg) { image in await image.fetchData() }
    }
}

private struct Note: Transferable {
    static var transferRepresentation: some TransferRepresentation<Note> {
        DataRepresentation(importedContentType: .plainText) { _ in Note() }
    }
}

@Suite struct AsyncTransferTests {
    @Test func anAsyncExporterRunsWhereTheExportCanWait() async {
        let image = FetchedImage(bytes: [0xFF, 0xD8, 0xFF])
        let exporters = DataRepresentation<FetchedImage>(exportedContentType: .jpeg) { image in await image.fetchData() }._exporters
        #expect(exporters.count == 1 && exporters[0].contentType == .jpeg)
        #expect(exporters[0].export(image) == nil)
        let exported = await exporters[0].asyncExport?(image) as? Data
        #expect(exported == Data([0xFF, 0xD8, 0xFF]))
        // A synchronous exporter keeps its own path and has no waiting one.
        let plain = DataRepresentation<FetchedImage>(exportedContentType: .png) { Data($0.bytes) }._exporters
        #expect(plain[0].export(image) as? Data == Data([0xFF, 0xD8, 0xFF]) && plain[0].asyncExport == nil)
        // A share link has nothing to hand on at once from a waiting exporter.
        #expect(await MainActor.run { _ShareItem(image) } == nil)
    }

    @Test func anImportOnlyRepresentationImportsAndExportsNothing() {
        let exporters = Note.transferRepresentation._exporters
        #expect(exporters.count == 1 && exporters[0].export(Note()) == nil)
        #expect(exporters[0].importer?(Data("hi".utf8)) != nil)
    }
}
#endif
