#!/usr/bin/env python3
"""The compile sweep (Tools/Coverage/README.md): build the corpus's open-source apps for wasm
against SwiftUIWeb and record every error, classified, so the gaps are ranked by how many real
apps hit them.

This is a measurement, not the acceptance standard of decision 0021. To get past the first
missing import and see what an app uses below it, the sweep rewrites copies of the sources: an
`import` of a module that does not exist on wasm becomes `import Foundation` with the original as a
comment, since every Apple framework re-exports Foundation (the line count is kept, so every error
points at the upstream line). Nothing upstream is edited; the clones are read only.

Subcommands, in the order the Coverage workflow runs them:
  plan     clone every app, read its local packages, group the apps into batches whose module
           names do not collide (one sweep package per batch builds SwiftUIWeb once)
  fetch    clone one batch's apps at the commits the plan recorded
  prepare  write the batch's sweep package: one target per local package target, one for the app
  run      build every target in dependency order, classify the errors, write results.json
"""
import argparse
import json
import os
import re
import shutil
import subprocess
import sys
from collections import Counter, defaultdict
from pathlib import Path

# The modules an app can import on wasm: SwiftUIWeb's products, the shadows (Packages/Shadows)
# and what the wasm SDK itself carries.
OURS = {
    "SwiftUI", "UIKit", "Foundation", "Combine", "Security", "SafariServices", "Charts", "MapKit",
    "CoreLocation", "AVFoundation", "AVKit", "Speech", "SwiftData", "UserNotifications", "WebKit",
    "os", "OSLog", "CoreGraphics", "UniformTypeIdentifiers", "CoreData", "CryptoKit", "CoreHaptics", "WidgetKit", "StoreKit", "AppIntents",
}
STDLIB = {"Swift", "_Concurrency", "_StringProcessing", "Observation", "Synchronization", "RegexBuilder", "Dispatch", "WASILibc"}
# swift-syntax, which the sweep package depends on itself: a package's macro targets import it.
SYNTAX_PACKAGE = "https://github.com/swiftlang/swift-syntax.git"
SYNTAX = {"SwiftSyntax", "SwiftSyntaxMacros", "SwiftCompilerPlugin", "SwiftSyntaxBuilder", "SwiftDiagnostics",
          "SwiftParser", "SwiftParserDiagnostics", "SwiftBasicFormat", "SwiftOperators", "SwiftSyntaxMacroExpansion",
          "SwiftIfConfig", "SwiftLexicalLookup", "SwiftSyntaxMacrosTestSupport", "SwiftSyntaxMacrosGenericTestSupport"}

# Apple's frameworks, to tell a missing framework from a third-party package in the report.
APPLE = set("""
os OSLog CoreData CoreGraphics QuartzCore CoreImage StoreKit PhotosUI Photos CloudKit WidgetKit AppIntents
ActivityKit CoreHaptics AuthenticationServices LocalAuthentication CryptoKit Network MessageUI EventKit
EventKitUI Contacts ContactsUI PDFKit QuickLook QuickLookThumbnailing GameKit GameController SpriteKit SceneKit
RealityKit ARKit Vision VisionKit CoreML NaturalLanguage HealthKit HealthKitUI CoreMotion CoreBluetooth CoreNFC
MediaPlayer MusicKit TipKit Translation FoundationModels UniformTypeIdentifiers LinkPresentation
BackgroundTasks UserNotificationsUI CoreSpotlight CoreTransferable CoreText CoreFoundation CoreMedia
CoreVideo CoreAudio AudioToolbox AVRouting ImageIO Metal MetalKit MetalPerformanceShaders Accelerate simd
Darwin ObjectiveC SystemConfiguration Intents IntentsUI Social WatchConnectivity AppKit Cocoa CarPlay
ShazamKit WeatherKit CoreTelephony NetworkExtension DeviceActivity FamilyControls ManagedSettings
SwiftUICore GroupActivities PassKit AdSupport AppTrackingTransparency MultipeerConnectivity ExtensionKit
StoreKitTest XCTest Testing Charts MapKit Speech SwiftData UserNotifications WebKit SafariServices Security
AVFoundation AVKit Combine Foundation UIKit SwiftUI CoreLocation CoreLocationUI DeveloperToolsSupport
AppleArchive Compression SoundAnalysis AVFAudio MediaToolbox Symbols ScreenTime SensitiveContentAnalysis
JavaScriptCore OSLog Spatial PhotosUI_Private CoreAudioKit Accessibility AccessibilitySupport MLX
""".split())

# A directory component that marks code outside the iOS app target: tests, extensions, the other
# platforms, vendored tooling.
EXCLUDE_DIR = re.compile(
    r"^(\.build|\.swiftpm|\.git|pods|carthage|derived ?data|fastlane|vendor|node_modules|third.?party|"
    r".*tests?|.*uitests?|preview content|snapshots?|"
    r".*widgets? ?extension|.*widget|.*extension|.*intents? ?(ui|extension)?|.*clip|"
    r"watch|watchos|.*watchkit.*|.*watch ?(os|app|extension)|"
    r"mac|macos|.*mac|.*macos|.*catalyst|tv|tvos|.*tv ?os|visionos|.*visionos|.*vision ?pro|android|kmp|"
    r"scripts|tools|plugins|docs?|skip)$",
    re.IGNORECASE,
)
IMPORT = re.compile(
    r"^(\s*)((?:@[\w]+(?:\([^)]*\))?\s+)*)import\s+(?:(?:typealias|struct|class|enum|protocol|let|var|func)\s+)?([A-Za-z_]\w*)"
)
MAIN = re.compile(r"^\s*@(main|UIApplicationMain)\b", re.MULTILINE)


def sh(cmd, cwd=None, timeout=None, check=True):
    r = subprocess.run(cmd, cwd=cwd, text=True, capture_output=True, timeout=timeout)
    if check and r.returncode != 0:
        raise RuntimeError(f"{' '.join(cmd)} failed ({r.returncode}):\n{r.stdout}\n{r.stderr}")
    return r


def clone(repo, dest, ref=None):
    """A shallow clone of a public GitHub repository at `ref` (or the default branch's head)."""
    if dest.exists():
        shutil.rmtree(dest)
    dest.mkdir(parents=True)
    url = f"https://github.com/{repo}.git"
    sh(["git", "init", "-q"], cwd=dest)
    sh(["git", "remote", "add", "origin", url], cwd=dest)
    for attempt in range(3):
        r = sh(["git", "fetch", "-q", "--depth", "1", "origin", ref or "HEAD"], cwd=dest, check=False, timeout=900)
        if r.returncode == 0:
            break
    else:
        raise RuntimeError(f"fetch {repo} failed: {r.stderr.strip()}")
    sh(["git", "checkout", "-q", "FETCH_HEAD"], cwd=dest)
    return sh(["git", "rev-parse", "HEAD"], cwd=dest).stdout.strip()


