// Apple's `CoreImage` module for wasm: images, filters and contexts (SwiftUIWeb's WebCoreImage,
// Docs/elements/CoreImage.md), with CoreGraphics, which Apple's CoreImage brings with it.
// Kingfisher's image filters (tint, colour controls) go through it.
#if os(WASI)
@_exported import CoreGraphics
@_exported import WebCoreImage
#endif
