// Apple's `ImageIO` module for wasm: image sources and destinations (WebGraphics's WebImageIO: a
// file's type, size, frames and delays, its frames as `CGImage`s, and images written as files),
// with CoreGraphics, which Apple's ImageIO brings with it. Kingfisher and the image caches read
// GIF frames and make thumbnails through it.
#if os(WASI)
@_exported import CoreGraphics
@_exported import WebImageIO
#endif
