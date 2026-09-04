# DisclosureGroup

Apple docs: [DisclosureGroup](https://developer.apple.com/documentation/swiftui/disclosuregroup),
[DisclosureGroupStyle](https://developer.apple.com/documentation/swiftui/disclosuregroupstyle).

## API surface

| API | Notes |
|---|---|
| `DisclosureGroup(_ title, content:)`, `DisclosureGroup(_ title, isExpanded:content:)`, `DisclosureGroup(isExpanded:content:label:)`, `DisclosureGroup(content:label:)` | implemented; without a binding the group keeps its own state (collapsed at first) |
| `DisclosureGroupStyle`, `DisclosureGroupStyleConfiguration` (`label`, `content`, `isExpanded` with its binding), `.automatic`, `disclosureGroupStyle(_:)` | implemented |
| The expand/collapse animation, `DisclosureGroup` inside `List` (outline rows), `OutlineGroup` | missing |

## Behaviour

`AutomaticDisclosureGroupStyle` stacks a row and, when expanded, the content. The row is a plain
`Button` toggling the binding: the chevron (6.5 wide, 8 tall, a 1.5 pt grey stroke at black
64/255, pointing right when collapsed and down when expanded), 5, the label, padded 4 above and
below, stretched to the full width and leading-aligned; the content is a centred `VStack` right
under the row (no spacing), so a text over a checkbox keeps their own 6.

## Measured (macOS 26.2, `disclosure/basic`, 2026-09-04)

| Property | Value | Probe |
|---|---|---|
| Row | full width, 24 tall for a 16 pt text label (4 above and below); a 24 pt `Label` makes a 32 row | `group`, `expanded`, `customLabel` |
| Label | at x 11.5 (the chevron's 6.5 and 5) | `customLabel` |
| Chevron | grey (191 over white = black 64/255); collapsed ink 1.5…4 × 8…16, expanded 0…6.5 × 10…14 | pixels |
| Expanded | the content directly under the row, centred; a text then a toggle 6 apart: 24 + 16 + 6 + 18.5 = 64.5 | step `expand` (`group`, `inside`, `toggle`) |
| Nesting | the inner group's row and content at the outer group's full width (no indent) | `inner`, `outer`, `nested` |

## Verification (2026-09-04)

Tier A: `disclosure/basic` exact, expand step included. Tier B: Chromium ≤ 0.28 %, WebKit 0.04 %, Firefox ≤ 0.35 %
with the expanded step's "Inside" in its glyph-hinting class (36 for 36.5); Tier C 0.04 %.
`DisclosureGroupTests` cover the row, the chevron, toggling by press, own state and a custom style.

## Not yet covered

The animation, the exact chevron glyph (approximate stroke), hover looks, outline rows in
lists, keyboard toggling (Space works through the button).
