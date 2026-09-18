#!/usr/bin/env python3
"""Renders every tracking output from the two data files (decision 0016): Docs/TODO.md from
Docs/todo.json; Docs/support-matrix.md and the landing page's SupportData.swift from
Docs/support.json (the progress page's data blob joins once Examples/Progress exists). Validates
the data first (unique ids, known enum values, referenced paths that exist, a framework per
support section, a fixture or a reason per row that does something) so a bad edit fails here
and not on a page. `--check` renders to memory and exits 1 when a committed output is stale
(CI runs it). Edit the JSON, never the outputs."""
import fnmatch, json, pathlib, re, sys
from collections import Counter, OrderedDict

root = pathlib.Path(__file__).resolve().parent.parent
todo_path = root / "Docs/todo.json"
support_path = root / "Docs/support.json"
todo_md = root / "Docs/TODO.md"
matrix_md = root / "Docs/support-matrix.md"
landing_swift = root / "Examples/Landing/Sources/Landing/SupportData.swift"
progress_swift = root / "Examples/Progress/Sources/Progress/ProgressData.swift"
goldens = root / "Fixtures/Goldens"

FRAMEWORKS = ["Site", "Interop", "SwiftUI", "UIKit", "Platform"]
SUPPORT_FRAMEWORKS = ["SwiftUI", "UIKit", "Interop"]
PRIORITIES = OrderedDict(next="Next (Phase 8, in order)", soon="Soon (the gap sweep)",
                         later="Later (needs a decision, a subsystem or a platform)")
STATUSES = ["planned", "in-progress", "done", "wontfix"]
KINDS = ["missing", "accepted", "approximate", "verify", "infra"]
STATUS_MARK = {"planned": "☐", "in-progress": "◐", "done": "☑", "wontfix": "✕"}
SUPPORT_STATUSES = OrderedDict(full="✅", partial="🟢", approximate="🟡", stub="🟠", missing="❌")
SUPPORT_MEANING = OrderedDict(full="API complete, fixtures pass exact layout and pixel checks",
                              partial="Common usage works; listed gaps",
                              approximate="Works but rendering knowingly differs (e.g. SF Symbols substitute)",
                              stub="Compiles, no behaviour", missing="Not implemented")
# Fixture prefixes that have no golden by design: the gallery shows them, a probe or a test checks them.
GOLDENLESS = ("probe/", "demo/")


def fail(message):
    print(f"gen-progress: {message}", file=sys.stderr)
    sys.exit(1)


def fixture_names():
    """Every fixture name declared in the sources (SwiftUI and UIKit)."""
    names = set()
    for folder in (root / "Fixtures/Sources", root / "Fixtures/UIKit"):
        for path in folder.rglob("*.swift"):
            names.update(re.findall(r'(?:Fixture|renamed)\("([a-z0-9/-]+)"', path.read_text()))
    return names


def load_todo():
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


def load_support():
    data = json.loads(support_path.read_text())
    if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", data.get("generated", "")):
        fail("support.json needs a `generated` date (YYYY-MM-DD, the day of the last edit)")
    declared = fixture_names()
    for section in data["sections"]:
        if section.get("framework") not in SUPPORT_FRAMEWORKS:
            fail(f"section {section.get('title')!r}: `framework` must be one of {SUPPORT_FRAMEWORKS}")
        for entry in section["entries"]:
            if entry.get("status") not in SUPPORT_STATUSES:
                fail(f"{entry.get('api')!r}: unknown status {entry.get('status')!r}")
            fixtures = entry.get("fixtures", [])
            if entry["status"] != "missing" and not fixtures and not entry.get("noFixture"):
                fail(f"{entry['api']!r}: a row that does something names its fixtures or says in `noFixture` why none can exist")
            for fixture in fixtures:
                if "*" in fixture:
                    if not fnmatch.filter(declared, fixture):
                        fail(f"{entry['api']!r}: no fixture matches {fixture}")
                elif fixture.startswith(GOLDENLESS):
                    if fixture not in declared:
                        fail(f"{entry['api']!r}: fixture {fixture} is not declared in the sources")
                elif not (goldens / fixture).is_dir():
                    fail(f"{entry['api']!r}: fixture {fixture} has no golden under Fixtures/Goldens")
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


def render_matrix(data):
    counts = Counter(e["status"] for s in data["sections"] for e in s["entries"])
    per_framework = {fw: Counter(e["status"] for s in data["sections"] if s["framework"] == fw for e in s["entries"]) for fw in SUPPORT_FRAMEWORKS}
    out = ["# Support matrix", "",
           f"Generated from `Docs/support.json` (last edited {data['generated']}) by `scripts/gen-progress.py`; edit the JSON, not this file. "
           "Anything not listed is not implemented. Every row that does something names the fixtures that prove it "
           "(`Fixtures/Goldens/<name>`; `demo/` and `probe/` fixtures have no golden and are checked by a probe or a test), "
           "or says why none can exist.", "",
           "| Status | Meaning |", "|---|---|"]
    out += [f"| {icon} {status} | {SUPPORT_MEANING[status]} |" for status, icon in SUPPORT_STATUSES.items()]
    out += ["", "| Framework | Rows | " + " | ".join(SUPPORT_STATUSES) + " |", "|---|---|" + "---|" * len(SUPPORT_STATUSES)]
    for fw in SUPPORT_FRAMEWORKS:
        c = per_framework[fw]
        out.append(f"| {fw} | {sum(c.values())} | " + " | ".join(str(c[s]) for s in SUPPORT_STATUSES) + " |")
    out.append(f"| **All** | **{sum(counts.values())}** | " + " | ".join(str(counts[s]) for s in SUPPORT_STATUSES) + " |")
    out.append("")
    for fw in SUPPORT_FRAMEWORKS:
        for section in data["sections"]:
            if section["framework"] != fw:
                continue
            out += [f"## {section['title']}", "", "| API | Status | Notes | Fixtures |", "|---|---|---|---|"]
            for e in section["entries"]:
                proof = ", ".join(e.get("fixtures", [])) or (f"— {e['noFixture']}" if e.get("noFixture") else "")
                out.append(f"| `{e['api']}` | {SUPPORT_STATUSES[e['status']]} {e['status']} | {e.get('notes', '')} | {proof} |")
            out.append("")
    return "\n".join(out)


