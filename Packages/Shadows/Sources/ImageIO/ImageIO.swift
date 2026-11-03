// Apple's `ImageIO` module for wasm: image sources (WebGraphics's WebImageIO: a file's type,
// size, frames and delays, and its frames as `CGImage`s), with CoreGraphics, which Apple's
// ImageIO brings with it. Kingfisher and the image caches read GIF frames and make thumbnails
// through it.
#if os(WASI)
@_exported import CoreGraphics
@_exported import WebImageIO
#endif
