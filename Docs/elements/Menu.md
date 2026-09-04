# Menu, contextMenu

Apple docs: [Menu](https://developer.apple.com/documentation/swiftui/menu),
[contextMenu](https://developer.apple.com/documentation/swiftui/view/contextmenu(menuitems:)).

## API surface

| API | Notes |
|---|---|
| `Menu(_ title:content:)`, `Menu(content:label:)`, `Menu(_:systemImage:content:)`, `Menu(_:image:content:)`, `Menu(_ configuration:)` | implemented |
| `Menu(_:content:primaryAction:)` | implemented: a split button; the label part runs the action, the indicator part opens the menu |
| `MenuStyle`, `MenuStyleConfiguration`, `.automatic`, `.button`, `.borderlessButton`, `menuStyle(_:)` | implemented (`.button` looks like `.automatic` on macOS; `.borderlessButton` drops the box) |
| `menuIndicator(_:)` | implemented (`.hidden` drops the chevron and its space) |
| `menuOrder(_:)`, `MenuOrder` | accepted, no effect (fixed order) |
| `Button`, `Divider`, nested `Menu` inside a menu | implemented: rows, separators, submenus beside their row |
| `contextMenu(menuItems:)`, `contextMenu(menuItems:preview:)` | implemented on a secondary click (the preview is not shown) |
| `Toggle`/`Picker` in menus (checked rows), `Section` headers in menus, `Label` icons in rows, keyboard navigation, hover highlight, `menuActionDismissBehavior`, `contextMenu(forSelectionType:)` | missing |

## Behaviour

`Menu.body` becomes `_MenuHost`, whose `MenuButtonNode` is the pull-down button: the pop-up
picker's box (`fillRRect`, radius 6, black at 20/255, 24 tall), the label 12 pt in, and one
downward chevron centred 12 pt before the trailing edge (7 wide, 3.5 tall, 1.5 stroke, round
caps). A press presents `_MenuContent(content)` with the presentation layer's `.menu` kind under
the button (`Docs/elements/Presentation.md`); `_MenuContent` stacks the items with 4 pt above and
below and sets `_inMenu`, under which `Button` renders `_MenuRowLabel` (the label after a 22 pt
check column, 16 pt trailing, at least 92.5 × 22), `Divider` becomes an 11 pt separator (a
1 pt line, 8 pt in from the sides) and `Menu` becomes a `SubmenuRowNode` (a row with a trailing
chevron) that presents `.submenu` beside the row, its first item level with the row (flipped to
the left when it would overflow). A row's action then dismisses every open menu
(`Runtime.dismissMenus`); a press outside a submenu closes it and continues to the parent menu.

With a `primaryAction` the button is split: 8 pt after the label a 1 pt divider (5 pt in from
the top and bottom), 24 pt to the trailing edge with a 1 pt chevron centred 11.25 pt before
it. Presses left of the divider run the action, presses on the indicator open the menu.

`contextMenu` wraps its view in `ContextMenuNode`; `Runtime.secondaryPointerDown(at:)` (the
canvas host forwards pointer button 2 and suppresses the browser's own context menu) hit-tests
for the deepest such node and presents `.menu` at the pointer. Over an open presentation a
secondary click behaves as a primary one (a click outside a menu dismisses it).

Semantics: the pull-down and submenu rows are `popUpButton`s labelled by their text, so probes
and assistive technology press them through the overlay.

## Measured (macOS 26.2, `menu/basic`, 2026-09-04)

| Property | Value | Probe |
|---|---|---|
| Pull-down box | label width + 47.5 (12 + 18 + 7 + 10.5), 24 tall | `options` (95 × 24 for "Options" 47.5), `custom`, `buttonStyle` |
| Split button | label width + 45 (12 + 8 + 1 + 24), divider 5 pt in, chevron centre 11.25 pt before the trailing edge | `primary` (91.5 × 24) |
| No indicator | label width + 24 | `noIndicator` (67.5 × 24) |
| `.button` style | same box as `.automatic` | `buttonStyle` (77 × 24) |
| Chevron | one, 7 × 3.5 centred 12 pt before the trailing edge, 1.5 stroke | pixels of `options` |
| Context menu, `Text` | the view's own frame | `context` |

Apple's capture shows the split button in the inactive look (grey label, thin chevron) although
the other buttons are active; the painter uses the active look, which costs a few hundred
pixels in Tier B.

## Verification (2026-09-04)

Tier A: `menu/basic` exact. Tier B 1/1 in Chromium (0.74 %), WebKit (0.41 %) and Firefox
(0.82 %), frames exact in all three. `MenuTests` cover the three button sizes, presenting on a press, rows
and separators, activation closing the menu, the split button, submenus and context menus;
`Playwright/menu-probe.mjs` drives the same through the accessibility overlay in Chromium,
including a right click. wasm js tests pass.

## Not yet covered

The menus themselves (macOS opens them in separate windows the golden cannot capture): the
real row highlight on hover, key equivalents, section headers, checked items, icons in rows,
keyboard navigation, the split button's active look, `.borderlessButton` metrics.