def is_manifest(name: str) -> bool:
    """Whether a file name is a SwiftPM manifest (`Package.swift`, `Package@swift-5.9.swift`)."""
    return name == "Package.swift" or name.startswith("Package@swift")


def excluded(rel: Path, extra):
    parts = rel.parts[:-1]
    if any(EXCLUDE_DIR.match(p) for p in parts):
        return True
    return any(str(rel).startswith(e.rstrip("/") + "/") or str(rel) == e for e in extra)


# MARK: local packages

def dump_package(pkg_dir: Path):
    r = sh(["swift", "package", "dump-package", "--package-path", str(pkg_dir)], check=False, timeout=600)
    if r.returncode != 0:
        return None, (r.stderr or r.stdout).strip().splitlines()[-1:] or ["dump-package failed"]
    try:
        return json.loads(r.stdout), None
    except json.JSONDecodeError as e:
        return None, [str(e)]


def tools_major(dump):
    v = (dump.get("toolsVersion") or {}).get("_version", "5.0")
    return int(v.split(".")[0])


def language_mode_of_package(dump, target):
    """v6 when the manifest's tools are 6 and nothing pins the target or the package to 5."""
    for s in target.get("settings") or []:
        text = json.dumps(s)
        if "swiftLanguageMode" in text or "swiftLanguageVersion" in text:
            return "v6" if '"v6"' in text or '"6"' in text else "v5"
    langs = dump.get("swiftLanguageModes") or dump.get("swiftLanguageVersions")
    if langs:
        text = json.dumps(langs)
        if "6" not in text:
            return "v5"
    return "v6" if tools_major(dump) >= 6 else "v5"


def swift_settings(target):
    """The defines and upcoming features a target declares, as manifest source."""
    out = []
    for s in target.get("settings") or []:
        if s.get("tool") != "swift" or s.get("condition"):
            continue
        kind = s.get("kind") or {}
        for key, ctor in (("define", "define"), ("enableUpcomingFeature", "enableUpcomingFeature"),
                          ("enableExperimentalFeature", "enableExperimentalFeature")):
            if key in kind:
                value = kind[key].get("_0") if isinstance(kind[key], dict) else kind[key]
                if isinstance(value, str):
                    out.append(f".{ctor}({json.dumps(value)})")
    return out


C_SOURCES = {".c", ".cc", ".cpp", ".cxx", ".m", ".mm"}
C_HEADERS = {".h", ".hh", ".hpp", ".inc", ".def", ".modulemap"}
# An Objective-C target this small is a shim (swift-navigation's UIKitNavigationShim): its headers
# stand in for it so the Swift targets above it still build. A bigger one (Firebase) is left out.
SHIM_LIMIT = 4


def c_settings(target):
    """The header search paths and defines a C target declares for every platform, as manifest source."""
    out = []
    for s in target.get("settings") or []:
        if s.get("tool") not in ("c", "cxx"):
            continue
        cond = s.get("condition") or {}
        if cond.get("platformNames") and not {"linux", "wasi"} & set(cond["platformNames"]):
            continue
        kind = s.get("kind") or {}
        for key in ("headerSearchPath", "define"):
            if key in kind:
                value = kind[key].get("_0") if isinstance(kind[key], dict) else kind[key]
                if isinstance(value, str):
                    entry = f".{key}({json.dumps(value)})"
                    if entry not in out:
                        out.append(entry)
    return out


def dependency_names(dep):
    """(kind, name, package) for a dump-package target dependency."""
    for kind in ("target", "byName", "product"):
        if kind in dep:
            v = dep[kind]
            return kind, v[0], (v[1] if kind == "product" else None)
    return None, None, None


def read_local_packages(root: Path, extra_exclude):
    """Every Package.swift in the clone (outside build and test folders) with its targets."""
    packages = []
    for manifest in sorted(root.rglob("Package.swift")):
        rel = manifest.relative_to(root)
        if excluded(rel, extra_exclude):
            continue
        dump, err = dump_package(manifest.parent)
        packages.append({"dir": str(manifest.parent.relative_to(root)), "dump": dump, "error": err})
    return packages


# MARK: remote packages
#
# An app's third-party packages, as Xcode resolved them (Package.resolved), are cloned at their
# pinned revisions under `<work>/_packages/<identity>@<revision>` and built from source like the
# local packages: one target per regular target (and macro targets, built for the host against
# swift-syntax). Binary, system-library and plugin targets, C-only targets and what depends on
# them are left out; an app's import of one of those is taken out like any other missing module.

PACKAGES_DIR = "_packages"


def github_repo(url):
    """`owner/name` for a GitHub URL (https, ssh or scp form), or None."""
    m = re.match(r"^(?:https?://|ssh://git@|git@)github\.com[/:]([^/]+)/([^/]+?)(?:\.git)?/?$", url.strip())
    return f"{m.group(1)}/{m.group(2)}" if m else None


def resolved_pins(root: Path, extra):
    """{identity: {"url", "repo", "revision"}} from every Package.resolved of the app (Xcode's in
    the project or workspace, and its local packages'), the first file's pin winning."""
    pins = {}
    for f in sorted(root.rglob("Package.resolved"), key=lambda p: (len(p.parts), str(p))):
        rel = f.relative_to(root)
        if excluded(rel, extra) or ".build" in rel.parts:
            continue
        try:
            data = json.loads(f.read_text(errors="replace"))
        except json.JSONDecodeError:
            continue
        for pin in (data.get("object") or {}).get("pins") or data.get("pins") or []:
            url = pin.get("location") or pin.get("repositoryURL") or ""
            revision = (pin.get("state") or {}).get("revision")
            repo = github_repo(url)
            if not repo or not revision:
                continue
            identity = (pin.get("identity") or repo.split("/")[1]).lower()
            pins.setdefault(identity, {"url": url, "repo": repo, "revision": revision})
    return pins


def package_key(identity, pin):
    return f"{identity}@{pin['revision'][:12]}"


def fetch_packages(work: Path, pins):
    """Clones each pinned package once per revision; {identity: key} of the ones that cloned."""
    keys = {}
    for identity, pin in sorted(pins.items()):
        if pin["url"].rstrip("/").removesuffix(".git").lower().endswith("swiftlang/swift-syntax") or \
                pin["repo"].lower() in ("apple/swift-syntax", "swiftlang/swift-syntax"):
            continue  # the sweep package's own swift-syntax builds the macros
        key = package_key(identity, pin)
        dest = work / PACKAGES_DIR / key
        if not (dest / ".git").exists():
            try:
                clone(pin["repo"], dest, pin["revision"])
            except Exception as e:
                print(f"package {identity}: {str(e).splitlines()[0][:200]}", file=sys.stderr)
                continue
        keys[identity] = key
    return keys


