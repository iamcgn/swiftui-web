# ForEach and Section

Apple docs: [ForEach](https://developer.apple.com/documentation/swiftui/foreach),
[DynamicViewContent](https://developer.apple.com/documentation/swiftui/dynamicviewcontent),
[Section](https://developer.apple.com/documentation/swiftui/section),
[Identifiable](https://developer.apple.com/documentation/swift/identifiable).

## API surface

`ForEach<Data: RandomAccessCollection, ID: Hashable, Content>` with public `data` and `content`:

| Initialiser | Notes |
|---|---|
| `init(_ data:, content:)` where `Data.Element: Identifiable`, `ID == Element.ID` | implemented |
| `init(_ data:, id: KeyPath<Element, ID>, content:)` | implemented |
| `init(_ data: Range<Int>, content:)` (`ID == Int`) | implemented; the range is read once, as documented |
| `init(_ data: Binding<C>, content: (Binding<C.Element>) -> R)` and the `id:` form | implemented; `Data == LazyMapSequence<C.Indices, (C.Index, ID)>`. Note that `Binding` is itself a `RandomAccessCollection` of element bindings, so `ForEach($items)` resolves to the plain collection initialiser with `Data == Binding<[Item]>`; behaviour is identical |
| `init(_ data: Binding<C>, editActions:…)` (iOS 16 / macOS 13) | missing (needs `List`) |
| `init(subviews:)`, `init(sections:)`, `ForEach(_:id:) { … }` over `Subviews` (iOS 18 / macOS 15) | missing |
| `DynamicViewContent` (`data`), `onDelete`, `onMove`, `onInsert` | protocol and `data` only |

`Section<Parent, Content, Footer>`:

| Initialiser | Notes |
|---|---|
| `init(content:header:footer:)`, `init(content:header:)`, `init(content:footer:)`, `init(content:)` | implemented |
| `init(_ titleKey: LocalizedStringKey, content:)`, `init<S: StringProtocol>(_ title:, content:)` (`Parent == Text`) | implemented |
| deprecated `init(header:content:)`, `init(footer:content:)`, `init(header:footer:content:)` | implemented, marked deprecated |
| `init(_:isExpanded:content:)`, `.collapsible(_:)`, `.listSectionSeparator`, `.headerProminence` | missing (need `List`/`Form`) |

## Runtime

`ForEachNode` is the one place the tree reconciles by key (ARCHITECTURE invariant 1). On each
update it walks the data, computes every element's id, and reuses the node that had that id last
time (updating it with the new element's content), creates a node for a new id, and unmounts
nodes whose ids vanished. Children are ordered like the data; duplicate ids get independent
nodes in order (SwiftUI logs a warning for duplicates). `SectionNode` keeps three children and
flattens them (invariant 2). Both are transparent to layout: their `layoutChildren` are the
elements' layout nodes, so stacks see the elements directly and unary modifiers distribute over
them through the existing proxy mechanism.

## Measured behaviours (macOS 26.2, SwiftUI 7.2.5, hosted-window goldens 2026-09-02)

| Behaviour | Value | Fixture |
|---|---|---|
| Elements lay out as direct children of the enclosing stack | `ForEach(0..<3)` between two texts: pitch 16 pt in a `VStack`, no extra spacing | `foreach/range`, `foreach/identifiable`, `foreach/id-keypath` |
| Empty `ForEach` | contributes nothing, no spacing (top 76 → row 92 → bottom 108) | `foreach/empty` |
| Modifier on a `ForEach` | applies to **every** element: `.padding()` makes each row 48 pt tall, `.frame(width: 120, height: 30).background(Color.blue)` frames each row; a preference written under one id resolves to the **last** element (`paddedLast`, `framedLast`) | `foreach/modifier` |
| Nested `ForEach` | inner elements flatten into the inner stack (3 × 30 + 2 × 8 = 106 wide rows) | `foreach/nested` |
| `ForEach($items)` | element bindings; layout as for values | `foreach/binding` |
| Identity across data changes | rows keep `@State` seeded at creation by id: after inserting at the front, mutating an item's model value (`@State` ignores the new initial value, row "a" stays 60 wide), reversing and removing, every surviving row keeps its width and follows its id | `foreach/identity` (4 steps) |
| `Section` outside `List`/`Form` | header, content and footer flatten in order; a `Section("Title")` header is a plain default-font `Text` (16 pt line, no styling): `section/title` stack is 4 × 16 = 64 tall | `section/vstack`, `section/title`, `section/hstack`, `section/foreach`, `section/mixed` |
| Modifier on a `Section` | applies to header, each content view and footer separately (`section/modifier` stack = 48 + 48 + 30 + 30 = 156) | `section/modifier` |
| Default-font text→text spacing in a `VStack` | 0 (the 13 pt system font's `textToText` value), so rows pack at their 16 pt line height | all of the above |

## Open

- `Section` header styling inside `List`, `Form`, `Picker` (element `List`).
- Duplicate-id warning; `onDelete`/`onMove` edit actions; `Subviews`-based `ForEach`.
- Pixel look of `foreach/*` and `section/*` is text and colour swatches only; see Tier B.