def render_landing(data):
    """The landing page's matrix as one string blob parsed on first use (large array literals
    compile into code on wasm and bloat the binary). The blob's shape is the page's contract."""
    lines = []
    for section in data["sections"]:
        lines.append("# " + section["title"])
        for e in section["entries"]:
            api = e["api"].replace("\t", " ").replace("\n", " ")
            notes = e.get("notes", "").replace("\t", " ").replace("\n", " ")
            lines.append("\t".join([e["status"], api, notes, str(len(e.get("fixtures", [])))]))
    blob = "\n".join(lines).replace("\\", "\\\\").replace('"""', '\\"\\"\\"')
    counts = Counter(e["status"] for s in data["sections"] for e in s["entries"])
    count_literal = ", ".join(f".{status}: {counts[status]}" for status in SUPPORT_STATUSES if counts[status])
    return f'''// Generated by scripts/gen-progress.py from Docs/support.json (last edited {data['generated']}); do not edit.
// The support matrix shown by the landing page. Kept as one string blob parsed on first use:
// large array literals compile into code on wasm and bloat the binary.

enum SupportStatus: String, CaseIterable {{
    case full, partial, approximate, stub, missing

    var title: String {{
        switch self {{
        case .full: return "Full"
        case .partial: return "Partial"
        case .approximate: return "Approximate"
        case .stub: return "Stub"
        case .missing: return "Missing"
        }}
    }}

    var meaning: String {{
        switch self {{
        case .full: return "API complete; fixtures pass exact layout and pixel checks"
        case .partial: return "Common usage works; listed gaps"
        case .approximate: return "Works but rendering knowingly differs"
        case .stub: return "Compiles, no behaviour"
        case .missing: return "Not implemented yet"
        }}
    }}
}}

struct SupportEntry: Identifiable {{
    let id: Int
    let api: String
    let status: SupportStatus
    let notes: String
    let fixtures: Int
}}

struct SupportSection: Identifiable {{
    let title: String
    let entries: [SupportEntry]
    var id: String {{ title }}
}}

enum SupportData {{
    static let generated = "{data['generated']}"
    static let counts: [SupportStatus: Int] = [{count_literal}]
    static var total: Int {{ counts.values.reduce(0, +) }}

    static let sections: [SupportSection] = {{
        var sections: [SupportSection] = []
        var title = ""
        var entries: [SupportEntry] = []
        var id = 0
        func flush() {{
            if !title.isEmpty {{ sections.append(SupportSection(title: title, entries: entries)) }}
            entries = []
        }}
        for line in blob.split(separator: "\\n", omittingEmptySubsequences: true) {{
            if line.hasPrefix("# ") {{
                flush()
                title = String(line.dropFirst(2))
                continue
            }}
            let fields = line.split(separator: "\\t", omittingEmptySubsequences: false).map(String.init)
            guard fields.count == 4, let status = SupportStatus(rawValue: fields[0]) else {{ continue }}
            id += 1
            entries.append(SupportEntry(id: id, api: fields[1], status: status, notes: fields[2], fixtures: Int(fields[3]) ?? 0))
        }}
        flush()
        return sections
    }}()

    private static let blob = """
{blob}
"""
}}
'''


def render_progress(support, todo):
    """The progress page's data (Examples/Progress): two tab-separated blobs parsed on first use,
    one row per support entry and one per todo item, plus the dates the data was edited."""
    def clean(text):
        return str(text).replace("\t", " ").replace("\n", " ")
    rows = []
    for section in support["sections"]:
        for e in section["entries"]:
            rows.append("\t".join([section["framework"], clean(section["title"]), e["status"], clean(e["api"]), clean(e.get("notes", "")),
                                   "|".join(e.get("fixtures", [])), clean(e.get("noFixture", ""))]))
    items = []
    for item in todo["items"]:
        items.append("\t".join([item["id"], item["framework"], clean(item["area"]), item["priority"], item["status"], item["kind"],
                                clean(item["title"]), clean(item["detail"]), item.get("done", ""), "|".join(item.get("refs", []))]))
    edited = max([support["generated"]] + [i["done"] for i in todo["items"] if i.get("done")])
    def literal(lines):
        return "\n".join(lines).replace("\\", "\\\\").replace('"""', '\\"\\"\\"')
    return f'''// Generated by scripts/gen-progress.py from Docs/support.json and Docs/todo.json; do not edit.
// The progress page's data as tab-separated blobs parsed on first use (large array literals
// compile into code on wasm and bloat the binary): one line per support row and per todo item.

enum ProgressData {{
    /// The day the data was last edited (support.json's `generated`, or the newest `done` date).
    static let edited = "{edited}"
    static let supportBlob = """
{literal(rows)}
"""
    static let todoBlob = """
{literal(items)}
"""
}}
'''


def main():
    check = "--check" in sys.argv
    todo = load_todo()
    support = load_support()
    outputs = {todo_md: render_todo(todo), matrix_md: render_matrix(support), landing_swift: render_landing(support),
               progress_swift: render_progress(support, todo)}
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
