#!/usr/bin/env python3
"""Renders Docs/support-matrix.md from Docs/support.json (SkipUI-style status per API)."""
import json, pathlib
root = pathlib.Path(__file__).resolve().parent.parent
data = json.loads((root / "Docs/support.json").read_text())
icons = {"full": "✅", "partial": "🟢", "approximate": "🟡", "stub": "🟠", "missing": "❌"}
out = ["# SwiftUI support matrix", "", "Generated from `Docs/support.json` by `scripts/support-matrix.py`. Anything not listed is not implemented.", "",
       "| Status | Meaning |", "|---|---|",
       "| ✅ full | API complete, fixtures pass exact layout and pixel checks |",
       "| 🟢 partial | Common usage works; listed gaps |",
       "| 🟡 approximate | Works but rendering knowingly differs (e.g. SF Symbols substitute) |",
       "| 🟠 stub | Compiles, no behaviour |",
       "| ❌ missing | Not implemented |", ""]
for section in data["sections"]:
    out += [f"## {section['title']}", "", "| API | Status | Notes | Fixtures |", "|---|---|---|---|"]
    for e in section["entries"]:
        out.append(f"| `{e['api']}` | {icons[e['status']]} {e['status']} | {e.get('notes','')} | {', '.join(e.get('fixtures', []))} |")
    out.append("")
(root / "Docs/support-matrix.md").write_text("\n".join(out))
print("wrote Docs/support-matrix.md")
