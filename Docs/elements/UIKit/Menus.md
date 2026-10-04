# UIMenu, UIContextMenuInteraction, UIEditMenuInteraction

`Packages/UIKitWeb/Sources/UIKitWebCore/Containers/Menus.swift` (uk-menus, 2026-10-04). The
harness cannot open a menu on the simulator (UIKit offers no way to present a button's menu or
trigger a context menu programmatically), so the card's geometry is approximate: an iOS-style
card, not measured pixels. `MenuTests` cover the behaviour.

## API

- `UIMenuElement` (title, image, subtitle) is the base of `UIAction` (`attributes`:
  `disabled`, `destructive`, `hidden`; `state`: `off`, `on`, `mixed`; `subtitle`), `UIMenu`
  (`children`, `options`: `displayInline`, `destructive`, `singleSelection`, `displayAsPalette`
  accepted; `identifier`, `preferredElementSize` accepted; `replacingChildren`,
  `flattenedActions`) and `UIDeferredMenuElement` (`init(_:)` cached, `uncached(_:)`; the
  provider's completion is expected synchronously, a later completion shows nothing).
- `UIButton.menu` with `showsMenuAsPrimaryAction` (a tap opens the menu instead of the primary
  action) or a 0.5 s long press otherwise; `changesSelectionAsPrimaryAction` shows the `on`
  action's title and moves the `on` state to the chosen action. `UIBarButtonItem(menu:)`: a
  platter with a menu and no primary action opens it on a tap, with both on a long press.
- `UIContextMenuInteraction(delegate:)` on any view: a 0.5 s press (within 10 pt) asks
  `contextMenuInteraction(_:configurationForMenuAtLocation:)`; the `UIContextMenuConfiguration`'s
  `actionProvider` builds the menu and its `previewProvider`'s controller view (sized to its
  `preferredContentSize`, else its bounds, else 250 × 150, 20 pt corners) floats above the card;
  the view's touch is cancelled; `willDisplayMenuFor` / `willEndFor` /
  `willPerformPreviewActionForMenuWith` run (the last never: there is no preview tap);
  `dismissMenu`, `location(in:)`.
- `UIEditMenuInteraction(delegate:)`: `presentEditMenu(with: UIEditMenuConfiguration(identifier:
  sourcePoint:))` asks `editMenuInteraction(_:menuFor:suggestedActions:)` (no suggested actions)
  and shows the actions as a capsule bar of 17 pt titles 6 above the point (below it near the
  top); `dismissMenu`, `reloadVisibleMenu`, `isVisible`, `updateVisibleMenuPosition`;
  `willPresentMenuFor` / `willDismissMenuFor` run.

## Behaviour

`MenuPresenter.present` presents a `MenuPanelController` (the custom modal style) from the
topmost presented controller; the presentation container (Containers/UIAlertController.swift)
lays its `MenuPanelView` out: 250 wide under its source (above it when there is no room), 6 from
it and at least 10 from the window's edges, left-aligned with the source when that fits, else
right-aligned; an edit menu's bar centred over its point. The card is a (244, 244, 244) glass
panel ((44, 44, 46) dark) with 26 pt corners and a soft shadow, no dim: a 32 pt header with the
menu's title (13 pt, secondary), 44 pt rows with a 17 pt title 16 in (the image, a system
symbol, 20 pt at the trailing edge; a subtitle in 12 pt under the title), 0.5 pt separators 16
in between rows, an 8 pt band between inline sections, check marks (`on`) and dashes (`mixed`)
before a title, red destructive titles, disabled ones at 30 %, submenu rows with a chevron that
open the submenu in place behind a back row (a chevron and the parent's title). A press
highlights its row (black 8 %); lifting on a row runs the action after the menu closes; a tap
outside closes the menu (`presentationControllerDidDismiss`-style callbacks do not apply).
The presenting control's highlight ends when a long press opens the menu, and its primary
action does not fire.

## Not yet covered

The real iOS 26 card (unmeasured: the harness cannot open menus), the open and close animations,
`UIMenu.preferredElementSize` (small and medium rows of icons), palettes, keyboard navigation of
menus, a context menu's preview tap, `UITargetedPreview` for context menus, edit menus for text
views (their own selection menus are the host's).
