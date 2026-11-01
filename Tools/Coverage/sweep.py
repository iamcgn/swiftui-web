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


# MARK: plan

def module_names(app):
    return {t["module"] for t in app["targets"]}


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
    return found


def describe_app(entry, root: Path):
    """The sweep's view of one clone: its local targets, the app target's files, the imports."""
    extra = entry.get("exclude", [])
    packages = read_local_packages(root, extra)
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
    # The app target: every Swift file outside the local packages and the excluded folders.
    app_files = []
    for f in sorted(root.rglob("*.swift")):
        rel = f.relative_to(root)
        if is_manifest(rel.name):
            continue
        if excluded(rel, extra) or any(rel.is_relative_to(d) for d in pkg_dirs if str(d) != "."):
            continue
        if Path(".") in pkg_dirs and any(rel.is_relative_to(Path(t["source_root"])) for t in targets):
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
    executable_locals = [t for t in targets if t["executable"]]
    if not app_files and executable_locals:
        executable_locals[0]["app"] = True
    elif app_files:
        models = [m for m in data_models(root, Path(".")) if not excluded(Path(m), extra)
                  and not any(Path(m).is_relative_to(d) for d in pkg_dirs if str(d) != ".")
                  and not any(Path(m).is_relative_to(Path(t["source_root"])) for t in targets)]
        targets.append({
            "module": "Sweep" + re.sub(r"\W", "", entry["name"]), "source_root": ".", "files": app_files,
            "deps": sorted({t["module"] for t in targets if not t["executable"]}), "third_party": [],
            "mode": xcode_language_mode(root), "settings": [], "resources": [], "models": models,
            "executable": True, "app": True,
        })
    for t in targets:
        if t["executable"] and not t.get("app"):
            t["skip"] = True
            notes.append(f"executable target {t['module']} is not the app; not built")
    # Imports, per target, of modules that are neither ours, the SDK's nor local (a target named
    # with a hyphen is imported with an underscore).
    local = {t["module"] for t in targets} | {t["module"].replace("-", "_") for t in targets}
    imports = Counter()
    for t in targets:
        for f in t["files"]:
            for line in (root / f).read_text(errors="replace").splitlines():
                m = IMPORT.match(line)
                if m:
                    imports[m.group(3)] += 1
    missing = sorted(m for m in imports if m not in OURS | STDLIB | local)
    asset_names = sorted({p.stem for p in root.rglob("*.colorset")} | {p.stem for p in root.rglob("*.imageset")}
                         | {p.stem for p in root.rglob("*.symbolset")})
    model_entities = sorted(set(re.findall(r'<entity name="([^"]+)"', "\n".join(
        c.read_text(errors="replace") for c in root.rglob("contents") if ".xcdatamodel" in str(c)))))
    os_conditions = sum(1 for t in targets for f in t["files"]
                        if re.search(r"#(?:else)?if\b[^\n]*\bos\((?:iOS|macOS|watchOS|tvOS|visionOS)\)", (root / f).read_text(errors="replace")))
    return {
        "targets": targets, "notes": notes, "missing_imports": missing,
        "asset_names": asset_names, "model_entities": model_entities, "os_condition_files": os_conditions,
        "files": sum(len(t["files"]) for t in targets if not t.get("skip")),
    }


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
        info = describe_app(entry, dest)
        apps.append({**entry, "sha": sha, **info})
        print(f"{entry['name']}: {sha[:10]} {info['files']} files, {len(info['targets'])} targets, missing imports {info['missing_imports']}")
    # Batches: no module name twice in one sweep package.
    batches = []
    for app in apps:
        if not app.get("sha"):
            app["batch"] = None
            continue
        names = module_names(app)
        for i, b in enumerate(batches):
            if len(b["apps"]) < args.batch_size and not (b["modules"] & names):
                b["apps"].append(app["name"]); b["modules"] |= names; app["batch"] = i
                break
        else:
            batches.append({"apps": [app["name"]], "modules": set(names)}); app["batch"] = len(batches) - 1
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
    for app in plan["apps"]:
        if app.get("batch") != args.batch:
            continue
        clone_dir = work / app["name"]
        local = {t["module"] for t in app["targets"]} | {t["module"].replace("-", "_") for t in app["targets"]}
        strip = (set(app["missing_imports"]) | set(strip_extra.get(app["name"], []))) - local
        strips[app["name"]] = sorted(strip)
        for t in app["targets"]:
            if t.get("skip"):
                continue
            dest_root = pkg / "Sources" / t["module"]
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
                mapping[str(dest.resolve())] = {"app": app["name"], "file": f}
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
            deps = "web" + "".join(f' + ["{d}"]' for d in t["deps"])
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
    manifest = MANIFEST_HEAD + f"""
let package = Package(
    name: "Sweep",
    // Required as soon as any app target carries localized resources (.lproj, .xcstrings).
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "SwiftUIWeb", path: "{root}"{traits_for("SwiftUIWeb")}),
        .package(name: "UIKitWeb", path: "{root}/Packages/UIKitWeb"),
        .package(name: "Shadows", path: "{root}/Packages/Shadows"{traits_for("Shadows")}),
    ],
    targets: [
        .target(name: "SweepDeps", dependencies: web, path: "Sources/SweepDeps"),
{chr(10).join(decls)}
    ]
)
"""
    deps_dir = pkg / "Sources" / "SweepDeps"
    deps_dir.mkdir(parents=True, exist_ok=True)
    (deps_dir / "Deps.swift").write_text("".join(f"import {m}\n" for m in sorted(OURS - {"CoreLocation"})))
    (pkg / "Package.swift").write_text(manifest)
    (pkg / "mapping.json").write_text(json.dumps(mapping))
    (pkg / "strip.json").write_text(json.dumps(strips))
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
            Path(dest).write_text(strip_imports((work / app_name / where["file"]).read_text(errors="replace"), strip))


def cmd_run(args):
    plan = json.loads(Path(args.plan).read_text())
    pkg = Path(args.pkg).resolve()
    work = Path(args.work)
    logs = pkg / "logs"
    logs.mkdir(exist_ok=True)
    mapping = json.loads((pkg / "mapping.json").read_text())
    strips = json.loads((pkg / "strip.json").read_text())

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
    for app in plan["apps"]:
        if app.get("batch") != args.batch:
            continue
        status, failed = [], set()
        for t in topo([t for t in app["targets"] if not t.get("skip")]):
            blocked = [d for d in t["deps"] if d in failed]
            if blocked:
                status.append({"module": t["module"], "status": "blocked", "by": blocked, "errors": []})
                failed.add(t["module"]); continue
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
                errors.append({"file": where["file"], "line": int(line), "msg": msg, "category": cat, "key": key})
            ok = code == 0
            if not ok:
                failed.add(t["module"])
            status.append({"module": t["module"], "status": "ok" if ok else ("timeout" if code == "timeout" else "errors"),
                           "errors": errors, "tail": "" if ok or errors else out[-3000:]})
            print(f"{app['name']} {t['module']}: {status[-1]['status']} ({len(errors)} errors)")
        files = [f for t in app["targets"] if not t.get("skip") for f in t["files"]]
        results["apps"].append({
            **{k: app.get(k) for k in ("name", "repo", "sha", "control", "missing_imports", "asset_names",
                                       "model_entities", "os_condition_files", "files", "notes")},
            "stripped": strips[app["name"]],
            "modes": sorted({t["mode"] for t in app["targets"] if not t.get("skip")}),
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
