# TextField, SecureField

Apple docs: [TextField](https://developer.apple.com/documentation/swiftui/textfield),
[SecureField](https://developer.apple.com/documentation/swiftui/securefield),
[TextFieldStyle](https://developer.apple.com/documentation/swiftui/textfieldstyle),
[onSubmit(_:)](https://developer.apple.com/documentation/swiftui/view/onsubmit(_:)).

## API surface

| API | Notes |
|---|---|
| `TextField(_ titleKey:text:prompt:)`, `TextField(_ title: S, text:prompt:)`, `TextField(text:prompt:label:)` | implemented; the prompt, else the label's text, is the placeholder (macOS shows no separate label outside `Form`) |
| `TextField(_:text:axis:)` | stub: single line |
| `TextField(_:value:format:)`, `TextField(_:value:formatter:)`, `onEditingChanged`/`onCommit` forms | missing |
| `SecureField(_:text:prompt:)`, `SecureField(text:prompt:label:)` | implemented (bullets painted, `<input type=password>` in the browser) |
| `TextFieldStyle`: `.automatic`, `.roundedBorder`, `.squareBorder`, `.plain`; `textFieldStyle(_:)` | implemented; custom styles are not (Apple's protocol is closed) |
| `onSubmit(_:)`, `onSubmit(of:_:)`, `SubmitTriggers` | implemented (Return in the field; triggers ignored) |
| `autocorrectionDisabled(_:)` | stored only |
| `labelsHidden()`, `disabled(_:)` | implemented (hidden labels change nothing on macOS; disabled dims and blocks focus) |
| `@FocusState`, `focused(_:)`, `submitLabel`, `textContentType`, `keyboardType`, `textInputAutocapitalization`, `lineLimit` for multi-line fields | missing |

## Behaviour

`TextField` is a composite: its body reads the `TextFieldStyle` environment and makes a
`_TextFieldCore`, the primitive that lays out, paints and owns focus. Editing lives in the
host: the canvas host keeps a real transparent `<input>` (`type=password` for secure fields) over
the field's text line, with the same font and line height, so typing, IME composition, the caret,
selection and copy/paste are the browser's; every `input` event pushes the value into the binding
through `Runtime.textField(_:didChange:)`, Return calls `textFieldDidSubmit`, focus and blur call
`textField(_:focused:)`. A press on the canvas focuses the field (`focusedTextFieldIdentifier`)
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

## Verification (2026-09-02)

Tier A: 3 fixtures exact (`textfield/steps` steps included). Tier B, frames exact: Chromium
≤ 0.53 % pixels, WebKit ≤ 0.39 %, Firefox ≤ 0.66 %. `Playwright/textfield-probe.mjs` types
into the overlay input in headless Chromium: the binding, the echo text, the focus ring and
blur on Tab all follow. wasm js tests pass.

## Not yet covered

Focused look (the ring is an accent stroke, unverified), painted caret and selection (the
browser's for now, so they are not in the display list), multi-line fields, formatted values,
`@FocusState`/programmatic focus, keyboard focus order between fields and buttons, `Form`
labels, text scrolling inside a narrow field (text is clipped), `submitLabel`, IME candidate
window placement (unverified by hand).
