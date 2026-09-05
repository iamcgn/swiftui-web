# symbolEffect

Apple docs: [symbolEffect(_:options:isActive:)](https://developer.apple.com/documentation/swiftui/view/symboleffect(_:options:isactive:)),
[symbolEffect(_:options:value:)](https://developer.apple.com/documentation/swiftui/view/symboleffect(_:options:value:)),
[SymbolEffect](https://developer.apple.com/documentation/symbols/symboleffect).

## API surface

| API | Notes |
|---|---|
| `symbolEffect(_:options:isActive:)` with `.pulse`, `.scale`, `.variableColor`, `.bounce`, `.wiggle`, `.rotate`, `.breathe` | implemented (approximate motion) |
| `symbolEffect(_:options:value:)` with `.bounce`, `.pulse`, `.variableColor`, `.wiggle`, `.rotate`, `.breathe` | implemented: plays on every change of the value |
| `SymbolEffectOptions` (`repeating`, `nonRepeating`, `repeat(_:)`, `speed(_:)`) | implemented |
| `symbolEffectsRemoved(_:)` | implemented: drops the inherited effects |
| Effect variants (`.up`/`.down`, `.byLayer`/`.wholeSymbol`, `.iterative`/`.cumulative`, `.reversing`, `.clockwise`/`.counterClockwise`, `.left`/`.right`, `.plain`/`.pulse`, `.hideInactiveLayers`/`.dimInactiveLayers`) | accepted; the stand-in glyphs have one layer, so by-layer variants act on the whole symbol |
| `.appear`, `.disappear` (`transition(.symbolEffect(...))`), `.replace` (`contentTransition(.symbolEffect(...))`) | accepted; appear/disappear are the plain transition, replace a crossfade |

## Behaviour

Effects reach symbol images through the environment. An image node keeps the running effects
and subscribes to host frames, so the glyph repaints on the animation clock without layout:
the glyph is painted with a transform about its centre and an opacity group.

- **Indefinite** effects run while `isActive`: pulse dims to 0.4 and back once a second;
  scale settles at 1.2 (0.8 for `.down`) with a short ease; variableColor steps the opacity
  through three levels every 1.2 s (`.reversing` plays them back down); bounce lifts and
  scales every 0.5 s; wiggle swings 3 pt (or ±7° for the turning variants) every 0.6 s; rotate
  turns once a second; breathe swells 10 % and dims 20 % every 1.4 s. Deactivating or removing
  the modifier stops the effect at once.
- **Discrete** effects play when `value` changes (the first value does not play), for
  `options.repeat` plays (one by default, forever with `.repeating`), `speed` scaling the cycle.
- SF Symbols are Lucide stand-ins drawn as single paths; SwiftUI's layer-by-layer motion,
  variable-colour layers and real spring curves are not reproduced, only the whole-symbol
  motion with comparable timing.

`symboleffect/basic` (inactive and untriggered effects) is exact in Tier A/B/C; the motion is
covered by `SymbolEffectTests` on the headless clock.

## Open

- Layer-aware effects, spring timing matched to SwiftUI, `.appear`/`.disappear` motion,
  `.replace` variants beyond a crossfade.
