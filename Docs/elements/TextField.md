# TextField, SecureField

Apple docs: [TextField](https://developer.apple.com/documentation/swiftui/textfield),
[SecureField](https://developer.apple.com/documentation/swiftui/securefield),
[TextFieldStyle](https://developer.apple.com/documentation/swiftui/textfieldstyle),
[onSubmit(_:)](https://developer.apple.com/documentation/swiftui/view/onsubmit(_:)).

## API surface

| API | Notes |
|---|---|
| `TextField(_ titleKey:text:prompt:)`, `TextField(_ title: S, text:prompt:)`, `TextField(text:prompt:label:)` | implemented; the prompt, else the label's text, is the placeholder (macOS shows no separate label outside `Form`) |
| `TextField(_:text:prompt:axis:)`, `TextField(text:prompt:axis:label:)` | implemented (2026-10-03): `.vertical` wraps the text at the field's width and grows a line at a time; `lineLimit` caps the lines, `lineLimit(_:reservesSpace:)` and a range reserve them; the host's element becomes a `<textarea>` whose Return still submits |
| `TextField(_:value:format:prompt:)`, `TextField(value:format:prompt:label:)`, `TextField(_:value:formatter:prompt:)`, `TextField(value:formatter:prompt:label:)` | implemented: the value's text is shown; typing is held in the field and parsed into the value on Return or when focus leaves (text that does not parse restores the value's text); `.number`, `.percent`, `.currency(code:)` and `NumberFormatter` on wasm come from `WebFoundation` (en_US, held to Foundation by `NumberFormattingTests`) |
| `TextField(_:text:onEditingChanged:onCommit:)` and the single-callback forms, the `formatter:` + callbacks form | implemented: `onEditingChanged` runs with focus coming and going, `onCommit` on Return |
| `SecureField(_:text:prompt:)`, `SecureField(text:prompt:label:)` | implemented (bullets painted, `<input type=password>` in the browser) |
| `TextFieldStyle`: `.automatic`, `.roundedBorder`, `.squareBorder`, `.plain`; `textFieldStyle(_:)` | implemented; custom styles are not (Apple's protocol is closed) |
| `onSubmit(_:)`, `onSubmit(of:_:)`, `SubmitTriggers` | implemented (Return in the field; triggers ignored) |
| `autocorrectionDisabled(_:)`, environment `autocorrectionDisabled` | implemented: the element's `autocorrect` and `spellcheck` |
| `labelsHidden()`, `disabled(_:)` | implemented (hidden labels change nothing on macOS; disabled dims and blocks focus) |
| `submitLabel(_:)`, `SubmitLabel` | implemented: the element's `enterkeyhint` (`done`, `go`, `send`, `join`, `route`, `search`, `next`; `return` and `continue` leave it unset) |
| `textContentType(_:)`, `UITextContentType` (shared with UIKitWeb) | implemented: the element's `autocomplete` token (`email`, `username`, `current-password`, `one-time-code`, `given-name`, …) |
| `keyboardType(_:)`, `UIKeyboardType` | implemented: the element's `inputmode` (`numeric`, `decimal`, `tel`, `email`, `url`, `search`) and `type` (`email`, `url`, `tel`, `search`) |
| `textInputAutocapitalization(_:)`, `TextInputAutocapitalization` | implemented: the element's `autocapitalize` (`off`, `words`, `sentences`, `characters`) |
| `@FocusState`, `focused(_:)` | implemented (Docs/elements/Focus.md) |

## Behaviour

`TextField` is a composite: its body reads the `TextFieldStyle` environment and makes a
`_TextFieldCore`, the primitive that lays out, paints and owns focus. Editing lives in the
host: the canvas host keeps a real transparent `<input>` (`type=password` for secure fields; a
`<textarea>` for a vertical field) over the field's text, with the same font and line height,
so typing, IME composition and copy/paste are the browser's; every `input` event pushes the
value into the binding through `Runtime.textField(_:didChange:)`, Return calls
`textFieldDidSubmit` (a text field submits on Return even as a textarea; Shift-Return keeps
the newline), focus and blur call `textField(_:focused:)`, and `select`, key and pointer
events report the selection through `textField(_:selectionStart:end:)`.

The caret and the selection are painted by the node (`TextInputInfo.paintsCaret`), so the
native host and the browser draw the same frame: the element's own caret is transparent and
its `::selection` highlight invisible (a style rule the host installs). The caret is a
`textCaretWidth` bar (1 pt in the text colour on macOS, 2 pt in the accent on iOS) the line's
height at the selection's start; a range fills `textSelectionColor` behind the lines it spans.
Both are unverified against the platforms (the goldens never focus a field).

A value field (`format:` or `formatter:`) keeps what the user types in an edit buffer: the
binding's text is only parsed when they press Return or focus leaves, so a half-typed number
does not snap back; text that fails to parse leaves the value alone and the field shows the
value's text again. A vertical field counts its lines from the wrapped layout's height (the
recorded text engine returns one line carrying the wrapped height) and lays them out at the
line pitch (16 on macOS; 26 on iOS, the body line plus the plain style's extra). A press on the canvas focuses the field (`focusedTextFieldIdentifier`)
and the host focuses the element. The semantics tree carries a `textField` node whose
`TextInputInfo` (text, placeholder, secure, text rect, font, enabled) the host mirrors.

## Measured (macOS 26.2, `textfield/basic`, `textfield/styles`, `textfield/steps`, 2026-09-02)

| Property | Value | Probe |
|---|---|---|
| Rounded-border field (default) | 24 pt tall, flexible width (fills 320, two share 156 each, `frame(width:)` honoured) | `empty`, `halves`, `narrow` |
| Text line | 6 pt from the leading edge, 16 pt line on a 17 pt baseline (4 pt above and below): a bordered button and a text label in a baseline row share it | `rowLabel` (y + 4), `rowButton` |
| Bezel | white fill with 5 pt corners (approximate, from the ramp), a 1 pt border of black at 23/255 drawn *outside* the frame | pixels of `empty`, `narrow` |
| `.squareBorder` | identical to the rounded style on macOS 26 | `square` |
| `.plain` | the bare text line: 16 tall, text at x = 0, no bezel | `plain`, `plainEmpty` |
| Placeholder | the title in the secondary colour (black at 50 %), same position | `empty`, `secureEmpty` |
| Text colour | primary (black at 85 %) | `filled` |
| Secure bullets | 5.5 pt discs, 8 pt pitch, the first 7.5 pt in, centred 5 pt above the baseline; the placeholder shows when empty | `secureFilled` |
| Disabled | fill white at 192/255, text at about 30 % (approximate), border unchanged | `disabled` |
| Model changes | the field repaints and its neighbours re-lay out (`On`/`Off` echo) | `textfield/steps` |
| Ideal width | text or placeholder width plus the insets (assumed; no golden) | — |

## Measured (macOS 26.6, `textfield/vertical`, `textfield/formatted`, plain style, 2026-10-03; iOS 26, `ios/textfield/vertical`)

The plain style keeps these goldens off the rounded bezel, whose metrics moved on macOS 26.6
(21 pt tall) while the older goldens stay at 26.2.

| Property | Value | Probe |
|---|---|---|
| Vertical field, wrapped | two 16 pt lines in 200 pt: 32 tall; one line stays 16 | `wrapped`, `short`, `single` |
| `lineLimit(3, reservesSpace: true)` on an empty field | three lines, 48 | `reserved` |
| `lineLimit(2)` on three lines of text | two lines, 32 (no ellipsis: the text is clipped) | `capped` |
| `lineLimit(2...4)` | the text's two lines, 32 | `ranged` |
| Ideal width (`fixedSize`) | the shown text's unrounded width plus 4: "Hello" 34.95, "1,234" 37.3, "$12.50" 45.09, the placeholder "Placeholder" 75.56 when empty (ours rounds widths to the half point: within 2) | `fixedText`, `int`, `currency`, `fixedEmpty` |
| Formatted text | `.number` 1,234 and 3.14159, `.percent` 25%, `.currency(code: "USD")` $12.50, `NumberFormatter()` 42 | `int`, `double`, `percent`, `currency`, `formatter` |
| iPhone, plain two lines | 52 (two 26 pt lines); rounded 60 (the lines plus 8); a rounded single line 34 | `plain`, `rounded`, `short` |
| iPhone, rounded empty field with three reserved lines | 84.287: two 26 pt lines, the placeholder's own 24.287 and 8 (a rule not yet pinned down; the probe is approximate) | `reserved` |

## Verification (2026-09-02; forms 2026-10-03)

Tier A: 6 fixtures exact (`textfield/steps` steps included; `textfield/formatted` within 2 pt
for the ideal widths, `ios/textfield/vertical` without its reserved field). Tier B, frames
exact: Chromium ≤ 0.53 % pixels on the older fixtures, the forms ≤ 2.3 % (glyph edges of the
wrapped lines), WebKit ≤ 0.39 %, Firefox ≤ 0.66 %. Tier C ≤ 2.26 %. `TextFieldFormsTests`
cover the value field's commit on Return and blur, the callbacks, the caret with and without a
selection, and the keyboard attributes reaching the input info. `Playwright/textfield-probe.mjs` types
into the overlay input in headless Chromium: the binding, the echo text, the focus ring and
blur on Tab all follow. wasm js tests pass.

## Not yet covered

Focused look (the ring is an accent stroke, unverified), the caret and selection colours and
widths (unverified), the rounded bezel on macOS 26.6 (21 pt; the goldens stay at 26.2),
`lineLimit` on a horizontal field, a vertical field's ellipsis past the limit (clipped here),
a formatted field's native typing (the macOS host types at the end only), keyboard focus
order between fields and buttons, text scrolling inside a narrow field (text is clipped), IME
candidate window placement (unverified by hand), the iPhone reserved-lines rule.