def condition_allows_ios(dep):
    """Whether a dump-package dependency's platform condition (if any) includes iOS."""
    for part in (dep.get("product") or dep.get("byName") or dep.get("target") or [])[1:]:
        if isinstance(part, dict) and part.get("platformNames"):
            return "ios" in part["platformNames"]
    return True


def describe_remote_packages(work: Path, keys, notes):
    """The targets of the cloned packages, in the shape describe_app gives local ones, each with
    `base` (its clone, relative to the work folder) and `remote` (its package key)."""
    dumps = {}
    for identity, key in keys.items():
        dump, err = dump_package(work / PACKAGES_DIR / key)
        if not dump:
            notes.append(f"package {identity}: {err[0] if err else 'unreadable'}")
            continue
        dumps[identity] = dump
    products = {}  # product name -> (identity, target names)
    for identity, dump in dumps.items():
        for prod in dump.get("products", []):
            if "library" in json.dumps(prod.get("type") or {}):
                products.setdefault(prod["name"], (identity, prod.get("targets", [])))
    targets, left_out = [], set()
    for identity, dump in dumps.items():
        key = keys[identity]
        root = work / PACKAGES_DIR / key
        names = {t["name"] for t in dump["targets"]}
        for t in dump["targets"]:
            kind = t["type"]
            if kind not in ("regular", "macro"):
                if kind in ("binary", "system", "plugin"):
                    left_out.add(t["name"])
                    notes.append(f"package {identity}: {kind} target {t['name']} not built")
                continue
            path = t.get("path") or f"Sources/{t['name']}"
            src = root / path
            if not src.is_dir():
                notes.append(f"package {identity}: target {t['name']} has no folder {path}")
                left_out.add(t["name"]); continue
            excludes = [str(Path(path) / e) for e in t.get("exclude", [])]
            files = [str(f.relative_to(root)) for f in sorted(src.rglob("*.swift"))
                     if f.is_file() and not any(str(f.relative_to(root)).startswith(e.rstrip("/") + "/") or str(f.relative_to(root)) == e for e in excludes)
                     and not (f.parent == root and is_manifest(f.name))]
            c_kind = None
            if not files:
                found = [f for f in src.rglob("*") if f.is_file()]
                sources = [f for f in found if f.suffix in C_SOURCES]
                objc = [f for f in sources if f.suffix in (".m", ".mm")]
                has_headers = any(f.suffix in C_HEADERS for f in found)
                if not objc and (sources or has_headers):
                    c_kind = "c"  # built as it is, by the wasm SDK's clang
                elif objc and len(objc) <= SHIM_LIMIT and has_headers:
                    c_kind = "headers"  # its headers only, so the module exists
                    notes.append(f"package {identity}: Objective-C shim {t['name']} stands in with its headers only")
                else:
                    left_out.add(t["name"])
                    why = f"{len(objc)} Objective-C files" if objc else "no sources"
                    notes.append(f"package {identity}: target {t['name']} has {why}, not built")
                    continue
            deps, syntax = [], []
            for d in t.get("dependencies", []):
                if not condition_allows_ios(d):
                    continue
                k, name, package = dependency_names(d)
                if k in ("target", "byName") and name in names:
                    deps.append(name)
                elif name in SYNTAX:
                    syntax.append(name)
                elif name in products and k in ("product", "byName"):
                    deps.extend(products[name][1])
                elif name:
                    left_out.add(f"{t['name']}<-{name}")
                    notes.append(f"package {identity}: target {t['name']} needs {name}, which no pinned package vends")
            targets.append({
                "module": t["name"], "source_root": path, "files": files, "base": f"{PACKAGES_DIR}/{key}",
                "remote": key, "deps": sorted(set(deps) - {t["name"]}), "syntax": sorted(set(syntax)),
                "third_party": [], "mode": language_mode_of_package(dump, t), "settings": swift_settings(t),
                "resources": [r.get("path") for r in t.get("resources") or [] if r.get("path")],
                "models": [], "executable": False, "macro": kind == "macro",
                **({"c": c_kind, "public_headers": t.get("publicHeadersPath") or "include",
                    "c_settings": c_settings(t), "exclude": t.get("exclude", [])} if c_kind else {}),
            })
    # What depends on a target that is not built is not built either (its module stays missing).
    missing = {n for n in left_out if "<-" not in n}
    changed = True
    while changed:
        changed = False
        for t in targets:
            if not t.get("skip") and any(d in missing or d not in {x["module"] for x in targets} for d in t["deps"]):
                t["skip"] = True; missing.add(t["module"]); changed = True
                gone = [d for d in t["deps"] if d in missing or d not in {x["module"] for x in targets}]
                notes.append(f"package target {t['module']} depends on {', '.join(gone[:3])}, not built; not built either")
    built = [t for t in targets if not t.get("skip")]
    modules = {t["module"] for t in built}
    vends = {name: [n for n in names if n in modules] for name, (_, names) in products.items()}
    return built, {name: names for name, names in vends.items() if names}


# MARK: plan

def module_keys(app):
    """Each module the app's batch must build, with what makes it the same module in another
    app: a package target is the same at the same package revision, an app's own never is."""
    return {t["module"]: t.get("remote") or f"app:{app['name']}" for t in app["targets"]}


def data_models(root: Path, base: Path):
    """The Core Data models (`.xcdatamodeld` bundles, bare `.xcdatamodel` folders) under a folder,
    as paths relative to the clone, for the CoreDataModel plugin."""
    found = []
    for d in sorted((root / base).rglob("*.xcdatamodel*")):
        rel = d.relative_to(root)
        if not d.is_dir() or d.suffix not in (".xcdatamodeld", ".xcdatamodel"):
            continue
        if d.suffix == ".xcdatamodel" and d.parent.suffix == ".xcdatamodeld":
            continue
        if any(EXCLUDE_DIR.match(x) for x in d.relative_to(root / base).parts[:-1]):
            continue
        found.append(str(rel))
    # Xcode builds one model per name. A second copy by the same name (a stale one left beside
    # the project, as Dime's top-level MainModel.xcdatamodeld) loses to the copy with more
    # attributes, so the classes come from the model the app was written against.
    best = {}
    for rel in found:
        name = Path(rel).name
        size = sum(c.read_text(errors="replace").count("<attribute ")
                   for c in (root / rel).rglob("contents"))
        if name not in best or size > best[name][1]:
            best[name] = (rel, size)
    return [rel for rel in found if best[Path(rel).name][0] == rel]


