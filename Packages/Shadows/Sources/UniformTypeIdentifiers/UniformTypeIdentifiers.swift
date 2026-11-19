// Apple's `UniformTypeIdentifiers` module for wasm (Docs/coverage.md: 12 apps, the most-imported
// framework SwiftUIWeb lacked): `UTType`, which SwiftUIWeb already shares between its transfer
// representations and UIKitWeb's document picker (WebGraphics/Input/UTType.swift), under the
// name an app's source imports. Like Apple's, it brings Foundation in with it: a file that
// imports only it may name `Data` and `URL` (Mlem's upload requests).
#if os(WASI)
@_exported import Foundation
@_exported import struct WebGraphics.UTType
#endif
