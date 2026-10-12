# onHover, onContinuousHover, help, pointerStyle

Apple docs: [onHover(perform:)](https://developer.apple.com/documentation/swiftui/view/onhover(perform:)),
[onContinuousHover(coordinateSpace:perform:)](https://developer.apple.com/documentation/swiftui/view/oncontinuoushover(coordinatespace:perform:)),
[help(_:)](https://developer.apple.com/documentation/swiftui/view/help(_:)-9swe4),
[pointerStyle(_:)](https://developer.apple.com/documentation/swiftui/view/pointerstyle(_:)).

## API surface

| API | Notes |
|---|---|
| `onHover(perform:)` | implemented |
| `onContinuousHover(coordinateSpace:perform:)`, `HoverPhase` | implemented for `.local` and `.global` (a named space reports local points) |
| `help(_:)` for `Text`, `LocalizedStringKey` and strings | implemented as a painted tooltip after a 1 s rest; the text is the element's description for assistive technology (the overlay's `title`, 2026-10-04) |
| `pointerStyle(_:)`, `PointerStyle` (`default`, `link`, `grabIdle`, `grabActive`, `horizontalText`, `verticalText`, `rectSelection`, `zoomIn`, `zoomOut`, `columnResize`, `rowResize`, `frameResize`) | implemented as the host's cursor (`HorizontalDirection`, `VerticalDirection`, `FrameResizePosition`, `FrameResizeDirection` added); image pointers are not offered |
| `hoverEffect(_:)`, `hoverEffect(_:isEnabled:)`, `HoverEffect` (`automatic`, `highlight`, `lift`), `hoverEffectDisabled(_:)`, `defaultHoverEffect(_:)` | implemented 2026-10-11 on the iOS profile (iPadOS pointer effects, approximate: the highlight a translucent rounded rect 4 pt around the view at 10 % ink with the content scaled 1.03, the lift the content at 1.15 under a 20 % shadow of radius 12 offset 8, eased over 0.2 s; `automatic` is the highlight unless `defaultHoverEffect` says otherwise); a no-op on macOS, where SwiftUI has no hover effects |
| Hovered looks of macOS controls | none, as AppKit's: push buttons, checkboxes, pop-ups, switches and sliders track no hover (`NSButton.showsBorderOnlyWhileMouseInside` defaults to false; read 2026-10-11); toolbar items highlight on hover in AppKit, which the painted toolbar does not reproduce |

## Behaviour

Hosts forward every pointer move, not only presses: the browser host's `pointermove` and
`pointerleave` (`Runtime.pointerMoved`, `Runtime.pointerLeft`), the native host through an
`NSTrackingArea` (`mouseMoved`, `mouseExited`). `Runtime.updateHover` finds the `_HoverTracking`
nodes whose frame (in window space, memoised per layout) contains the point, tells the ones the
pointer left `hoverChanged(inside: false)`, and the ones it is over `hoverChanged(inside: true, at:)`
with the point in the node's space — all of them, front to back, as SwiftUI reports a hover to
every view under the pointer. Clipping by scroll views and presentations is not considered.

- `HoverNode` (`onHover`) calls the action once on entry and once on exit; leaving the window
  exits too; an unmounted node is forgotten.
- `ContinuousHoverNode` reports `.active(point)` on every move inside (local, or window
  coordinates for `.global`) and `.ended` once.
- `HelpNode` asks the runtime for a tooltip on entry and cancels it on exit. `Runtime.tooltip`
  keeps the text, the pointer position and the request time on the animation clock;
  `needsFrame` stays true while it is pending so hosts keep ticking, `advanceAnimations` shows it
  after `Runtime.tooltipDelay` (1 s) and `render` paints it last: an 11 pt label with 6 × 3 pt
  padding in a 4 pt rounded panel (light 246 grey / dark 44 grey, a 15 % ink border and a soft
  shadow), 20 pt below the pointer and flipped above it near the bottom, kept inside the window.
  `Runtime.visibleTooltip` reports it for tests. The look is an approximation of the macOS
  tooltip panel, which lives in its own window and cannot be captured; what AppKit states is
  followed: the tooltip font is the 11 pt system font (`NSFont.toolTipsFont(ofSize: 0)`, read
  2026-10-11) and the delay 1 s. Measuring the panel's padding, corner and material needs a
  real pointer resting on a view (synthetic events do not reach tracking areas, and the
  harness does not move the user's cursor), so it stays approximate.
- `HoverEffectNode` (`hoverEffect`) paints the iPadOS pointer effects on the iOS profile while
  hovered (above), tweening its progress on the animation clock; nothing on macOS.
- A representable (`_PlatformViewHostNode`) tracks hover like an `onHover` view and forwards
  it to its UIKit tree, whose hovered pointer interaction contributes a style the same way
  (Docs/elements/Representable.md, 2026-09-18).
- `PointerStyleNode` contributes its style through `_PointerStyled`; `Runtime.pointerStyle` is
  the deepest hovered one. The browser host sets the canvas `cursor` to the CSS name; the native
  host sets the matching `NSCursor`.

## Verification (2026-09-04)

`hover/basic` (resting state): Tier A exact, Tier C 0.00 %, Tier B exact frames in three browsers.
`Playwright/hover-probe.mjs` (Chromium, served from Examples/Gallery on 8767) moves the mouse over
the fixture: `onHover` enters and leaves (the label and the entry count change), the continuous
hover reports a point and ends, `pointerStyle` sets `pointer`/`text` cursors and restores the
default, and the tooltip appears only after the delay and hides on leave. `HoverTests` cover the
same in the runtime, including global coordinates, the tooltip's placement and flipping, and the
deepest pointer style.

## Not yet covered

Hover through presentations and clipped scroll content, the tooltip panel's measured look and
the iPadOS effects' exact geometry (both need a real pointer), the toolbar items' hover
highlight, image pointers. `HoverTests.hoverEffectsOnTheIOSProfile` covers the effects.
