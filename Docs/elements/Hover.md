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
| `help(_:)` for `Text`, `LocalizedStringKey` and strings | implemented as a painted tooltip after a 1 s rest; not yet exposed to assistive technology |
| `pointerStyle(_:)`, `PointerStyle` (`default`, `link`, `grabIdle`, `grabActive`, `horizontalText`, `verticalText`, `rectSelection`, `zoomIn`, `zoomOut`, `columnResize`, `rowResize`, `frameResize`) | implemented as the host's cursor (`HorizontalDirection`, `VerticalDirection`, `FrameResizePosition`, `FrameResizeDirection` added); image pointers are not offered |
| Hover effects on controls (`hoverEffect`, hovered looks) | missing; macOS controls do not change on hover |

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
  tooltip panel, which lives in its own window and cannot be captured.
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

`help` in the accessibility tree (a `title`/description on the overlay element), hover through
presentations and clipped scroll content, control hover looks, `hoverEffect`, image pointers.