def describe_app(entry, root: Path, work: Path = None):
    """The sweep's view of one clone: its local targets, its packages' targets, the app target's
    files, the imports."""
    extra = entry.get("exclude", [])
    packages = read_local_packages(root, extra)
    pins = resolved_pins(root, extra) if work else {}
    remote_notes = []
    remote, remote_names_by_product = describe_remote_packages(work, fetch_packages(work, pins), remote_notes) if pins else ([], {})
    pkg_dirs = [Path(p["dir"]) for p in packages]
    targets, notes = [], []
    product_targets = {}  # product name -> target names, across the local packages
    for p in packages:
        if p["dump"]:
            for prod in p["dump"].get("products", []):
                product_targets.setdefault(prod["name"], prod.get("targets", []))
    for p in packages:
        if not p["dump"]:
            notes.append(f"{p['dir']}/Package.swift: {p['error'][0] if p['error'] else 'unreadable'}")
            continue
        dump = p["dump"]
        local_names = {t["name"] for t in dump["targets"]}
        for t in dump["targets"]:
            if t["type"] not in ("regular", "executable"):
                if t["type"] == "macro":
                    notes.append(f"{p['dir']}: macro target {t['name']} not built")
                continue
            path = t.get("path") or f"Sources/{t['name']}"
            src = Path(p["dir"]) / path
            if not (root / src).is_dir():
                notes.append(f"{p['dir']}: target {t['name']} has no folder {path}")
                continue
            deps, third = [], []
            for d in t.get("dependencies", []):
                kind, name, package = dependency_names(d)
                if kind in ("target", "byName") and name in local_names:
                    deps.append(name)
                elif name in product_targets and kind in ("product", "byName"):
                    deps.extend(product_targets[name])
                elif name in remote_names_by_product and kind in ("product", "byName"):
                    deps.extend(remote_names_by_product[name])
                elif name:
                    third.append(name)
            files = [str(f.relative_to(root)) for f in sorted((root / src).rglob("*.swift"))
                     if not any(EXCLUDE_DIR.match(x) for x in f.relative_to(root / src).parts[:-1])]
            files = [f for f in files if Path(f).name not in t.get("exclude", [])]
            # A target at the package's own folder (`path: "."`) holds its manifest, which is
            # SwiftPM's to read, not a source of the module (BackyardBirds' data package).
            files = [f for f in files if not (Path(f).parent == Path(p["dir"]) and is_manifest(Path(f).name))]
            targets.append({
                "module": t["name"], "source_root": str(src), "files": files,
                "deps": sorted(set(deps) - {t["name"]}), "third_party": sorted(set(third)),
                "mode": language_mode_of_package(dump, t), "settings": swift_settings(t),
                "resources": [r.get("path") for r in t.get("resources") or [] if r.get("path")],
                "models": data_models(root, src),
                "executable": t["type"] == "executable",
            })
    local_count = len(targets)
    targets.extend(remote)
    notes.extend(remote_notes)
    # The app target: every Swift file outside the local packages and the excluded folders.
    app_files = []
    for f in sorted(root.rglob("*.swift")):
        rel = f.relative_to(root)
        if is_manifest(rel.name):
            continue
        if excluded(rel, extra) or any(rel.is_relative_to(d) for d in pkg_dirs if str(d) != "."):
            continue
        if Path(".") in pkg_dirs and any(rel.is_relative_to(Path(t["source_root"])) for t in targets if not t.get("remote")):
            continue
        app_files.append(str(rel))
    # One @main: the SwiftUI App (or the UIKit delegate) of the iOS app, the others' files left out.
    mains = [f for f in app_files if MAIN.search((root / f).read_text(errors="replace"))]
    if len(mains) > 1:
        def score(f):
            text = (root / f).read_text(errors="replace")
            return (0 if re.search(r":\s*App\b", text) else 1, 0 if "ios" in f.lower() else 1, len(f))
        keep = min(mains, key=score)
        for f in mains:
            if f != keep:
                app_files.remove(f)
                notes.append(f"left out a second @main: {f}")
    executable_locals = [t for t in targets[:local_count] if t["executable"]]
    if not app_files and executable_locals:
        executable_locals[0]["app"] = True
    elif app_files:
        models = [m for m in data_models(root, Path(".")) if not excluded(Path(m), extra)
                  and not any(Path(m).is_relative_to(d) for d in pkg_dirs if str(d) != ".")
                  and not any(Path(m).is_relative_to(Path(t["source_root"])) for t in targets if not t.get("remote"))]
        targets.append({
            "module": "Sweep" + re.sub(r"\W", "", entry["name"]), "source_root": ".", "files": app_files,
            "deps": sorted({t["module"] for t in targets if not t["executable"] and not t.get("macro")}), "third_party": [],
            "mode": xcode_language_mode(root), "settings": [], "resources": [], "models": models,
            "executable": True, "app": True,
        })
    # The app target links the package modules its files import (Xcode links the products the
    # project lists; the imports say which of them the app's code uses).
    remote_modules = {t["module"]: t for t in targets if t.get("remote") and not t.get("macro")}
    for t in targets:
        if t.get("app") and t["source_root"] == ".":
            imported = set()
            for f in t["files"]:
                for line in (root / f).read_text(errors="replace").splitlines():
                    m = IMPORT.match(line)
                    if m:
                        imported.add(m.group(3))
            t["deps"] = sorted({d for d in t["deps"] if d not in remote_modules}
                               | {n for n in remote_modules if n in imported or n.replace("-", "_") in imported})
    # Only the package targets the app's own targets reach are built.
    by = {t["module"]: t for t in targets}
    reach, todo = set(), [t["module"] for t in targets if not t.get("remote")]
    while todo:
        n = todo.pop()
        if n in reach or n not in by:
            continue
        reach.add(n)
        todo.extend(by[n]["deps"])
    targets = [t for t in targets if not t.get("remote") or t["module"] in reach]
    for t in targets:
        if t["executable"] and not t.get("app"):
            t["skip"] = True
            notes.append(f"executable target {t['module']} is not the app; not built")
    # Imports, per target, of modules that are neither ours, the SDK's nor local (a target named
    # with a hyphen is imported with an underscore).
    local = {t["module"] for t in targets} | {t["module"].replace("-", "_") for t in targets}
    imports = Counter()
    for t in targets:
        if t.get("macro"):
            continue  # built for the host: its imports are swift-syntax's and the host's
        base = work / t["base"] if t.get("base") else root
        for f in t["files"]:
            for line in (base / f).read_text(errors="replace").splitlines():
                m = IMPORT.match(line)
                if m:
                    imports[m.group(3)] += 1
    missing = sorted(m for m in imports if m not in OURS | STDLIB | SYNTAX | local)
    asset_names = sorted({p.stem for p in root.rglob("*.colorset")} | {p.stem for p in root.rglob("*.imageset")}
                         | {p.stem for p in root.rglob("*.symbolset")})
    model_entities = sorted(set(re.findall(r'<entity name="([^"]+)"', "\n".join(
        c.read_text(errors="replace") for c in root.rglob("contents") if ".xcdatamodel" in str(c)))))
    os_conditions = sum(1 for t in targets if not t.get("remote") for f in t["files"]
                        if re.search(r"#(?:else)?if\b[^\n]*\bos\((?:iOS|macOS|watchOS|tvOS|visionOS)\)", (root / f).read_text(errors="replace")))
    return {
        "targets": targets, "notes": notes, "missing_imports": missing,
        "asset_names": asset_names, "model_entities": model_entities, "os_condition_files": os_conditions,
        "files": sum(len(t["files"]) for t in targets if not t.get("skip") and not t.get("remote")),
        "packages": sorted({t["remote"] for t in targets if t.get("remote")}),
        "pins": pins,
    }

    for key in sorted({t["remote"] for t in remote}):
        dump, _ = dump_package(work / PACKAGES_DIR / key)
        for prod in (dump or {}).get("products", []):
            built = [n for n in prod.get("targets", []) if any(t["module"] == n for t in remote)]
            if built:
                out.setdefault(prod["name"], built)
    return out


