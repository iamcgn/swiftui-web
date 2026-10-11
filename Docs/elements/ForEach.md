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
| `DynamicViewContent` (`data`), `onDelete`, `onMove`, `onInsert`, `ForEach(_:editActions:)` | `onDelete` and `onMove` drive a list's editing (`Docs/elements/List.md`, 2026-09-18); `onInsert` is accepted without effect |

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

## Subviews and sections (sw-subviews; macOS 26.6, `foreach/subviews`, `foreach/subviews-foreach`, `foreach/sections`, `foreach/container-values`; 2026-10-11)

Apple docs: [Group(subviews:transform:)](https://developer.apple.com/documentation/swiftui/group/init(subviews:transform:)),
[ForEach(subviews:content:)](https://developer.apple.com/documentation/swiftui/foreach/init(subviews:content:)),
[SectionCollection](https://developer.apple.com/documentation/swiftui/sectioncollection),
[ContainerValues](https://developer.apple.com/documentation/swiftui/containervalues).

The container forms resolve a view value's structural children before any node exists
(`API/Subviews.swift`, `_Subviews.structure`): a tuple's elements, a `ForEach`'s elements (with
their identities), a conditional's branch, an optional's value, a `Group`'s children, an
`AnyView`'s content, a `Section` (its content for the `subviews:` forms; header, content and
footer for `sections:`), and a modifier on a container applied to each child (`Group { … }
.padding(.leading, 6)` is two padded subviews; measured: `subviews.count` is 6 for a tuple of a
text, a two-element `ForEach`, an `if`, and such a group). A custom view resolves through its
body when the body is a container holding several children; a view whose body comes to one
piece (`Button`) stays itself with its state and style. Identities: a `ForEach` element's id, an
`id(_:)`, else the index. Loose views between sections form a section of their own without a
header (`Top` and `Bottom` make the second of three sections). `ContainerValues` are set per
child by `containerValue(_:_:)` (declared with `@Entry` in an extension, the fourth container
the macro accepts) and `tag(_:)` (`containerValues.tag(for:)`, `hasTag`); on a group they reach
every child, an outer tag replacing an inner one. `SubviewsCollection` and its slices are views
(each subview in turn) and random-access collections.

Open: `containerValues` read by `List`/`Picker` for their own purposes, `SubviewsCollection`
inside lazy containers (resolved eagerly), the `ForEach(sections:)` form inside `List`.

## Open

- `Section` header styling inside `Form`, `Picker` (`List` is done: `Docs/elements/List.md`).
- Duplicate-id warning; `onInsert` by drop.
- Tier B: Chromium and WebKit exact frames on all 14 fixtures (every identity step included);
  Firefox measures "Vegetables" 0.5 pt wider, which shifts the leading-aligned column of
  `section/title` and `section/foreach` by 0.25 pt (text-width class, not a ForEach/Section issue).
