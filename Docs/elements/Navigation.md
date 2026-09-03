# NavigationStack, NavigationLink

Apple docs: [NavigationStack](https://developer.apple.com/documentation/swiftui/navigationstack),
[NavigationLink](https://developer.apple.com/documentation/swiftui/navigationlink),
[NavigationPath](https://developer.apple.com/documentation/swiftui/navigationpath),
[navigationDestination(for:destination:)](https://developer.apple.com/documentation/swiftui/view/navigationdestination(for:destination:)),
[navigationDestination(isPresented:destination:)](https://developer.apple.com/documentation/swiftui/view/navigationdestination(ispresented:destination:)),
[navigationTitle(_:)](https://developer.apple.com/documentation/swiftui/view/navigationtitle(_:)-avgj).

## API surface

| API | Notes |
|---|---|
| `NavigationStack(root:)`, `NavigationStack(path: Binding<NavigationPath>, root:)`, `NavigationStack(path: Binding<Data>, root:)` (homogeneous collections) | implemented |
| `NavigationPath` (`init`, `init(_ sequence:)`, `count`, `isEmpty`, `append`, `removeLast`) | implemented; `codable` representation missing |
| `NavigationLink(destination:label:)`, `NavigationLink("title") { destination }`, `NavigationLink(value:label:)`, `NavigationLink("title", value:)` | implemented (`value: nil` disables the link) |
| `navigationDestination(for:destination:)` | implemented: registered with the enclosing stack by type; values of an unregistered type are ignored |
| `navigationDestination(isPresented:destination:)` | implemented (the binding is read in a body, so observation pushes and pops) |
| `navigationDestination(item:destination:)` | missing |
| `navigationTitle(_:)` (`Text`, key, string) | recorded on `Runtime.navigationTitle` for hosts; not drawn (window chrome on macOS) |
| `navigationSubtitle`, `navigationBarBackButtonHidden` | stored only |
| `navigationBarTitleDisplayMode`, `toolbar`, `toolbarBackground`, `NavigationSplitView`, `NavigationView` (deprecated), `navigationViewStyle` | missing |
| Back navigation | `Runtime.navigateBack()` pops the innermost stack (hosts wire a button or key); no painted back button or slide animation |

## Behaviour

`NavigationStack` is a composite: its body reads the path (binding or private `@State`) so
observation tracks it and hands `_NavigationStackHost` the root and the path values.
`NavigationStackNode` mounts the root with a `_navigationContext` in the environment that links
and `navigationDestination(for:)` modifiers use to find it. On every update it re-reads the path:
value entries are reconciled against the path (nodes for the unchanged prefix are kept), views
pushed by destination links or `isPresented` bindings stay after them; each entry's view is
rebuilt from the registered builder so state in the destination closure flows through. A value
link appends to the path through the binding and the stack re-reads it at once (so a binding
nobody observes still navigates); a destination link appends a view entry. Layout: the stack is
the top entry's size and every layer, root included, is placed centred in that frame; only the
top layer is painted and hit-tested. Inside a `List` row (`_inListRow` environment) a link is its
plain label carrying a `NavigationLinkActivationKey` layout value that `ListContentNode` runs when
the row is pressed; elsewhere it is a `Button` (default style) whose action pushes.

## Measured (macOS 26.2, `nav/basic`, `nav/list`, `nav/title`, `nav/sizing`, `nav/steps`, 2026-09-02)

| Property | Value | Probe |
|---|---|---|
| Stack size | exactly its content's: a `VStack` of 168 sits at y = 46 in a 260 pt fixture; `Color` fills (320 × 192 in a stack of three), a text is 33 × 16, a `frame(width: 100)` is honoured | `nav`, `stack`, `navFill`, `navText`, `navLeft` |
| Link outside a list | a bordered button: "Detail" 59 × 24 (label + 24), a 24 pt `Label` makes it 73.5 × 32, `frame(maxWidth:)` around a link is 320 wide | `link`, `labelLink`, `wideLink`, `valueLink` |
| Link in a list row | the plain label: "Apple" 35 × 16 at (16, 14), a `Label` 39.5 × 24 with the list's icon slot and tint; no disclosure chevron on macOS | `row1`, `row2`, `row3` |
| Title, subtitle | nothing in the content (window chrome): "Content" stays centred | `content` |
| Push | the pushed view is centred in the fixture (`Number 1` 58 × 16 at (131, 74), stack 68.5 × 52) and the root keeps its frame beneath it (`Root` at (145.75, 74)) | `nav/steps` steps `push1`, `push2` |
| Pop | popping to a shorter path shows that entry; an empty path shows the root | steps `pop`, `popAll` |

## Verification (2026-09-02)

Tier A: 5 fixtures exact (`nav/steps` steps included). Tier B, frames exact: Chromium ≤ 0.15 %
pixels, WebKit ≤ 0.06 %; Firefox 6/9 with every failure the same 0.5 pt wider "Number 1"
(x 130.75 vs 131, width 58.5 vs 58: the `Vegetables` glyph-hinting class), pixels ≤ 0.18 %.
wasm js tests pass.

## Not yet covered

Back button and title in chrome (hosts), push/pop animation, `navigationDestination(item:)`,
`NavigationSplitView` and sidebars, toolbars, `NavigationPath` codable representation, links
that pop to the root or replace the path, a value pushed from a view that a later path change
removes (the destination-link entry stays on top), keyboard shortcuts (⌘[ / Escape).