def xcode_language_mode(root: Path):
    versions = Counter()
    for pbx in root.rglob("project.pbxproj"):
        if any(EXCLUDE_DIR.match(p) for p in pbx.relative_to(root).parts[:-2]):
            continue
        versions.update(re.findall(r"SWIFT_VERSION = ([\d.]+);", pbx.read_text(errors="replace")))
    for yml in list(root.glob("project.yml")) + list(root.glob("*.yml")):
        versions.update(re.findall(r"SWIFT_VERSION:\s*\"?([\d.]+)", yml.read_text(errors="replace")))
    if not versions:
        return "v5"
    return "v6" if versions.most_common(1)[0][0].startswith("6") else "v5"


def cmd_plan(args):
    corpus = json.loads(Path(args.corpus).read_text())["apps"]
    work = Path(args.work)
    apps = []
    for entry in corpus:
        dest = work / entry["name"]
        try:
            sha = clone(entry["repo"], dest, entry.get("ref"))
        except Exception as e:  # a renamed or deleted repository is a result, not a failure of the sweep
            apps.append({**entry, "sha": None, "error": str(e).splitlines()[0][:300]})
            print(f"{entry['name']}: {e}", file=sys.stderr)
            continue
        try:
            info = describe_app(entry, dest, work)
        except Exception as e:  # one app's odd package must not stop the sweep: build it without packages
            print(f"{entry['name']}: packages not usable ({type(e).__name__}: {str(e)[:200]}); building without them", file=sys.stderr)
            info = describe_app(entry, dest)
            info["notes"].append(f"its packages could not be described ({type(e).__name__}); built without them")
        apps.append({**entry, "sha": sha, **info})
        print(f"{entry['name']}: {sha[:10]} {info['files']} files, {len(info['targets'])} targets, missing imports {info['missing_imports']}")
        for note in info["notes"]:
            if note.startswith("package"):
                print(f"  {note}")
    # Batches: no module name twice in one sweep package.
    batches = []
    for app in apps:
        if not app.get("sha"):
            app["batch"] = None
            continue
        keys = module_keys(app)
        for i, b in enumerate(batches):
            if len(b["apps"]) < args.batch_size and all(b["modules"].get(m, k) == k for m, k in keys.items()):
                b["apps"].append(app["name"]); b["modules"].update(keys); app["batch"] = i
                break
        else:
            batches.append({"apps": [app["name"]], "modules": dict(keys)}); app["batch"] = len(batches) - 1
    plan = {"apps": apps, "batches": [b["apps"] for b in batches]}
    Path(args.out).write_text(json.dumps(plan, indent=1))
    if os.environ.get("GITHUB_OUTPUT"):
        with open(os.environ["GITHUB_OUTPUT"], "a") as out:
            out.write(f"batches={json.dumps(list(range(len(batches))))}\n")
    print(f"{len(apps)} apps in {len(batches)} batches")


def cmd_fetch(args):
    plan = json.loads(Path(args.plan).read_text())
    for app in plan["apps"]:
        if app.get("batch") == args.batch:
            clone(app["repo"], Path(args.work) / app["name"], app["sha"])
            fetch_packages(Path(args.work), {i: p for i, p in (app.get("pins") or {}).items()
                                             if package_key(i, p) in set(app.get("packages", []))})


sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "Traits"))
import traits as app_traits  # noqa: E402  (Tools/Traits: which package traits an app needs, decision 0024)


# MARK: prepare

def strip_imports(text, strip):
    out = []
    for line in text.split("\n"):
        m = IMPORT.match(line)
        if m and m.group(3) in strip:
            # Every Apple framework re-exports Foundation, so a file that imported only CoreData
            # still sees URL and Date on iOS. Keep that, or the stripped import shows up as
            # Foundation gaps that are not there.
            line = f"{m.group(1)}import Foundation // [sweep] {line.strip()}"
        out.append(line)
    return "\n".join(out)


MANIFEST_HEAD = """// swift-tools-version: 6.1
// Generated by Tools/Coverage/sweep.py prepare: one target per local package target and one for
// each app of this batch, linking SwiftUIWeb's products where Xcode links Apple's frameworks.
import PackageDescription
import CompilerPluginSupport  // `.macro` targets (packages' macros, built for the host)

let web: [Target.Dependency] = [
    .product(name: "SwiftUI", package: "SwiftUIWeb"),
    .product(name: "SwiftUIWebCanvas", package: "SwiftUIWeb"),
    .product(name: "Charts", package: "SwiftUIWeb"),
    .product(name: "MapKit", package: "SwiftUIWeb"),
    .product(name: "AVFoundation", package: "SwiftUIWeb"),
    .product(name: "AVKit", package: "SwiftUIWeb"),
    .product(name: "Speech", package: "SwiftUIWeb"),
    .product(name: "SwiftData", package: "SwiftUIWeb"),
    .product(name: "UserNotifications", package: "SwiftUIWeb"),
    .product(name: "CryptoKit", package: "SwiftUIWeb"),
    .product(name: "CoreHaptics", package: "SwiftUIWeb"),
    .product(name: "WidgetKit", package: "SwiftUIWeb"),
    .product(name: "StoreKit", package: "SwiftUIWeb"),
    .product(name: "AppIntents", package: "SwiftUIWeb"),
    .product(name: "WebKit", package: "SwiftUIWeb"),
    .product(name: "UIKit", package: "UIKitWeb"),
    .product(name: "Foundation", package: "Shadows"),
    .product(name: "Combine", package: "Shadows"),
    .product(name: "Security", package: "Shadows"),
    .product(name: "SafariServices", package: "Shadows"),
    .product(name: "os", package: "Shadows"),
    .product(name: "OSLog", package: "Shadows"),
    .product(name: "CoreGraphics", package: "Shadows"),
    .product(name: "UniformTypeIdentifiers", package: "Shadows"),
    .product(name: "CoreData", package: "Shadows"),
]
let stack: [LinkerSetting] = [.unsafeFlags(["-Xlinker", "-z", "-Xlinker", "stack-size=4194304"])]
"""


