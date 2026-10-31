#!/usr/bin/env python3
"""An API surface as a set of keys, from a folder of symbol graphs (`*.symbols.json`).

A key is a symbol's path components joined by dots: `View.navigationTitle(_:)`,
`Button.init(_:action:)`, `ScrollViewReader`. Overloads that differ only in their types share
a key, so the diff counts names and argument labels, not every generic variant. The module a
symbol is declared in is kept but not part of the key: Apple splits SwiftUI across SwiftUI and
SwiftUICore, and SwiftUIWeb across SwiftUIWebCore, SwiftUIWebUIKit and the framework modules.

  surface.py apple <dir> -o apple.json   # one subfolder per Apple module (apple-symbols.sh)
  surface.py ours <dir> -o ours.json     # the graphs a SwiftUIWeb build emitted

Left out: underscored names, symbols synthesized from protocol extensions (`::SYNTHESIZED::`,
the same member repeated on every conforming type), and symbols unavailable or obsoleted on
iOS. Deprecated symbols are kept and marked.
"""
import argparse
import json
from pathlib import Path

IOS_DOMAINS = {"iOS", "iPadOS", "*"}
# The modules an app sees through SwiftUIWeb on wasm; a build's graphs also hold its packages'
# (swift-syntax, JavaScriptKit), which are not API an app reaches for.
OUR_MODULES = {
    "SwiftUI", "SwiftUIWebCore", "SwiftUIWebUIKit", "SwiftUIWebCanvas", "Charts", "MapKit", "CoreLocation",
    "AVFoundation", "AVKit", "Speech", "SwiftData", "UserNotifications", "WebKit", "UIKit", "UIKitWebCore",
    "WebFoundation", "WebCombine", "WebGraphics", "Foundation", "Combine", "Security", "SafariServices",
    "CoreData", "WebCoreData", "CryptoKit", "CoreHaptics", "WidgetKit",
}
SKIP_KINDS = {"swift.deinit"}


def symbols(path: Path):
    data = json.loads(path.read_text())
    module = data.get("module", {}).get("name", path.name.split(".")[0].split("@")[0])
    for s in data.get("symbols", []):
        yield module, s


def entry(s, apple):
    pid = s.get("identifier", {}).get("precise", "")
    if "::SYNTHESIZED::" in pid:
        return None
    pc = s.get("pathComponents") or []
    if not pc or any(c.startswith("_") for c in pc):
        return None
    kind = s.get("kind", {}).get("identifier", "")
    if kind in SKIP_KINDS:
        return None
    if s.get("accessLevel") not in (None, "public", "open"):
        return None
    deprecated = False
    for a in s.get("availability") or []:
        if a.get("domain") not in IOS_DOMAINS:
            continue
        if a.get("isUnconditionallyUnavailable") or "obsoleted" in a:
            return None
        if a.get("isUnconditionallyDeprecated") or "deprecated" in a:
            deprecated = True
    if apple:
        # A symbol whose availability names other platforms but not iOS is not on iOS.
        domains = {a.get("domain") for a in s.get("availability") or [] if "introduced" in a}
        if domains and not domains & {"iOS", "iPadOS", "*"}:
            return None
    return ".".join(pc), {"kind": kind.replace("swift.", ""), "deprecated": deprecated}


def collect(folder: Path, apple: bool, group_by_folder: bool):
    out = {}
    for f in sorted(folder.rglob("*.symbols.json")):
        group = f.parent.name if group_by_folder else None
        for module, s in symbols(f):
            if not apple and module not in OUR_MODULES:
                continue
            e = entry(s, apple)
            if not e:
                continue
            key, info = e
            info["module"] = group or module
            bucket = out.setdefault(info["module"] if apple else "all", {})
            prev = bucket.get(key)
            # An overload that is not deprecated keeps the key current.
            if prev is None or (prev["deprecated"] and not info["deprecated"]):
                bucket[key] = info
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("side", choices=["apple", "ours"])
    ap.add_argument("folder")
    ap.add_argument("-o", "--out", required=True)
    args = ap.parse_args()
    folder = Path(args.folder)
    data = collect(folder, args.side == "apple", group_by_folder=args.side == "apple")
    meta = {}
    if (folder / "sdk-version").exists():
        meta["sdk"] = (folder / "sdk-version").read_text().strip()
    Path(args.out).write_text(json.dumps({"meta": meta, "modules": data}))
    for m, keys in sorted(data.items()):
        print(f"{m}: {len(keys)} keys ({sum(1 for v in keys.values() if v['deprecated'])} deprecated)")


if __name__ == "__main__":
    main()
