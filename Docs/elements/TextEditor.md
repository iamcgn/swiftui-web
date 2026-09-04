# TextEditor

Apple docs: [TextEditor](https://developer.apple.com/documentation/swiftui/texteditor),
[TextEditorStyle](https://developer.apple.com/documentation/swiftui/texteditorstyle),
[scrollContentBackground(_:)](https://developer.apple.com/documentation/swiftui/view/scrollcontentbackground(_:)).

## API surface

| API | Notes |
|---|---|
| `TextEditor(text:)` | implemented |
| `TextEditorStyle` (`.automatic`, `.plain`), `textEditorStyle(_:)` | implemented: the plain style paints no background; custom styles are not (the protocol exposes only that flag) |
| `scrollContentBackground(_:)` | implemented for the editor (`.hidden` removes its white background); lists and scroll views ignore it |
| `font`, `foregroundColor`, `lineSpacing`, `disabled` | honoured (a disabled editor keeps its black text, as on macOS) |
| Editing | the host's multi-line input: a transparent `<textarea>` over the text in the browser (typing, IME, caret, selection are the browser's), typing at the end of the text natively (Return inserts a newline) |
| `findNavigator`, `findDisabled`, `replaceDisabled`, text selection binding, `lineLimit` on editors, `writingToolsBehavior`, scrolling of long content | missing |

## Behaviour

`TextEditorNode` fills whatever it is proposed (like a scroll view; 100 × 100 unproposed,
unverified) and declares the default 8 pt stack spacing. It paints a white background unless
the plain style or `scrollContentBackground(.hidden)` removes it, then the text laid out at the
width minus 5 pt each side, clipped to its bounds: every line at the text view's pitch (the
font size × 0.955 rounded: 12 for 13 pt) plus the line spacing, the first baseline at the cap
height below the top edge plus a gap that grows with the font size (measured at 13 and 22 pt).
The text is pure black (not the primary 85 %) unless a `foregroundColor` is set. A press focuses
the editor through the runtime's text-field focus; its semantics carry a multi-line
`TextInputInfo` (line height and first baseline) for the hosts.

## Measured (macOS 26.2, `texteditor/basic`, `texteditor/sizing`, `texteditor/styles`, `texteditor/steps`, 2026-09-04)

| Property | Value | Probe |
|---|---|---|
| Frame | fills its proposal: 280 wide in a padded stack, 320 × 148 between texts at the default 8 pt spacing, 280 next to a 32 pt text in a row; `frame(width:height:)` honoured | `lines`, `fill`, `left`, `narrow` |
| Text origin | 5 pt in; the 13 pt text's cap top on the top edge (baseline at +9.16) | pixels of `lines`, `fill` |
| Line pitch | 12 for 13 pt ("World" 12 under "Hello"); `lineSpacing(10)` makes 22 | `lines`, `spaced` |
| Title font | `.font(.title)` (22 pt): the cap top 8.5 down | `title` |
| Colours | text black (0, 0, 0); `foregroundColor(.red)` honoured; disabled unchanged; no border or visible background against white | `red`, `disabled`, pixels |
| Wrapping | NSTextView keeps "…several lines" (265 pt of ink) on the first line where SwiftUI's `Text` at the same 270 pt wraps "lines": its letters sit tighter and its spaces wider than SF's SwiftUI rendering (not reproduced; `texteditor/basic` is approximate) | `wrapping` |
| Model changes | the text repaints; the echo text re-lays out | `texteditor/steps` |

## Verification (2026-09-04)

Tier A: all 4 fixtures exact, the `texteditor/steps` steps included. Tier B, frames exact in
Chromium and WebKit; Firefox's hinting shifts "Above" in `texteditor/sizing` (the known class).
Pixels: `basic` 2.6 % in every browser (the wrapped paragraph, listed approximate), `sizing`
≤ 0.45 %, `styles` ≤ 1.02 %, `steps` ≤ 0.76 %. Tier C: 2.60 / 0.35 / 0.97 / ≤ 0.68 %.
`TextEditorTests` cover sizing and spacing, the text's inset, baseline and pitch, the
background and its removal, colours and line spacing, focus and the host's input and submit.

## Not yet covered

NSTextView's letter and word spacing, scrolling long content, selection and caret positions
inside the text natively, find and replace, the unverified ideal size, the top gap for fonts
other than 13 and 22 pt.