DECL_NAME = re.compile(r'name: "([^"]+)"')


def render_manifest(parts, drops=None):
    """The sweep package's manifest from prepare's parts, with `drops` ({module: dependencies})
    taken out of those targets' dependencies (a package target that did not build). Each target is
    its own statement: one `targets: [...]` literal holding every package's targets is more than
    the manifest's type checker will take in reasonable time."""
    drops = drops or {}
    out = []
    for d in parts["decls"]:
        m = DECL_NAME.search(d)
        gone = drops.get(m.group(1), ()) if m else ()
        if gone:
            lines = d.split("\n")
            for i, line in enumerate(lines):
                if line.strip().startswith("dependencies:"):
                    for n in gone:
                        q = json.dumps(n)
                        line = line.replace(q + ", ", "").replace(", " + q, "").replace(q, "")
                    lines[i] = line
            d = "\n".join(lines)
        out.append("targets.append(\n" + d.strip().rstrip(",") + "\n)")
    return parts["head"] + "\n".join(out) + "\n" + parts["tail"]


def cmd_prepare(args):
    plan = json.loads(Path(args.plan).read_text())
    pkg = Path(args.out)
    work = Path(args.work)
    root = Path(args.root).resolve()
    strip_extra = json.loads(Path(args.strip).read_text()) if args.strip and Path(args.strip).exists() else {}
    if (pkg / "Sources").exists():
        shutil.rmtree(pkg / "Sources")
    pkg.mkdir(parents=True, exist_ok=True)
    mapping, decls, strips = {}, [], {}
    # The package traits this batch's apps need (decision 0024), as each app's own manifest would
    # enable them; --all-traits turns every one on (the surface build, which has no apps).
    traits_needed = set(app_traits.TRAITS) if args.all_traits else set()
    declared, uses_syntax = set(), False
    for app in plan["apps"]:
        if app.get("batch") != args.batch:
            continue
        local = {t["module"] for t in app["targets"]} | {t["module"].replace("-", "_") for t in app["targets"]}
        strip = (set(app["missing_imports"]) | set(strip_extra.get(app["name"], []))) - local
        strips[app["name"]] = sorted(strip)
        for t in app["targets"]:
            if t.get("skip"):
                continue
            if t["module"] in declared:
                continue  # a package another app of the batch pins at the same revision
            declared.add(t["module"])
            clone_dir = work / (t.get("base") or app["name"])
            dest_root = pkg / "Sources" / t["module"]
            if t.get("c"):
                # A C target: its folder as it is (an Objective-C shim: without its .m files, plus
                # an empty source so the target has one), built by the SDK's clang.
                src = clone_dir / t["source_root"]
                skip_objc = t["c"] == "headers"
                shutil.copytree(src, dest_root, dirs_exist_ok=True, symlinks=False,
                                ignore=lambda d, names: [n for n in names if skip_objc and Path(n).suffix in (".m", ".mm")
                                                         or n in (".git", ".build") or is_manifest(n)
                                                         or not (Path(d) / n).exists()])
                if skip_objc:
                    (dest_root / "_sweep_shim.c").write_text("/* The sweep builds this Objective-C shim's headers only. */\n")
                excludes = [e for e in t.get("exclude", []) if (dest_root / e).exists()]
                decls.append(
                    f'        .target(\n            name: "{t["module"]}",\n            dependencies: [{", ".join(json.dumps(d) for d in t["deps"])}],\n'
                    f'            path: "Sources/{t["module"]}",\n'
                    + (f'            exclude: [{", ".join(json.dumps(e) for e in excludes)}],\n' if excludes else "")
                    + f'            publicHeadersPath: {json.dumps(t["public_headers"])},\n'
                    + f'            cSettings: [{", ".join(t["c_settings"])}]\n        ),'
                )
                continue
            if t.get("macro"):
                # Built for the host against the sweep package's swift-syntax; sources as they are.
                uses_syntax = True
                for f in t["files"]:
                    dest = dest_root / Path(f).relative_to(t["source_root"])
                    dest.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(clone_dir / f, dest)
                syntax = "".join(f', .product(name: "{n}", package: "swift-syntax")' for n in t.get("syntax", []))
                deps = (", ".join(json.dumps(d) for d in t["deps"]) + syntax).lstrip(", ")
                settings = ", ".join([f".swiftLanguageMode(.{t['mode']})"] + t["settings"])
                decls.append(
                    f'        .macro(\n            name: "{t["module"]}",\n            dependencies: [{deps}],\n'
                    f'            path: "Sources/{t["module"]}",\n'
                    f'            swiftSettings: [{settings}]\n        ),'
                )
                continue
            used = set()
            for f in t["files"]:
                rel = Path(f).relative_to(t["source_root"]) if t["source_root"] != "." else Path(f)
                name = rel.name
                if name.lower() in used:  # a module takes each file name once
                    name = f"{rel.parent.name or 'root'}_{name}"
                    while name.lower() in used:
                        name = "_" + name
                used.add(name.lower())
                dest = dest_root / rel.parent / name
                dest.parent.mkdir(parents=True, exist_ok=True)
                text = (clone_dir / f).read_text(errors="replace")
                traits_needed |= set(app_traits.needed_in_text(text))
                dest.write_text(strip_imports(text, strip))
                mapping[str(dest.resolve())] = {"app": app["name"], "file": f, "base": t.get("base") or app["name"],
                                                **({"package": t["remote"].split("@")[0]} if t.get("remote") else {})}
            if not t["files"]:
                # A target with no Swift sources (an Objective-C or C package, whose only Swift
                # file was its manifest) still needs its folder, so the module exists for the
                # targets that import it.
                dest_root.mkdir(parents=True, exist_ok=True)
                (dest_root / "_NoSwiftSources.swift").write_text(
                    "// This target has no Swift sources in the app's repository.\n")
            resources = []
            for r in t["resources"]:
                src = clone_dir / t["source_root"] / r
                if src.exists():
                    dst = dest_root / r
                    if src.is_dir():
                        shutil.copytree(src, dst, dirs_exist_ok=True)
                    else:
                        dst.parent.mkdir(parents=True, exist_ok=True); shutil.copy2(src, dst)
                    resources.append(f'.process({json.dumps(r)})')
            # Core Data models go next to the sources, out of the target's files, and the
            # CoreDataModel plugin generates their classes (as Xcode's codegen does).
            models = []
            if t.get("models"):
                traits_needed.add("CoreData")
            for m in t.get("models", []):
                name = Path(m).name
                if name in models:
                    continue
                shutil.copytree(clone_dir / m, dest_root / name, dirs_exist_ok=True)
                models.append(name)
            kind = "executableTarget" if t.get("app") else "target"
            settings = [f".swiftLanguageMode(.{t['mode']})"] + t["settings"]
            extra = [json.dumps(d) for d in t["deps"]]
            if t.get("syntax"):
                uses_syntax = True
                extra += [f'.product(name: "{n}", package: "swift-syntax")' for n in t["syntax"]]
            # One typed array, not a chain of `+`: a long chain is more than the manifest's type
            # checker will take (IcySky's 32 targets).
            deps = f"web + ([{', '.join(extra)}] as [Target.Dependency])" if extra else "web"
            decls.append(
                f'        .{kind}(\n            name: "{t["module"]}",\n            dependencies: {deps},\n'
                f'            path: "Sources/{t["module"]}",\n'
                + (f'            exclude: [{", ".join(json.dumps(m) for m in models)}],\n' if models else "")
                + (f'            resources: [{", ".join(resources)}],\n' if resources else "")
                + f'            swiftSettings: [{", ".join(settings)}]'
                + (",\n            linkerSettings: stack" if t.get("app") else "")
                + (',\n            plugins: [.plugin(name: "CoreDataModel", package: "SwiftUIWeb")]' if models else "")
                + "\n        ),"
            )
    def traits_for(package):
        names = [t for t in app_traits.TRAITS if t in traits_needed and package in app_traits.TRAITS[t][1]]
        return f', traits: [{", ".join(json.dumps(t) for t in names)}]' if names else ""
    # The packages' macros build against the swift-syntax SwiftUIWeb already resolves.
    syntax_dependency = f'\n        .package(url: "{SYNTAX_PACKAGE}", from: "601.0.1"),' if uses_syntax else ""
    # Each target is its own statement: one `targets: [...]` literal holding every package's
    # targets is more than the manifest's type checker will take in reasonable time.
    head = MANIFEST_HEAD + """
var targets: [Target] = [
    .target(name: "SweepDeps", dependencies: web, path: "Sources/SweepDeps"),
]
"""
    tail = f"""
let package = Package(
    name: "Sweep",
    // Required as soon as any app target carries localized resources (.lproj, .xcstrings).
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "SwiftUIWeb", path: "{root}"{traits_for("SwiftUIWeb")}),
        .package(name: "UIKitWeb", path: "{root}/Packages/UIKitWeb"),
        .package(name: "Shadows", path: "{root}/Packages/Shadows"{traits_for("Shadows")}),{syntax_dependency}
    ],
    targets: targets
)
"""
    parts = {"head": head, "decls": decls, "tail": tail}
    manifest = render_manifest(parts)
    deps_dir = pkg / "Sources" / "SweepDeps"
    deps_dir.mkdir(parents=True, exist_ok=True)
    (deps_dir / "Deps.swift").write_text("".join(f"import {m}\n" for m in sorted(OURS - {"CoreLocation"})))
    (pkg / "Package.swift").write_text(manifest)
    (pkg / "mapping.json").write_text(json.dumps(mapping))
    (pkg / "strip.json").write_text(json.dumps(strips))
    (pkg / "manifest.json").write_text(json.dumps(parts))
    print(f"wrote {pkg / 'Package.swift'} ({len(decls)} targets, {len(mapping)} files"
          + "".join(f", {t} trait" for t in app_traits.TRAITS if t in traits_needed) + ")")


