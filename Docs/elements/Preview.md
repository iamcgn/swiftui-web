# #Preview, PreviewProvider

Apple docs: [Preview(_:body:)](https://developer.apple.com/documentation/swiftui/preview(_:body:)),
[PreviewProvider](https://developer.apple.com/documentation/swiftui/previewprovider).

## API surface

| API | Notes |
|---|---|
| `#Preview(_ name:body:)`, `#Preview(_:traits:_:body:)` | implemented as a declaration macro that expands to nothing |
| `PreviewTrait` (`sizeThatFitsLayout`, orientations, `fixedLayout`) | stubs |
| `PreviewProvider` | protocol only (nothing renders previews) |
| `#Preview` with `PreviewModifier`, `previewLayout`, `previewDevice`, `previewDisplayName` | missing |

## Behaviour

Previews are an editor feature. `SwiftUIWebMacros` is a SwiftPM macro target (swift-syntax
601, fetched as prebuilt libraries: a clean build takes about 27 s) whose `PreviewMacro` returns
no declarations, so preview blocks in app sources compile and leave nothing behind. The macro is
declared in the `SwiftUI` shim module, keeping `SwiftUIWebCore` free of the dependency; the plugin
runs on the host, so the wasm cross-compile and the gallery build are unaffected.

## Verification (2026-09-03)

`PreviewTests` compiles both `#Preview` forms and a `PreviewProvider` in a test module; the
wasm `js test` compiles the same file through the host plugin; the gallery builds. No golden.

## Not yet covered

Rendering previews (a gallery of `#Preview` bodies would need a macro that keeps the body), the
`PreviewModifier` protocol, device and layout traits with effect.
