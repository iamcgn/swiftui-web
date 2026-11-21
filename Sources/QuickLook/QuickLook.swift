// Quick Look on the web: `quickLookPreview` presents a sheet that shows the file at the bound URL
// (an image drawn to fit, anything else by its name with a link that opens it in the browser)
// with a Done button that clears the binding, as dismissing Apple's preview does. A file the app
// wrote itself (IceCubes copies a picture to a temporary folder first) is read and decoded here,
// since the browser can't load a file URL; a remote image loads as `AsyncImage` does. Several
// items page with Previous and Next. Apple's framework re-exports Foundation; its SwiftUI part
// is a cross-import, so the modifiers are there in a file that imports SwiftUI too.
#if os(WASI)
@_exported import WebFoundation
#else
import Foundation
#endif
import SwiftUI

extension View {
    /// Presents a preview of the file at the binding's URL while it holds one; dismissing the
    /// preview sets the binding to `nil`.
    nonisolated public func quickLookPreview(_ item: Binding<URL?>) -> some View {
        sheet(isPresented: _QuickLookPresented(item).binding) {
            _QuickLookPreview(urls: item.wrappedValue.map { [$0] } ?? [], selection: item)
        }
    }

    /// Presents a preview of `items`, opened at the selection, while the selection holds one;
    /// paging moves the selection, and dismissing the preview sets it to `nil`.
    nonisolated public func quickLookPreview<Items: RandomAccessCollection>(_ selection: Binding<Items.Element?>, in items: Items) -> some View
    where Items.Element == URL {
        let urls = Array(items)
        return sheet(isPresented: _QuickLookPresented(selection).binding) {
            _QuickLookPreview(urls: urls, selection: selection)
        }
    }
}

/// Whether a preview is up: while the binding holds a URL.
struct _QuickLookPresented {
    let item: Binding<URL?>
    init(_ item: Binding<URL?>) { self.item = item }
    var binding: Binding<Bool> {
        let item = item
        return Binding(get: { item.wrappedValue != nil }, set: { if !$0 { item.wrappedValue = nil } })
    }
}

/// The file extensions a preview draws as an image.
let _quickLookImageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "heic", "heif", "bmp", "tif", "tiff"]

/// The preview: the selected file, its name as the title, Done, and paging through several.
struct _QuickLookPreview: View {
    let urls: [URL]
    @Binding var selection: URL?

    private var index: Int? { selection.flatMap { urls.firstIndex(of: $0) } }

    var body: some View {
        NavigationStack {
            Group {
                if let url = selection {
                    _QuickLookItem(url: url).id(url)
                } else {
                    EmptyView()
                }
            }
            .navigationTitle(selection?.lastPathComponent ?? "")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { selection = nil }
                }
                if urls.count > 1 {
                    ToolbarItem(placement: .bottomBar) {
                        HStack {
                            Button("Previous") { step(-1) }.disabled((index ?? 0) == 0)
                            Spacer()
                            Button("Next") { step(1) }.disabled((index ?? urls.count - 1) >= urls.count - 1)
                        }
                    }
                }
            }
        }
    }

    private func step(_ delta: Int) {
        guard let index else { return }
        let next = index + delta
        if urls.indices.contains(next) { selection = urls[next] }
    }
}

/// One file: an image drawn to fit, or the file's name with a link to open it.
struct _QuickLookItem: View {
    let url: URL

    private var isImage: Bool { _quickLookImageExtensions.contains(url.pathExtension.lowercased()) }

    var body: some View {
        if isImage, url.isFileURL {
            if let data = try? Data(contentsOf: url), let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                fileRow
            }
        } else if isImage {
            AsyncImage(url: url) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                ProgressView()
            }
        } else {
            fileRow
        }
    }

    private var fileRow: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc")
                .font(.largeTitle)
            Text(url.lastPathComponent)
            if !url.isFileURL {
                Link("Open", destination: url)
            }
        }
        .padding()
    }
}