# MARK: run and classify

ERROR = re.compile(r"^(/[^:\n]+\.swift):(\d+):(\d+): error: (.+)$", re.MULTILINE)
NO_MODULE = re.compile(r"no such module '([^']+)'")


def normalize_type(t):
    t = re.sub(r"^(some|any)\s+", "", t.strip())
    t = re.sub(r"^(SwiftUI|SwiftUICore|UIKit|Foundation|Swift)\.", "", t)
    depth, out = 0, ""
    for ch in t:  # drop generic arguments
        if ch == "<":
            depth += 1
        elif ch == ">":
            depth -= 1
        elif depth == 0:
            out += ch
    out = out.rstrip("?!").replace(".Type", "")
    return out or t


def classify(msg):
    """(category, key) for one error message; the key is what the report counts across apps."""
    if m := NO_MODULE.search(msg):
        return "module", m.group(1)
    if m := re.match(r"cannot find type '([^']+)' in scope", msg):
        return "type", m.group(1)
    if m := re.match(r"cannot find '([^']+)' in scope", msg):
        return "name", m.group(1)
    if m := re.match(r"(?:value of type|type|static member|instance member) '(.+?)' (?:has no member|has no static member) '([^']+)'", msg):
        return "member", f"{normalize_type(m.group(1))}.{m.group(2)}"
    if m := re.match(r"reference to member '([^']+)' cannot be resolved", msg):
        return "member", f"?.{m.group(1)}"
    if m := re.match(r"unknown attribute '([^']+)'", msg):
        # A property wrapper or macro the app uses (@AppStorage, @FetchRequest): keep its name.
        return "attribute", f"@{m.group(1)}"
    if re.search(r"actor-isolated|Sendable|nonisolated|data race|concurrency|global actor|MainActor", msg):
        return "isolation", re.sub(r"'[^']*'", "'…'", msg)[:160]
    if m := re.search(r"'([^']+)' is (?:unavailable|only available)", msg):
        return "availability", m.group(1)
    if m := re.search(r"does not conform to protocol '([^']+)'", msg):
        return "conformance", m.group(1)
    if re.search(r"argument label|extra argument|missing argument|takes no arguments|no exact matches|cannot convert", msg):
        return "signature", re.sub(r"'[^']*'", "'…'", msg)[:160]
    return "other", re.sub(r"'[^']*'", "'…'", msg)[:160]


def topo(targets):
    order, seen = [], set()
    by = {t["module"]: t for t in targets}

    def visit(n, stack=()):
        if n in seen or n not in by or n in stack:
            return
        for d in by[n]["deps"]:
            visit(d, stack + (n,))
        seen.add(n); order.append(by[n])
    for t in targets:
        visit(t["module"])
    return order


def tokens_of(root: Path, files):
    words = set()
    for f in files:
        text = (root / f).read_text(errors="replace")
        text = re.sub(r"//[^\n]*", "", text)
        words.update(re.findall(r"\b[A-Za-z_]\w*\b", text))
    return sorted(words)


