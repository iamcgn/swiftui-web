#!/usr/bin/env python3
"""Renders the progress outputs from the tracking data (decision 0016): Docs/TODO.md from
Docs/todo.json today; the progress page's data blob once Examples/Progress exists. Validates the
data first (unique ids, known enum values, referenced paths that exist) so a bad edit fails here
and not on the page. `--check` renders to memory and exits 1 when a committed output is stale
(CI runs it)."""
import json, pathlib, sys
from collections import Counter, OrderedDict

root = pathlib.Path(__file__).resolve().parent.parent
todo_path = root / "Docs/todo.json"
todo_md = root / "Docs/TODO.md"

FRAMEWORKS = ["Site", "Interop", "SwiftUI", "UIKit", "Platform"]
PRIORITIES = OrderedDict(next="Next (Phase 8, in order)", soon="Soon (the gap sweep)",
                         later="Later (needs a decision, a subsystem or a platform)")
STATUSES = ["planned", "in-progress", "done", "wontfix"]
KINDS = ["missing", "accepted", "approximate", "verify", "infra"]
STATUS_MARK = {"planned": "☐", "in-progress": "◐", "done": "☑", "wontfix": "✕"}


def fail(message):
    print(f"gen-progress: {message}", file=sys.stderr)
    sys.exit(1)


def load():
    data = json.loads(todo_path.read_text())
    items = data["items"]
    ids = Counter(item["id"] for item in items)
    duplicates = [i for i, n in ids.items() if n > 1]
    if duplicates:
        fail(f"duplicate ids: {duplicates}")
    for item in items:
        for key in ("id", "framework", "area", "title", "detail", "kind", "priority", "status"):
            if key not in item:
                fail(f"{item.get('id', '?')}: missing `{key}`")
        if item["framework"] not in FRAMEWORKS:
            fail(f"{item['id']}: unknown framework {item['framework']!r}")
        if item["priority"] not in PRIORITIES:
            fail(f"{item['id']}: unknown priority {item['priority']!r}")
        if item["status"] not in STATUSES:
            fail(f"{item['id']}: unknown status {item['status']!r}")
        if item["kind"] not in KINDS:
            fail(f"{item['id']}: unknown kind {item['kind']!r}")
        if item["status"] == "done" and not item.get("done"):
            fail(f"{item['id']}: done items carry the date in `done`")
        for ref in item.get("refs", []):
            if not (root / ref).exists():
                fail(f"{item['id']}: ref {ref} does not exist")
    return data


def render_todo(data):
    items = data["items"]
    open_items = [i for i in items if i["status"] in ("planned", "in-progress")]
    done_items = sorted((i for i in items if i["status"] == "done"), key=lambda i: i["done"], reverse=True)
    wontfix = [i for i in items if i["status"] == "wontfix"]
    out = ["# What is next", "",
           "Generated from `Docs/todo.json` by `scripts/gen-progress.py`; edit the JSON, not this file. "
           "The same data is shown on the progress page. Priorities: **next** is Phase 8 of "
           "`Docs/ROADMAP.md` in order, **soon** the gap sweep after it (what ordinary apps hit), "
           "**later** what needs a decision, a subsystem or a platform that does not exist yet. "
           "Kinds: *missing* (no API), *accepted* (compiles, no behaviour), *approximate* (behaves, pixels "
           "or motion differ), *verify* (behaves, never measured against Apple), *infra* (tooling, docs, site). "
           "Marks: ☐ planned, ◐ in progress, ☑ done, ✕ a documented non-goal.", ""]
    counts = Counter(i["framework"] for i in open_items)
    out += ["| Framework | Open items | next | soon | later |", "|---|---|---|---|---|"]
    for framework in FRAMEWORKS:
        rows = [i for i in open_items if i["framework"] == framework]
        if not rows:
            continue
        by = Counter(i["priority"] for i in rows)
        out.append(f"| {framework} | {len(rows)} | {by['next']} | {by['soon']} | {by['later']} |")
    out.append(f"| **All** | **{len(open_items)}** | {sum(1 for i in open_items if i['priority']=='next')} | "
               f"{sum(1 for i in open_items if i['priority']=='soon')} | {sum(1 for i in open_items if i['priority']=='later')} |")
    out.append("")
    for priority, heading in PRIORITIES.items():
        out += [f"## {heading}", ""]
        for framework in FRAMEWORKS:
            rows = [i for i in open_items if i["priority"] == priority and i["framework"] == framework]
            if not rows:
                continue
            out += [f"### {framework}", ""]
            for item in rows:
                refs = ", ".join(f"[{pathlib.Path(r).name}]({r})" for r in item.get("refs", []))
                out.append(f"- {STATUS_MARK[item['status']]} **{item['title']}** `{item['id']}` · {item['area']} · {item['kind']}  ")
                out.append(f"  {item['detail']}" + (f" ({refs})" if refs else ""))
            out.append("")
    if done_items:
        out += ["## Landed", ""]
        for item in done_items:
            out.append(f"- ☑ {item['done']} **{item['title']}** `{item['id']}` · {item['framework']} · {item['area']}")
        out.append("")
    if wontfix:
        out += ["## Non-goals", ""]
        for item in wontfix:
            out.append(f"- ✕ **{item['title']}** `{item['id']}` · {item['framework']}: {item['detail']}")
        out.append("")
    return "\n".join(out)


def main():
    check = "--check" in sys.argv
    data = load()
    outputs = {todo_md: render_todo(data)}
    stale = [path for path, text in outputs.items() if not path.exists() or path.read_text() != text]
    if check:
        if stale:
            fail("stale outputs, run scripts/gen-progress.py: " + ", ".join(str(p.relative_to(root)) for p in stale))
        print("gen-progress: outputs current")
        return
    for path, text in outputs.items():
        path.write_text(text)
        print(f"wrote {path.relative_to(root)}")


if __name__ == "__main__":
    main()
