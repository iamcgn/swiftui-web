# Dark appearance: colorScheme, preferredColorScheme, system colours and control inks

Apple docs: [ColorScheme](https://developer.apple.com/documentation/swiftui/colorscheme),
[colorScheme](https://developer.apple.com/documentation/swiftui/environmentvalues/colorscheme),
[preferredColorScheme(_:)](https://developer.apple.com/documentation/swiftui/view/preferredcolorscheme(_:)).

## API surface

| API | Notes |
|---|---|
| `ColorScheme`, `EnvironmentValues.colorScheme`, `.environment(\.colorScheme, …)` | implemented: system colours, label colours, control inks, list and field backgrounds and asset variants follow the environment |
| `preferredColorScheme(_:)` | implemented: applies to the whole window (the root environment), `nil` returns to the system appearance |
| The system appearance | the browser host follows `prefers-color-scheme` (and its changes); the native host follows the window's effective appearance |
| `colorSchemeContrast`, `ColorSchemeContrast`, `preferredColorScheme` per presentation | missing |

## Behaviour

`PlatformProfile.resolve(_:scheme:)` has a table per appearance (`ColorTable.swift`); `Color`
resolves through `environment.colorScheme`. Controls draw their fills, tracks, separators and
marks with `environment._ink(alpha)` (the `controlInk` system colour: black in light, white in
dark, at the same alphas, which is what Apple's inactive-window greys measure to); text fields,
lists, tables and date pickers fill with `controlBackground`; switch and slider knobs with `knob`;
presentations with `windowBackground`.

`Runtime.hostColorScheme` is the system appearance a host reports (seeded from the initial
environment, so fixtures and tests choose theirs); `preferredColorScheme` records the tree's
preference on the runtime; `applyColorScheme` (in `layout`) moves the root environment to the
effective scheme and re-applies the root view (`RootNode.reapply`), so every node resolves its
colours again. `Runtime.paintsWindowBackground` (hosts set it) makes `render` start with the
window background; goldens are transparent, so fixtures leave it off.

The harness gives a fixture with `.colorScheme(.dark)` a `darkAqua` window (AppKit-backed
controls follow the window, not the environment) and the fixture catalog's dark variants
(`FixtureAssets.appearance`).

## Measured (macOS 26.2, `dark/*`, 2026-09-04)

| Colour | Light | Dark | Fixture |
|---|---|---|---|
| red, orange, yellow, green | 255 56 60 · 255 141 40 · 255 204 0 · 52 199 89 | 255 66 69 · 255 146 48 · 255 214 0 · 48 209 88 | `dark/system-colors` |
| mint, teal, cyan, blue | 0 200 179 · 0 195 208 · 0 192 232 · 0 136 255 | 0 218 195 · 0 210 224 · 60 211 254 · 0 145 255 | |
| indigo, purple, pink, brown, gray | 97 85 245 · 203 48 224 · 255 45 85 · 172 127 94 · 142 142 147 | 109 124 255 · 219 52 242 · 255 55 95 · 183 138 102 · 152 152 157 | |
| primary, secondary | black 216/255, black 127/255 | white 216/255, white 140/255 | `dark/text` |
| tertiary, quaternary (`fill(.tertiary)`) | — | white 63/255, white 25/255 (drawn as primary × 0.35 and × 0.25, within a channel's tolerance) | `dark/system-colors` |
| accentColor | 0 136 255 | 0 122 255 (not the dark blue) | |
| link | 0 104 218 | 65 156 255 | `dark/text` |
| window / control background | white (`NSColor.windowBackgroundColor` on 26.2) | 30 30 30 | `dark/list`, `dark/controls` text fields |
| control inks | black at 19–50/255 (buttons 19, checkbox 25/36, switch 25/36, pop-up 20, segmented 20/50, stepper 20, slider 25/58, progress 15, group box 8) | white at the same alphas | `dark/controls` |
| progress fill | black 85/255 | opaque 170 170 170 | |
| switch and slider knobs | white | white 222/255 | |
| text field border | black 23/255 | 128 128 128 at 22/255 | |
| placeholder, disabled field text | secondary, tertiary | secondary, tertiary (154 and 86 over the 30 fill) | |

## Verification (2026-09-04)

Tier A: 4 fixtures exact. Tier C: `dark/system-colors` and `dark/text` 0.00 %, `dark/list`
0.02 %, `dark/controls` 0.33 %. `DarkModeTests` cover the tables, the ink swap, field and text
colours, `preferredColorScheme` on and off, a host scheme change re-resolving a mounted tree and
the painted window background.

## Not yet covered

Sidebar and grouped-form backgrounds, popover and menu panels, the colour picker well, gauge and
date picker chrome in dark (unverified: they use the ink and background tables), the focus ring,
`colorSchemeContrast`, per-presentation schemes, the gallery page chrome.