def rewrite_sources(mapping, work, app_name, strip):
    """Writes an app's copied sources again with a larger set of imports taken out."""
    for dest, where in mapping.items():
        if where["app"] == app_name:
            source = work / where.get("base", app_name) / where["file"]
            text = strip_imports(source.read_text(errors="replace"), strip)
            if Path(dest).read_text(errors="replace") != text:  # an unchanged file keeps its build
                Path(dest).write_text(text)


def cmd_run(args):
    plan = json.loads(Path(args.plan).read_text())
    pkg = Path(args.pkg).resolve()
    work = Path(args.work)
    logs = pkg / "logs"
    logs.mkdir(exist_ok=True)
    mapping = json.loads((pkg / "mapping.json").read_text())
    strips = json.loads((pkg / "strip.json").read_text())
    parts_file = pkg / "manifest.json"
    parts = json.loads(parts_file.read_text()) if parts_file.exists() else None
    drops = {}  # module -> the dependencies it is built without (package targets that failed)

    def build(target, timeout):
        cmd = ["swift", "build", "--package-path", str(pkg), "--scratch-path", str(pkg / ".build"),
               "--swift-sdk", args.sdk, "--target", target]
        try:
            r = subprocess.run(cmd, text=True, capture_output=True, timeout=timeout)
            out, code = r.stdout + r.stderr, r.returncode
        except subprocess.TimeoutExpired as e:
            out, code = (e.stdout or b"").decode(errors="replace") if isinstance(e.stdout, bytes) else (e.stdout or ""), "timeout"
        (logs / f"{target}.log").write_text(out)
        return code, out

    code, out = build("SweepDeps", 5400)
    results = {"batch": args.batch, "deps": "ok" if code == 0 else "failed", "apps": []}
    if code != 0:
        results["deps_log"] = out[-6000:]
        Path(args.out).write_text(json.dumps(results, indent=1))
        print(out[-6000:]); sys.exit(1)
    built = {}
    for app in plan["apps"]:
        if app.get("batch") != args.batch:
            continue
        status, failed = [], set()
        # Macro targets build for the host as their users' dependencies, not on their own.
        for t in topo([t for t in app["targets"] if not t.get("skip") and not t.get("macro")]):
            blocked = [d for d in t["deps"] if d in failed]
            if t["module"] in built:
                # A package target another app of the batch built already: the same result.
                status.append({**built[t["module"]], "errors": []})
                if built[t["module"]]["status"] != "ok":
                    failed.add(t["module"])
                continue
            if blocked and not parts:
                status.append({"module": t["module"], "status": "blocked", "by": blocked, "errors": []})
                failed.add(t["module"]); continue
            if blocked:
                # A package it uses did not build: build it without that package, its imports
                # taken out as the sweep takes out any module that does not exist on wasm, so its
                # own errors still count (an app is never hidden behind a package's failure).
                drops[t["module"]] = sorted(set(drops.get(t["module"], [])) | set(blocked))
                (pkg / "Package.swift").write_text(render_manifest(parts, drops))
                strips[app["name"]] = sorted(set(strips[app["name"]]) | set(blocked))
                rewrite_sources(mapping, work, app["name"], set(strips[app["name"]]))
            code, out = build(t["module"], 2400)
            # A module the wasm SDK turns out not to have (or not to show to this target) is
            # taken out like the others and the target built again, once.
            absent = set(NO_MODULE.findall(out)) - set(strips[app["name"]])
            if code != 0 and absent:
                strips[app["name"]] = sorted(set(strips[app["name"]]) | absent)
                rewrite_sources(mapping, work, app["name"], set(strips[app["name"]]))
                code, out = build(t["module"], 2400)
            errors, seen = [], set()
            for path, line, col, msg in ERROR.findall(out):
                where = mapping.get(str(Path(path).resolve()))
                if not where or where["app"] != app["name"]:
                    continue  # a dependency's error is SwiftUIWeb's own, reported by its CI
                k = (where["file"], line, col, msg)
                if k in seen:
                    continue
                seen.add(k)
                cat, key = classify(msg)
                shown = f"[{where['package']}] {where['file']}" if where.get("package") else where["file"]
                errors.append({"file": shown, "line": int(line), "msg": msg, "category": cat, "key": key,
                               **({"package": where["package"]} if where.get("package") else {})})
            ok = code == 0
            if not ok:
                failed.add(t["module"])
            status.append({"module": t["module"], "status": "ok" if ok else ("timeout" if code == "timeout" else "errors"),
                           "errors": errors, "tail": "" if ok or errors else out[-3000:],
                           **({"without": blocked} if blocked else {})})
            if t.get("remote"):
                status[-1]["package"] = t["remote"]
                built[t["module"]] = {k: v for k, v in status[-1].items() if k != "errors"}
            print(f"{app['name']} {t['module']}: {status[-1]['status']} ({len(errors)} errors)")
        files = [f for t in app["targets"] if not t.get("skip") and not t.get("remote") for f in t["files"]]
        results["apps"].append({
            **{k: app.get(k) for k in ("name", "repo", "sha", "control", "missing_imports", "asset_names",
                                       "model_entities", "os_condition_files", "files", "notes")},
            "stripped": strips[app["name"]],
            "modes": sorted({t["mode"] for t in app["targets"] if not t.get("skip") and not t.get("remote")}),
            "packages": app.get("packages", []),
            "third_party": sorted({d for t in app["targets"] for d in t["third_party"]}),
            "targets": status,
            "tokens": tokens_of(work / app["name"], files),
        })
    Path(args.out).write_text(json.dumps(results, indent=1))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("plan"); p.add_argument("--corpus", required=True); p.add_argument("--work", required=True)
    p.add_argument("--batch-size", type=int, default=6); p.add_argument("-o", "--out", required=True)
    p = sub.add_parser("fetch"); p.add_argument("--plan", required=True); p.add_argument("--work", required=True)
    p.add_argument("--batch", type=int, required=True)
    p = sub.add_parser("prepare"); p.add_argument("--plan", required=True); p.add_argument("--work", required=True)
    p.add_argument("--batch", type=int, required=True); p.add_argument("--root", required=True)
    p.add_argument("--strip"); p.add_argument("-o", "--out", required=True)
    p.add_argument("--all-traits", action="store_true", help="enable every package trait (the surface build)")
    p = sub.add_parser("run"); p.add_argument("--plan", required=True); p.add_argument("--work", required=True)
    p.add_argument("--pkg", required=True); p.add_argument("--batch", type=int, required=True)
    p.add_argument("--sdk", required=True); p.add_argument("-o", "--out", required=True)
    args = ap.parse_args()
    {"plan": cmd_plan, "fetch": cmd_fetch, "prepare": cmd_prepare, "run": cmd_run}[args.cmd](args)


if __name__ == "__main__":
    main()
