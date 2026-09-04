# Link

Apple docs: [Link](https://developer.apple.com/documentation/swiftui/link),
[OpenURLAction](https://developer.apple.com/documentation/swiftui/openurlaction).

## API surface

| API | Notes |
|---|---|
| `Link(_ title, destination:)`, `Link(destination:label:)` | implemented |
| `EnvironmentValues.openURL`, `OpenURLAction` (custom handlers, `.handled`, `.discarded`, `.systemAction`, `.systemAction(url)`), `callAsFunction(_:)`, `callAsFunction(_:completion:)` | implemented; hosts install `OpenURLAction.systemHandler` (the browser opens a new tab, the native host asks `NSWorkspace`) |
| `ShareLink` | missing |

## Behaviour

A link is a plain-style `Button` whose label is coloured with the link blue (0, 104, 218; half
opacity when disabled) and snapped to the pixel grid like other controls' labels; a press asks
the `openURL` action, which runs a custom handler from the environment first and otherwise the
host's opener. The font is the environment's (a title link is 33 tall).

## Measured (macOS 26.2, `link/basic`, 2026-09-04)

| Property | Value | Probe |
|---|---|---|
| Size | the label's: "Apple" 35 × 16, a title link 54 × 33, a `Label` link 90.5 × 24 | `titled`, `large`, `custom` |
| Colour | 0, 104, 218 (not the accent 0, 136, 255); disabled 127, 179, 236 = half opacity over white | pixels of `titled`, `disabled` |
| Label snapping | the label sits at the whole pixel (115 for a link at 114.75) | `customLabel` |
| In a row | 8 from a text, like any text | `row`, `inline` |

## Verification (2026-09-04)

Tier A: `link/basic` exact. Tier B: Chromium 0.43 %, WebKit 0.08 %, Firefox 0.44 %; Tier C 0.08 %. `LinkTests` cover the colour,
the disabled look, the system opener, custom handlers and redirects.

## Not yet covered

Hover looks (a pointing hand), underline on hover, `ShareLink`, `Link` inside `Text` markdown.
