# #Preview, PreviewProvider

Apple docs: [Preview(_:body:)](https://developer.apple.com/documentation/swiftui/preview(_:body:)),
[PreviewProvider](https://developer.apple.com/documentation/swiftui/previewprovider).

## API surface

| API | Notes |
|---|---|
| `#Preview(_ name:body:)`, `#Preview(_:traits:_:body:)` | implemented 2026-10-11: the macro keeps the body as a `_Preview` (name, traits, `#fileID`, line, body) in an enum with a compiler-unique name conforming to `_PreviewRegistration` |
| `PreviewTrait` (`sizeThatFitsLayout`, orientations, `fixedLayout`, `modifier(_:)`) | implemented: `fixedLayout` sizes the preview, `modifier` wraps it, the orientations are accepted |
| `PreviewModifier` (`makeSharedContext`, `body(content:context:)`), `PreviewModifierContent` | implemented: `_PreviewHost` awaits each modifier's shared context once and wraps the body |
| `_PreviewRegistry.all` | the app's previews: natively the `_PreviewRegistration` conformers read from the loaded images' Swift conformance records (`__TEXT,__swift5_proto`, Apple platforms); on wasm and Linux the ones registered (`_PreviewRegistry.registered`, filled by a generated index) |
| The gallery | shows the fixtures' `#Preview` blocks as `preview/<name>` fixtures at their fixed layout or 360 × 200 (`scripts/gen-fixture-sources.py` emits `GeneratedPreviews` from the source text; `demo/` previews `Card` and `Card, fixed`) |
| `PreviewProvider`, `previewLayout`, `previewDevice`, `previewDisplayName`, `PreviewDevice`, `PreviewLayout` | compile; accepted without effect (a `PreviewProvider`'s previews are not listed) |

## Behaviour

`SwiftUIWebMacros` is a SwiftPM macro target (swift-syntax 601, fetched as prebuilt libraries:
a clean build takes about 27 s). `PreviewMacro` expands a `#Preview` to an enum named by
`makeUniqueName` — a declaration macro at global scope may introduce no arbitrary name and no
extension, which is why Apple's previews use unique names and find them at run time — whose
`preview` is the `_Preview`. The macro is declared in the `SwiftUI` shim module, keeping
`SwiftUIWebCore` free of the dependency; the plugin runs on the host, so the wasm cross-compile
and the gallery build are unaffected.

Discovery: on Apple platforms `_PreviewRegistry.all` walks every loaded image's
`__swift5_proto` section (relative pointers to protocol conformance descriptors), keeps the
conformances to `_PreviewRegistration`, calls each type descriptor's metadata accessor and
reads `preview`. Wasm and Linux binaries carry the same records but no API reads them, so the
gallery registers a generated index: `gen-fixture-sources.py` copies each fixture `#Preview`'s
name, traits and body into `GeneratedPreviews` (the bodies must use the fixtures' public API,
which the macro-kept bodies need not). `_PreviewHost` renders a preview: without modifiers the
body itself; with them, `Color.clear` until every `makeSharedContext()` has resolved, then the
body wrapped by each modifier in order.

## Verification (2026-09-03; 2026-10-11)

`PreviewTests` declares three `#Preview`s (plain, named, with a `PreviewModifier` whose
context arrives asynchronously and a fixed layout) and finds them through the registry in
order, renders the kept body, sees the modifier wrap it once its context is made, and merges a
registered index without duplicates; the gallery shows `preview/card` and `preview/card-fixed`
(360 × 200 and 240 × 120, checked in Chromium). No golden: a preview body is not a screen.

## Not yet covered

Listing a `PreviewProvider`'s previews, device and orientation traits with effect, conformance
records on wasm and Linux (the generated index stands in).

## @Entry (2026-10-04)

The same macro target provides `@Entry`: on a `var` with an explicit type in an extension of
`EnvironmentValues`, `FocusedValues` or `Transaction` it adds a private key type named after the
property (`__Key_name`, an `EnvironmentKey`, `FocusedValueKey` or `TransactionKey`) and
accessors over the container's subscript. Environment and transaction entries need a default
value; focused entries are optional and take none. Applied anywhere else, or without a type,
the macro reports an error. `EntryMacroTests` use all three containers.
