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
| `NavigationPath` (`init`, `init(_ sequence:)`, `count`, `isEmpty`, `append`, `removeLast`) | implemented |
| `NavigationPath.CodableRepresentation`, `NavigationPath(_ codable:)`, `codable` | implemented (2026-10-04): the elements' mangled type names and JSON, last element first, through the runtime's own JSON coder; an element that is not `Codable` makes `codable` nil; restoring stops at a type the program no longer declares (private and local types cannot be looked up by name) |
| `NavigationLink(destination:label:)`, `NavigationLink("title") { destination }`, `NavigationLink(value:label:)`, `NavigationLink("title", value:)` | implemented (`value: nil` disables the link) |
| `navigationDestination(for:destination:)` | implemented: registered with the enclosing stack by type; values of an unregistered type are ignored |
| `navigationDestination(isPresented:destination:)` | implemented (the binding is read in a body, so observation pushes and pops) |
| `navigationDestination(item:destination:)` | implemented (2026-10-04, `nav/item`): pushed while the item is non-nil, a new item swaps the pushed screen in place, nil pops, popping sets nil |
| `navigationTitle(_:)` (`Text`, key, string) | recorded on `Runtime.navigationTitle` for hosts; not drawn (window chrome on macOS) |
| `navigationSubtitle` | stored only |
| `navigationBarBackButtonHidden` | implemented for the iOS bar (`Docs/elements/iOS.md`); nothing to hide on macOS |
| `NavigationSplitView` | see `Docs/elements/NavigationSplitView.md` |
| `toolbar`, `toolbarBackground` | see `Docs/elements/Toolbar.md` (the title joins the bar when a host paints window chrome) |
| `navigationBarTitleDisplayMode` | implemented for the iOS bar (`Docs/elements/iOS.md`); no effect on macOS |
| ⌘[ and Escape | implemented (2026-10-04): pop the navigation stack around the focused control, else the first stack with a pushed screen; after a presentation's own Escape handling |
| `NavigationView` (deprecated), `navigationViewStyle` | missing |
| Back navigation | `Runtime.navigateBack()` pops the innermost stack (hosts wire a button or key); macOS paints no back button and does not animate. iOS: the bar's back button and the push/pop slide, `Docs/elements/iOS.md` |

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
the top entry's size, and every layer, root included, is centred in a box as large as the
largest layer anchored at the frame's top-left (`nav/path-change`, 2026-10-04: a 16 pt presented
screen over a 44 pt root sits 14 pt down, hanging out of the frame, and the root at the frame's
top; a 72 pt pushed screen holds the root 14 pt down); only the root and the top layer are laid
out (a value screen under a presented one reports no probe), only the top layer is painted
and hit-tested. Preferences follow: under a pushed view only the root and that view report;
under a value screen every path screen does (`nav/steps` on macOS 26.2 reported the lower
value screen's probes). A path change keeps the screens pushed above it (destination links, presented and
item destinations): clearing the path under a presented screen leaves that screen on top with
its binding on, as SwiftUI does. Inside a `List` row (`_inListRow` environment) a link is its
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

## Measured (macOS 26.6, `nav/item`, `nav/path-change`, 2026-10-04)

| Behaviour | Value | Fixture |
|---|---|---|
| `navigationDestination(item:)` | setting the item pushes its screen (probes `itemA`, `detail`), a new item swaps it (`itemB`), nil pops back to the root | `nav/item` steps |
| Stack size | the top screen's: 58 × 72 for the pushed three-row screen, 62 × 16 for the presented text, 28.5 × 44 for the root | `nav/path-change` |
| Lower screens | centred in the largest screen's box at the frame's top-left: the root at y 78 under the 72 pt screen, at the frame's y 92 under the 16 pt one (which sits at 106) | `nav/path-change` |
| Path cleared under a presented screen | the presented screen stays (its probe reports, the value screen's does not) | `nav/path-change/clearPath` |

## Not yet covered

The row a `List` under an iOS large title lands on after a programmatic scroll that collapses
the bar (UIKit re-anchors it: Docs/elements/iOS.md, "Scroll content under the bar").
Back button and title in macOS chrome (hosts) and the macOS push/pop animation (iOS has both,
`Docs/elements/iOS.md`; the 26.6 goldens for new fixtures avoid buttons, whose bezel moved),
toolbars, links that pop to the root or replace the path, restoring a codable path whose types
are private or local, the stack's hit testing of a lower screen hanging out of a small frame.
