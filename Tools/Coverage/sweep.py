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
    "CoreLocation", "AVFoundation", "AVFAudio", "AVKit", "Speech", "SwiftData", "UserNotifications", "WebKit",
    "os", "OSLog", "CoreGraphics", "UniformTypeIdentifiers", "CoreData", "CryptoKit", "CoreHaptics", "CoreImage", "WidgetKit", "StoreKit", "AppIntents", "Intents", "IntentsUI",
    "Dispatch", "CoreFoundation", "ImageIO", "MobileCoreServices", "SystemConfiguration",
    "LocalAuthentication", "FoundationNetworking", "FoundationXML", "CommonCrypto", "AudioToolbox", "EventKit", "EventKitUI", "Contacts",
    "Network", "Photos", "PhotosUI", "AuthenticationServices", "CoreMotion", "ActivityKit", "BackgroundTasks", "TipKit", "Symbols", "Compression", "zlib", "Translation", "_Translation_SwiftUI", "JavaScriptCore",
    "CoreText", "CloudKit", "Accelerate", "PDFKit", "CoreSpotlight", "NaturalLanguage", "QuickLook", "LinkPresentation", "WeatherKit", "MediaPlayer", "CoreTelephony", "WatchConnectivity", "GameKit", "XCTest",
    "SceneKit",
}
# `Builtin` is the compiler's own module (swift-collections imports it with the BuiltinModule
# feature). `XCTest` is the shadow's (Packages/Shadows): the wasm SDK's own can't be read beside
# SwiftUIWeb's Foundation, and packages import it on wasm where Apple's platforms look it up at
# run time (swift-dependencies' test observer, xctest-dynamic-overlay's `XCTFail`). `SwiftShims` is
# the standard library's C declarations, in every SDK: swift-collections 1.7.6 imports it for
# `_swift_stdlib_immortalize`, and stripping it failed InternalCollectionsUtilities and every
# collection module above it (Thunderbird, OnlineStoreTCA, EhPanda).
STDLIB = {"Swift", "_Concurrency", "_StringProcessing", "Observation", "Synchronization", "RegexBuilder", "WASILibc",
          "Builtin", "SwiftShims"}
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


AUTO_RESOURCE_SUFFIXES = (".xcstrings", ".lproj", ".xcassets", ".storyboard", ".xib")


def files_under(root, suffix=""):
    """The files under `root` ending in `suffix`, sorted, into symlinked folders too: SwiftPM reads
    a target's sources through them (swift-issue-reporting 2 links its package-support types into
    IssueReporting from a "Symbolic Links" folder), and `Path.rglob` does not follow them. A folder
    reached twice (a link back up the tree) is read once."""
    found, seen = [], set()
    for folder, subfolders, names in os.walk(root, followlinks=True):
        real = os.path.realpath(folder)
        if real in seen:
            subfolders[:] = []
            continue
        seen.add(real)
        found += [Path(folder) / n for n in names if n.endswith(suffix)]
    return sorted(found)


def auto_resources(source_root):
    """The resources SwiftPM picks up in a target's folder by their type, outermost only."""
    found = []
    if not source_root.is_dir():
        return found
    for path in sorted(source_root.rglob("*")):
        rel = path.relative_to(source_root)
        if any(EXCLUDE_DIR.match(part.lower()) for part in rel.parts[:-1]):
            continue
        if any(part.endswith(AUTO_RESOURCE_SUFFIXES) for part in rel.parts[:-1]):
            continue  # inside a resource already taken whole
        if path.name.endswith(AUTO_RESOURCE_SUFFIXES):
            found.append(str(rel))
    return found


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
    init_submodules(dest)
    return sh(["git", "rev-parse", "HEAD"], cwd=dest).stdout.strip()


# Submodules on GitHub, fetched over https whatever form .gitmodules gives (ssh needs a key).
SUBMODULE_URLS = ["-c", "url.https://github.com/.insteadOf=git@github.com:",
                  "-c", "url.https://github.com/.insteadOf=ssh://git@github.com/"]


def init_submodules(dest):
    """Check out the clone's submodules at their recorded commits, as Xcode and SwiftPM see them.

    An app that keeps a package in a submodule (Harbour's Modules/PortainerKit) otherwise builds
    without it, and every use of the package counts as an error. A submodule that can't be
    fetched (private, gone) stays empty, which is what the sweep saw before."""
    if not (dest / ".gitmodules").exists():
        return
    base = ["git", *SUBMODULE_URLS, "submodule", "update", "--init", "--recursive"]
    r = sh(base + ["--depth", "1"], cwd=dest, check=False, timeout=900)
    if r.returncode != 0:
        # A recorded commit that isn't a branch tip may need the whole history.
        r = sh(base, cwd=dest, check=False, timeout=1800)
    if r.returncode != 0:
        print(f"submodules of {dest.name}: {(r.stderr or r.stdout).strip().splitlines()[-1:]}")


def is_manifest(name: str) -> bool:
    """Whether a file name is a SwiftPM manifest (`Package.swift`, `Package@swift-5.9.swift`)."""
    return name == "Package.swift" or name.startswith("Package@swift")


def in_target_exclude(rel: Path, excludes):
    """Whether SwiftPM leaves a file out of a target: a hidden file or folder on its path, or a
    path at or under one of the target's `exclude` entries, each relative to the target's folder
    (`"Helper.swift"` leaves out the target's own `Helper.swift`, not `Snapshot/Helper.swift`)."""
    if any(part.startswith(".") for part in rel.parts):
        return True
    return any(rel == e or e in rel.parents for e in excludes)


def excluded(rel: Path, extra):
    parts = rel.parts[:-1]
    if any(EXCLUDE_DIR.match(p) for p in parts):
        return True
    return excluded_by_entry(rel, extra)


def excluded_by_entry(rel: Path, extra):
    """Whether the corpus entry's own `exclude` list leaves the path out."""
    return any(str(rel).startswith(e.rstrip("/") + "/") or str(rel) == e for e in extra)


# MARK: local packages

_DUMPS = {}


def dump_package(pkg_dir: Path):
    """dump-package's JSON of a package, once per folder (the plan reads a cloned package's
    manifest both to find what it depends on and to describe its targets)."""
    key = str(Path(pkg_dir).resolve())
    if key not in _DUMPS:
        _DUMPS[key] = _dump_package(pkg_dir)
    return _DUMPS[key]


def _dump_package(pkg_dir: Path):
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


def default_traits(dump):
    """The traits a package turns on by default, and the traits those turn on. SwiftPM defines
    each enabled trait's name for the package's own targets (`#if Perception`), and builds the
    dependencies and settings conditioned on it; the sweep, which flattens every package into one,
    does the same for the default set (swift-navigation's Perception and CustomDump)."""
    traits = {t.get("name"): t for t in dump.get("traits") or [] if isinstance(t, dict)}
    enabled, todo = set(), list((traits.get("default") or {}).get("enabledTraits") or [])
    while todo:
        name = todo.pop()
        if name in enabled or name == "default":
            continue
        enabled.add(name)
        todo.extend((traits.get(name) or {}).get("enabledTraits") or [])
    return enabled


def condition_allows_traits(condition, traits):
    """Whether a setting's or a dependency's condition holds for the enabled traits: none named,
    or one of those it names on."""
    named = condition.get("traits") if isinstance(condition, dict) else None
    return not named or bool(set(named) & set(traits))


# `.defaultIsolation(MainActor.self)` (tools 6.2) as a flag, since the sweep's manifest is 6.1:
# the target's unannotated declarations are main-actor isolated, as in IceCubes's packages.
DEFAULT_MAIN_ACTOR = '.unsafeFlags(["-default-isolation", "MainActor"])'


def default_isolation_is_main_actor(value):
    """Whether a dumped `defaultIsolation` setting is MainActor (`{"_0": "MainActor"}`, or the
    bare value), not `nil`/nonisolated."""
    if isinstance(value, dict):
        value = value.get("_0", next(iter(value), None) if value else None)
    return isinstance(value, str) and value.lower() == "mainactor"


def swift_settings(target, traits=frozenset()):
    """The defines and upcoming features a target declares, as manifest source: the package's
    enabled traits as defines first, then the settings with no condition or a trait condition
    that holds."""
    out = [f".define({json.dumps(t)})" for t in sorted(traits)]
    for s in target.get("settings") or []:
        cond = s.get("condition")
        named = {k for k, v in (cond or {}).items() if v}
        if s.get("tool") != "swift" or named - {"traits"} or not condition_allows_traits(cond, traits):
            continue
        kind = s.get("kind") or {}
        if "defaultIsolation" in kind and default_isolation_is_main_actor(kind["defaultIsolation"]):
            out.append(DEFAULT_MAIN_ACTOR)
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


QUOTED_INCLUDE = re.compile(r'^[ \t]*#[ \t]*include[ \t]*"([^"\n]+/[^"\n]+)"', re.M)


WASI_POSIX_COMPAT = Path(__file__).resolve().parent / "wasi-posix-compat.h"
# The calls wasi-posix-compat.h stands in for, each with what marks a package's own declaration.
WASI_MISSING_CALLS = {"dup": re.compile(r'\bint[ \t]+dup[ \t]*\(')}


def wasi_missing_calls(root: Path):
    """The POSIX calls wasi-libc lacks that a C target's sources make without declaring them
    (Runestone's vendored tree-sitter calls `dup`), which wasi-posix-compat.h supplies."""
    found = set()
    for f in files_under(root):
        if not (f.is_file() and f.suffix in C_SOURCES | C_HEADERS):
            continue
        try:
            text = f.read_text(errors="replace")
        except OSError:
            continue
        for name, declared in WASI_MISSING_CALLS.items():
            if declared.search(text):
                return set()
            if re.search(rf'(?<![A-Za-z0-9_.>]){name}[ \t]*\(', text):
                found.add(name)
    return found


def vendored_quote_dirs(root: Path, public_headers: str, settings):
    """Folders of a C target that hold a header its own quoted includes name but cannot reach.

    Apple's SDKs ship some C libraries' headers (ICU's unicode/umachine.h, for one), so a
    vendored C library can write `#include "unicode/umachine.h"` from inside its own
    unicode folder and still build in Xcode, where the include falls through to the SDK.
    The wasm SDK has no such headers, so the build stops though the package carries its
    own copy. Each such folder goes on the quote path only (-iquote), so angle includes
    and the system headers stay as they are."""
    search = [root / public_headers]
    for entry in settings:
        m = re.match(r'\.headerSearchPath\((".*")\)$', entry)
        if m:
            search.append(root / json.loads(m.group(1)))
    files = [f for f in files_under(root) if f.is_file() and f.suffix in C_SOURCES | C_HEADERS]
    dirs = []
    for f in files:
        try:
            text = f.read_text(errors="replace")
        except OSError:
            continue
        for inc in QUOTED_INCLUDE.findall(text):
            if (f.parent / inc).exists() or any((d / inc).exists() for d in search + dirs):
                continue
            for h in files:
                if h.as_posix().endswith("/" + inc):
                    base = Path(h.as_posix()[: -len(inc) - 1])
                    if base not in dirs and (base / inc).is_file():
                        dirs.append(base)
                        break
    return dirs


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


# An app that keeps no Package.resolved (Thunderbird's local package asks for swift-nio's `main`;
# Gem's and OnlineStoreTCA's Xcode projects leave theirs out of git) still names its packages and
# the versions it takes: in each local Package.swift and in the project's package references.
# Those it names with no pin are resolved the way Xcode would resolve them that day (a branch's
# head, the newest release tag in range), and so are the packages those name in turn, so the
# sweep builds them from source instead of counting every use as an error. The plan job resolves
# them once, so every shard of a sweep builds the same revisions.

SEMVER = re.compile(r"^v?(\d+)\.(\d+)(?:\.(\d+))?$")
_REFS = {}


def version_tuple(text):
    m = SEMVER.match(str(text or "").strip())
    return (int(m.group(1)), int(m.group(2)), int(m.group(3) or 0)) if m else None


def remote_refs(repo):
    """{"heads": {branch: sha}, "tags": {version: sha}} of a public GitHub repository."""
    if repo not in _REFS:
        refs = {"heads": {}, "tags": {}}
        r = sh(["git", "ls-remote", "--heads", "--tags", f"https://github.com/{repo}.git"],
               check=False, timeout=120)
        peeled = {}
        for line in r.stdout.splitlines() if r.returncode == 0 else []:
            sha, _, ref = line.partition("\t")
            if ref.startswith("refs/heads/"):
                refs["heads"][ref[len("refs/heads/"):]] = sha
            elif ref.startswith("refs/tags/"):
                name = ref[len("refs/tags/"):]
                if name.endswith("^{}"):
                    peeled[name[:-3]] = sha
                elif version_tuple(name):
                    refs["tags"].setdefault(version_tuple(name), (name, sha))
        refs["tags"] = {v: peeled.get(name, sha) for v, (name, sha) in refs["tags"].items()}
        _REFS[repo] = refs
    return _REFS[repo]


def resolve_requirement(repo, req):
    """The commit a requirement picks: ("branch", name), ("revision", sha), ("exact", version) or
    ("range", lower, upper) with `upper` excluded; None when nothing matches."""
    if req[0] == "revision":
        return req[1] if re.fullmatch(r"[0-9a-f]{40}", req[1] or "") else None
    refs = remote_refs(repo)
    if req[0] == "branch":
        return refs["heads"].get(req[1])
    if req[0] == "exact":
        return refs["tags"].get(version_tuple(req[1]))
    lower, upper = version_tuple(req[1]), version_tuple(req[2]) if req[2] else None
    found = [v for v in refs["tags"] if lower and v >= lower and (upper is None or v < upper)]
    return refs["tags"][max(found)] if found else None


def manifest_requirement(req):
    """A dump-package dependency requirement in resolve_requirement's form."""
    for kind in ("branch", "revision", "exact"):
        if kind in req:
            v = req[kind]
            return (kind, v[0] if isinstance(v, list) else v)
    if "range" in req:
        r = req["range"][0] if isinstance(req["range"], list) else req["range"]
        return ("range", r.get("lowerBound"), r.get("upperBound"))
    return None


def manifest_dependencies(dump):
    """[(identity, url, requirement)] of a dump-package's source-control dependencies."""
    out = []
    for d in (dump or {}).get("dependencies") or []:
        for entry in d.get("sourceControl") or []:
            remote = ((entry.get("location") or {}).get("remote") or [None])[0]
            url = remote.get("urlString") if isinstance(remote, dict) else remote
            req = manifest_requirement(entry.get("requirement") or {})
            if url and req:
                out.append(((entry.get("identity") or "").lower(), url, req))
    return out


def used_dependencies(dump):
    """manifest_dependencies of a package, only the ones a target's iOS dependency names under
    the package's default traits: a package an Apple-only or off trait asks for is not built."""
    traits = default_traits(dump or {})
    used = set()
    for t in (dump or {}).get("targets") or []:
        if t.get("type") not in ("regular", "executable", "macro"):
            continue  # a test target's packages are not built
        for d in t.get("dependencies") or []:
            kind, _, package = dependency_names(d)
            if kind == "product" and package and condition_allows_ios(d, traits):
                used.add(package.lower())
    return [d for d in manifest_dependencies(dump) if d[0] in used]


def project_requirement(req):
    """An Xcode XCRemoteSwiftPackageReference requirement in resolve_requirement's form."""
    kind = req.get("kind")
    if kind == "branch":
        return ("branch", req.get("branch"))
    if kind == "revision":
        return ("revision", req.get("revision"))
    if kind == "exactVersion":
        return ("exact", req.get("version"))
    low = version_tuple(req.get("minimumVersion"))
    if not low:
        return None
    if kind == "upToNextMajorVersion":
        return ("range", req["minimumVersion"], f"{low[0] + 1}.0.0")
    if kind == "upToNextMinorVersion":
        return ("range", req["minimumVersion"], f"{low[0]}.{low[1] + 1}.0")
    if kind == "versionRange":
        return ("range", req["minimumVersion"], req.get("maximumVersion"))
    return None


def project_dependencies(root: Path, extra):
    """[(identity, url, requirement)] of the package references in the clone's Xcode projects."""
    out = []
    for pbx in sorted(root.rglob("project.pbxproj")):
        rel = pbx.relative_to(root)
        if excluded(rel, extra):
            continue
        try:
            objects = xcodeproj.parse(pbx.read_text(errors="replace")).get("objects") or {}
        except (AssertionError, ValueError, IndexError):
            continue
        for obj in objects.values():
            if isinstance(obj, dict) and obj.get("isa") == "XCRemoteSwiftPackageReference":
                url, req = obj.get("repositoryURL"), project_requirement(obj.get("requirement") or {})
                if url and req:
                    out.append(("", url, req))
    return out


def requirement_allows(version, req):
    """Whether a release version satisfies an exact or range requirement."""
    if req[0] == "exact":
        return version == version_tuple(req[1])
    if req[0] == "range":
        lower, upper = version_tuple(req[1]), version_tuple(req[2]) if req[2] else None
        return bool(lower) and version >= lower and (upper is None or version < upper)
    return False


def resolve_requirements(repo, reqs, excluded=()):
    """The commit that every requirement on one package allows, as SwiftPM picks it: a branch or
    revision when one is asked for (the first, the root's before its packages'), else the newest
    release, other than the `excluded` commits, that every version requirement allows; None when
    nothing does."""
    fixed = [r for r in reqs if r[0] in ("branch", "revision")]
    if fixed:
        return resolve_requirement(repo, fixed[0])
    tags = remote_refs(repo)["tags"]
    allowed = [v for v in tags if tags[v] not in excluded and all(requirement_allows(v, r) for r in reqs)]
    return tags[max(allowed)] if allowed else None


def declared_pins(work: Path, root: Path, extra, packages, pins, notes, passes=20, backtracks=8):
    """`pins` with every package the app's manifests and projects name but no Package.resolved
    pins, resolved, and the packages those name in turn. Each package takes a commit that all the
    requirements on it allow: a requirement found later (a dependency's exact version under the
    app's wider range) moves the pick, and the moved package's own requirements replace those of
    its earlier pick, until no pick moves. When nothing satisfies a package's requirements and
    leaving out one picked package's requirements would, that package goes back to an older
    release (at most `backtracks` times), as SwiftPM would try before giving up."""
    pins = dict(pins)
    resolved_repos = {p["repo"].lower() for p in pins.values()}
    wanted = {}  # repo (lower) -> {"identity", "url", "repo", "by": {source: [requirement]}}

    def want(source, deps):
        for identity, url, req in deps:
            repo = github_repo(url)
            if not repo or repo.lower() in resolved_repos:
                continue
            entry = wanted.setdefault(repo.lower(), {"identity": identity or repo.split("/")[1].lower().removesuffix(".git"),
                                                       "url": url, "repo": repo, "by": {}})
            entry["by"].setdefault(source, []).append(req)

    want("", [d for p in packages for d in manifest_dependencies(p["dump"])] + project_dependencies(root, extra))
    # A pinned package's own dependencies: Package.resolved leaves out what a trait the Apple
    # build doesn't enable uses (SQLite.swift's embedded SQLite, which the sweep's Linux-hosted
    # manifest turns on), so the ones its enabled targets use are resolved like the root's.
    pinned = fetch_packages(work, pins)
    for identity, key in sorted(pinned.items()):
        dump, _ = dump_package(work / PACKAGES_DIR / key)
        want(f"pin:{identity}", used_dependencies(dump))
    picked = {}  # repo (lower) -> commit or None
    excluded = {}  # repo (lower) -> commits a conflict ruled out

    def blame(entry):
        """A picked package whose requirements alone keep `entry` from resolving and that has
        another release its own requirements allow, ruled out at its current pick; whether there
        was one."""
        for source in entry["by"]:
            if not source or not picked.get(source):
                continue  # the root's own requirements, or a package nothing satisfied either
            if any(r[0] in ("branch", "revision") for reqs in wanted[source]["by"].values() for r in reqs):
                continue  # on a branch or revision, so no older release to try
            rest = [r for other in entry["by"] if other != source for r in entry["by"][other]]
            if not resolve_requirements(entry["repo"], rest):
                continue
            ruled_out = excluded.get(source, set()) | {picked[source]}
            own = [r for reqs in wanted[source]["by"].values() for r in reqs]
            if resolve_requirements(wanted[source]["repo"], own, ruled_out):  # an older one to try
                excluded[source] = ruled_out
                return True
        return False

    for _ in range(passes):
        moved = False
        for key, entry in list(wanted.items()):
            identity = entry["identity"]
            if identity in pins and key not in picked:
                continue  # Package.resolved pins one of that name
            reqs = [r for source in entry["by"] for r in entry["by"][source]]
            if not reqs:
                if key in picked:
                    # Only an earlier pick asked for it: drop it, and what its own pick asked for.
                    moved = True
                    del picked[key]
                    pins.pop(identity, None)
                    for other in wanted.values():
                        other["by"].pop(key, None)
                continue
            revision = resolve_requirements(entry["repo"], reqs, excluded.get(key, ()))
            if not revision and backtracks and blame(entry):
                backtracks -= 1
                moved = True
                continue  # the blamed package moves to an older release first
            if key in picked and picked[key] == revision:
                continue
            moved = True
            picked[key] = revision
            for other in wanted.values():
                other["by"].pop(key, None)  # what the earlier pick asked for no longer holds
            if not revision:
                pins.pop(identity, None)
                continue
            pins[identity] = {"url": entry["url"], "repo": entry["repo"], "revision": revision, "declared": reqs}
            keys = fetch_packages(work, {identity: pins[identity]})
            if identity in keys:
                dump, _ = dump_package(work / PACKAGES_DIR / keys[identity])
                want(key, manifest_dependencies(dump))
        if not moved:
            break
    else:
        notes.append(f"packages: no stable resolution after {passes} passes; the last picks are built")
    for key, revision in picked.items():
        entry = wanted[key]
        reqs = [r for source in entry["by"] for r in entry["by"][source]]
        if not reqs:
            pins.pop(entry["identity"], None)  # left over when the passes ran out
            continue
        if revision:
            notes.append(f"package {entry['identity']}: no Package.resolved pin; {reqs} resolve to {revision[:12]}")
        else:
            notes.append(f"package {entry['identity']}: nothing in {entry['repo']} satisfies all of {reqs}, not built")
    return pins


def dependency_traits_hold(dep, traits):
    """Whether a dump-package dependency's trait condition, if any, holds for `traits`."""
    parts = (dep.get("product") or dep.get("byName") or dep.get("target") or [])[1:]
    return all(condition_allows_traits(part, traits) for part in parts if isinstance(part, dict))


def condition_allows_ios(dep, traits=None):
    """Whether a dump-package dependency's platform condition (if any) includes iOS, and its
    trait condition (if any, and when the package's enabled traits are given) holds."""
    if traits is not None and not dependency_traits_hold(dep, traits):
        return False
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
        traits = default_traits(dump)
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
            files = [str(f.relative_to(root)) for f in files_under(src, ".swift")
                     if f.is_file() and not any(str(f.relative_to(root)).startswith(e.rstrip("/") + "/") or str(f.relative_to(root)) == e for e in excludes)
                     and not (f.parent == root and is_manifest(f.name))]
            c_kind = None
            if not files:
                found = [f for f in files_under(src) if f.is_file()]
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
                if not condition_allows_ios(d, traits):
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
                "third_party": [], "mode": language_mode_of_package(dump, t), "settings": swift_settings(t, traits),
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


def asset_catalogs(root: Path, base: Path):
    """The asset catalogs (`.xcassets`) under a folder, as paths relative to the clone, for the
    AssetSymbols plugin."""
    found = []
    for d in sorted((root / base).rglob("*.xcassets")):
        if not d.is_dir() or any(p.suffix == ".xcassets" for p in d.relative_to(root / base).parents if p != Path(".")):
            continue
        if any(EXCLUDE_DIR.match(x) for x in d.relative_to(root / base).parts[:-1]):
            continue
        found.append(str(d.relative_to(root)))
    return found


POD_MODULE = re.compile(r"^\s*framework\s+module\s+([A-Za-z_]\w*)", re.MULTILINE)


def checked_in_pods(root: Path):
    """The CocoaPods a repository keeps checked in (`Pods/<pod>` beside its `Target Support
    Files`), as local targets: Xcode builds each pod's sources as a framework module named by its
    module map (R.swift.Library is `Rswift`). Pods with no Swift sources (tools such as SwiftLint
    or R.swift's generator, shipped as binaries) and Objective-C pods are left out."""
    pods = []
    for support in sorted(root.rglob("Target Support Files")):
        rel = support.relative_to(root)
        if support.parent.name != "Pods" or any(x in (".build", ".git") for x in rel.parts):
            continue
        for d in sorted(p for p in support.iterdir() if p.is_dir() and not p.name.startswith("Pods-")):
            src = support.parent / d.name
            if not src.is_dir():
                continue
            module = None
            for mm in sorted(d.glob("*.modulemap")):
                m = POD_MODULE.search(mm.read_text(errors="replace"))
                if m:
                    module = m.group(1)
                    break
            module = module or re.sub(r"\W", "_", d.name)
            files = [str(f.relative_to(root)) for f in files_under(src, ".swift")
                     if not any(EXCLUDE_DIR.match(x) and x.lower() != "pods" for x in f.relative_to(src).parts[:-1])]
            if not files:
                continue
            version = None
            for xc in sorted(d.glob("*.xcconfig")):
                m = re.search(r"^SWIFT_VERSION\s*=\s*([\d.]+)", xc.read_text(errors="replace"), re.MULTILINE)
                if m:
                    version = m.group(1)
            pods.append({"module": module, "source_root": str(src.relative_to(root)), "files": files,
                         "mode": "v6" if (version or "5").startswith("6") else "v5"})
    # A pod's dependencies are the other pods its files import.
    names = {p["module"] for p in pods}
    for p in pods:
        imported = set()
        for f in p["files"]:
            for line in (root / f).read_text(errors="replace").splitlines():
                m = IMPORT.match(line)
                if m:
                    imported.add(m.group(3))
        p["deps"] = sorted((imported & names) - {p["module"]})
    return pods


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


def intent_definitions(root: Path, base: Path, beside=None):
    """The intent definition files (`.intentdefinition`, often in a `Base.lproj` folder) under a
    folder, as paths relative to the clone, for the IntentDefinitions plugin. With `beside` (the
    app target's files, which the project lists wherever they are, widget folders included),
    the definitions in a folder holding some of those files, whatever the folder is called
    (Dime's ExpenditureWidget/Base.lproj)."""
    found = []
    folders = {Path(f).parent for f in beside} if beside is not None else None
    for f in sorted((root / base).rglob("*.intentdefinition")):
        if not f.is_file():
            continue
        rel = f.relative_to(root)
        if folders is None:
            if any(EXCLUDE_DIR.match(x) for x in f.relative_to(root / base).parts[:-1]):
                continue
        else:
            home = rel.parent.parent if rel.parent.suffix == ".lproj" else rel.parent
            if any(x in (".build", ".git", "Pods", "Carthage") for x in rel.parts) or \
                    not any(d == home or d.is_relative_to(home) for d in folders):
                continue
        found.append(str(rel))
    return found


# An app target that runs swift-openapi-generator's build plugin (`plugin:OpenAPIGenerator` in
# its project) gets its `Client` and `Components` from the OpenAPI document beside its files, as
# Xcode generates them. The sweep target gets the same plugin, from the generator at the app's
# own pinned revision, and the document and its config are copied next to its sources.
OPENAPI_PLUGIN = "plugin:OpenAPIGenerator"
OPENAPI_DOC = re.compile(r"^openapi\.(ya?ml|json)$")
OPENAPI_CONFIG = re.compile(r"^openapi-generator-config\.ya?ml$")


def openapi_inputs(root: Path, extra, beside):
    """[document, config] (paths relative to the clone) for the app target's OpenAPIGenerator
    plugin, or [] when its project runs none. The pair beside the most of the target's files is
    the one Xcode feeds the plugin."""
    projects = [f for f in root.rglob("project.pbxproj")
                if not excluded(f.relative_to(root), extra) and ".build" not in f.relative_to(root).parts]
    if not any(OPENAPI_PLUGIN in f.read_text(errors="replace") for f in projects):
        return []
    homes = {}
    for f in beside:
        for d in Path(f).parents:
            homes[d] = homes.get(d, 0) + 1
    def found(pattern):
        hits = [f.relative_to(root) for f in root.rglob("*") if pattern.match(f.name) and f.is_file()
                and not any(part in (".build", ".git", "Pods", "Carthage", PACKAGES_DIR) for part in f.relative_to(root).parts)
                and not excluded(f.relative_to(root), extra)]
        hits = [h for h in hits if homes.get(h.parent)]
        return str(max(hits, key=lambda h: (homes[h.parent], -len(h.parts)))) if hits else None
    doc, config = found(OPENAPI_DOC), found(OPENAPI_CONFIG)
    return [doc, config] if doc and config else []


def describe_app(entry, root: Path, work: Path = None):
    """The sweep's view of one clone: its local targets, its packages' targets, the app target's
    files, the imports."""
    extra = entry.get("exclude", [])
    packages = read_local_packages(root, extra)
    pins = resolved_pins(root, extra) if work else {}
    remote_notes = []
    if work:
        pins = declared_pins(work, root, extra, packages, pins, remote_notes)
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
        traits = default_traits(dump)
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
                if not dependency_traits_hold(d, traits):
                    continue
                kind, name, package = dependency_names(d)
                if kind in ("target", "byName") and name in local_names:
                    deps.append(name)
                elif name in product_targets and kind in ("product", "byName"):
                    deps.extend(product_targets[name])
                elif name in remote_names_by_product and kind in ("product", "byName"):
                    deps.extend(remote_names_by_product[name])
                elif name:
                    third.append(name)
            # SwiftPM builds every Swift file under the target's folder but hidden ones and the
            # target's own `exclude` paths, so the app-level folder filter stays out of it: a
            # source folder may be named like one it skips (MlemMiddleware's `Snapshot` models).
            target_excludes = [Path(e) for e in t.get("exclude", [])]
            files = [str(f.relative_to(root)) for f in files_under(root / src, ".swift")
                     if not in_target_exclude(f.relative_to(root / src), target_excludes)]
            # A target at the package's own folder (`path: "."`) holds its manifest, which is
            # SwiftPM's to read, not a source of the module (BackyardBirds' data package).
            files = [f for f in files if not (Path(f).parent == Path(p["dir"]) and is_manifest(Path(f).name))]
            targets.append({
                "module": t["name"], "source_root": str(src), "files": files, "package_dir": p["dir"],
                "deps": sorted(set(deps) - {t["name"]}), "third_party": sorted(set(third)),
                "mode": language_mode_of_package(dump, t), "settings": swift_settings(t, traits),
                "resources": [r.get("path") for r in t.get("resources") or [] if r.get("path")],
                "models": data_models(root, src),
                "intents": intent_definitions(root, src),
                "executable": t["type"] == "executable",
            })
    local_count = len(targets)
    targets.extend(remote)
    # The CocoaPods the repository keeps checked in, each a module of its own, as Xcode builds
    # them (Clendar's R.swift.Library and SwiftyChrono).
    # Only the pods some file outside them imports: a pod the tests alone use stays out.
    taken = {t["module"] for t in targets}
    pods = checked_in_pods(root)
    outside = set()
    if pods:
        for f in root.rglob("*.swift"):
            if "Pods" in f.relative_to(root).parts or ".build" in f.relative_to(root).parts:
                continue
            for line in f.read_text(errors="replace").splitlines():
                m = IMPORT.match(line)
                if m:
                    outside.add(m.group(3))
    wanted, todo = set(), [p["module"] for p in pods if p["module"] in outside]
    by_pod = {p["module"]: p for p in pods}
    while todo:
        n = todo.pop()
        if n not in wanted:
            wanted.add(n)
            todo.extend(by_pod[n]["deps"])
    for p in pods:
        if p["module"] not in wanted or p["module"] in taken or excluded_by_entry(Path(p["source_root"]) / "x", extra):
            continue
        targets.append({
            "module": p["module"], "source_root": p["source_root"], "files": p["files"], "deps": p["deps"],
            "third_party": [], "mode": p["mode"], "settings": [], "resources": [], "models": [], "intents": [],
            "executable": False, "pod": True,
        })
        notes.append(f"checked-in pod {p['source_root']}: module {p['module']}, {len(p['files'])} files")
    notes.extend(remote_notes)
    # The app target: every Swift file outside the local packages and the excluded folders.
    # `project_files` also holds the files in folders whose names only suggest another target
    # (`Intents`, `Preview Content`): an app target whose project lists them compiles them.
    app_files, project_files = [], []
    for f in sorted(root.rglob("*.swift")):
        rel = f.relative_to(root)
        if is_manifest(rel.name):
            continue
        if excluded_by_entry(rel, extra) or any(rel.is_relative_to(d) for d in pkg_dirs if str(d) != "."):
            continue
        if Path(".") in pkg_dirs and any(rel.is_relative_to(Path(t["source_root"])) for t in targets if not t.get("remote")):
            continue
        project_files.append(str(rel))
        if not excluded(rel, extra):
            app_files.append(str(rel))
    # The iOS app target's own files, when its Xcode project says which they are: a repository
    # with a macOS app, extensions or a watch app beside it shares some folders and declares its
    # own copy of other types in each, which redeclare one another in one module.
    pbx_files = [p for p in sorted(root.rglob("project.pbxproj"))
                 if not excluded(p.relative_to(root).parent.parent / "x", extra)
                 and not any(p.relative_to(root).is_relative_to(d) for d in pkg_dirs if str(d) != ".")]
    try:
        app_target = xcodeproj.app_target_files(root, pbx_files)
    except Exception as e:  # an unreadable project leaves the folder-based guess
        app_target = None
        notes.append(f"Xcode project not read ({type(e).__name__}: {str(e)[:120]})")
    sub_apps = []  # (target name, project folder, files, conditions, regex literals, concurrency) of the repository's other iOS apps
    other_bases = []  # the folders of the repository's other apps' projects
    conditions = []  # the app target's Debug compilation conditions (`TARGET_APP`)
    regex = None  # whether the app target's Debug build parses bare-slash regex literals (None: no target read)
    concurrency = None  # the app target's own concurrency defaults (None: no target read)
    if app_target:
        name, members, base, conditions, regex, concurrency = app_target
        guessed = set(app_files)
        kept = [f for f in project_files if f in members or (f in guessed and not Path(f).is_relative_to(base))]
        # A repository of several apps, each in its own project folder (SimpleSwiftUI's four,
        # SwiftUIExperiments' forty-five): each other iOS app is built as a module of its own,
        # from the files its target compiles, since in one module their types redeclare one another.
        for pbx in pbx_files:
            other_base = pbx.relative_to(root).parent.parent
            if str(other_base) == "." or other_base.is_relative_to(base) or base.is_relative_to(other_base):
                continue
            try:
                other = xcodeproj.app_target_files(root, [pbx])
                ios = other and xcodeproj.app_target_files(root, [pbx], ios_only=True)
            except Exception:
                continue
            if not other:
                continue
            other_bases.append(other_base)
            if ios:  # another platform's app (SimpleSwiftUI's macOS SimpleNotes) is left out
                # Every file its target compiles, shared ones included: a file two apps list is
                # built in each app's module (issue 236).
                files = [f for f in project_files if f in ios[1]]
                if files:
                    sub_apps.append((ios[0], other_base, files, ios[3], ios[4], ios[5]))
        if other_bases:
            claimed = {f for _, _, files, _, _, _ in sub_apps for f in files}
            kept = [f for f in kept if f in members or (f not in claimed and not any(Path(f).is_relative_to(b) for b in other_bases))]
            left = len(other_bases) - len(sub_apps)
            notes.append(f"{len(sub_apps)} more iOS apps in their own project folders, each built as its own module"
                         + (f"; {left} other apps' folders left out" if left else ""))
        if kept:
            if len(kept) < len(app_files):
                notes.append(f"app target {name}: {len(kept)} of {len(app_files)} Swift files outside the packages")
            listed = len(set(kept) - set(app_files))
            if listed:
                notes.append(f"app target {name}: {listed} Swift files its project compiles from folders named for other targets")
            app_files = kept
        else:
            conditions = []
            regex = None
            concurrency = None
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
        # The app's asset catalogs, for their symbols (`Image(.logo)`); the sweep builds no
        # resources for the app, so only the catalogs' folders and `Contents.json` are copied.
        # The app's intent definitions, for the classes Xcode generates from them.
        intents = [d for d in intent_definitions(root, Path("."), beside=app_files + [f for _, _, fs, _, _, _ in sub_apps for f in fs])
                   if not excluded_by_entry(Path(d), extra)
                   and not any(Path(d).is_relative_to(p) for p in pkg_dirs if str(p) != ".")
                   and not any(Path(d).is_relative_to(Path(t["source_root"])) for t in targets if not t.get("remote"))]
        catalogs = [c for c in asset_catalogs(root, Path(".")) if not excluded(Path(c), extra)
                    and not any(Path(c).is_relative_to(d) for d in pkg_dirs if str(d) != ".")
                    and not any(Path(c).is_relative_to(Path(t["source_root"])) for t in targets if not t.get("remote"))]
        openapi = openapi_inputs(root, extra, app_files)
        if openapi:
            if "swift-openapi-generator" in pins:
                notes.append(f"app target: OpenAPIGenerator plugin generates from {openapi[0]}")
            else:
                notes.append("app target: its project runs the OpenAPIGenerator plugin, but no pin names swift-openapi-generator")
                openapi = []
        targets.append({
            "module": "Sweep" + re.sub(r"\W", "", entry["name"]), "source_root": ".", "files": app_files,
            "deps": sorted({t["module"] for t in targets if not t["executable"] and not t.get("macro")}), "third_party": [],
            "mode": xcode_language_mode(root), "settings": xcode_settings(root, conditions, regex, concurrency),
            "resources": [], "models": models, "intents": intents,
            "openapi": openapi, "openapi_pin": pins.get("swift-openapi-generator") if openapi else None,
            "catalogs": catalogs, "symbol_extensions": bool(catalogs) and xcode_asset_symbol_extensions(root),
            "executable": True, "app": True,
        })
        sub_bases = [b for _, b, _, _, _, _ in sub_apps]
        if sub_bases:
            main = targets[-1]
            main["models"] = [m for m in main["models"] if not any(Path(m).is_relative_to(b) for b in sub_bases)]
            main["intents"] = [d for d in main["intents"] if not any(Path(d).is_relative_to(b) for b in sub_bases)]
            main["catalogs"] = [c for c in main["catalogs"] if not any(Path(c).is_relative_to(b) for b in sub_bases)]
            main["symbol_extensions"] = bool(main["catalogs"]) and main["symbol_extensions"]
        used = {t["module"] for t in targets}
        for sub_name, sub_base, files, sub_conditions, sub_regex, sub_concurrency in sub_apps:
            module = "Sweep" + re.sub(r"\W", "", entry["name"]) + "_" + (re.sub(r"\W", "", sub_name) or "App")
            while module in used:
                module += "_"
            used.add(module)
            sub_catalogs = [c for c in catalogs if Path(c).is_relative_to(sub_base)]
            targets.append({
                "module": module, "source_root": ".", "files": files,
                "deps": sorted({t["module"] for t in targets if not t["executable"] and not t.get("macro")}),
                "third_party": [], "mode": xcode_language_mode(root / sub_base),
                "settings": xcode_settings(root / sub_base, sub_conditions, sub_regex, sub_concurrency), "resources": [],
                "models": [m for m in models if Path(m).is_relative_to(sub_base)],
                "intents": [d for d in intents if Path(d).is_relative_to(sub_base)],
                "catalogs": sub_catalogs, "symbol_extensions": bool(sub_catalogs) and xcode_asset_symbol_extensions(root / sub_base),
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
    # A local package's file may import a package module that its own manifest doesn't declare
    # when the Xcode project links that product: Xcode builds the workspace's products into one
    # folder every module there sees (Mlem's Media imports NukeVideo, which only the app target
    # links). Such an import makes the module the local target's dependency, as the app
    # target's own imports do.
    linked_products = set()
    for f in root.rglob("project.pbxproj"):
        if not excluded(f.relative_to(root), extra) and ".build" not in f.relative_to(root).parts:
            linked_products.update(m.group(1).strip('"') for m in PRODUCT_NAME.finditer(f.read_text(errors="replace")))
    linked_modules = {n for prod in linked_products for n in remote_names_by_product.get(prod, [])} & set(remote_modules)
    if linked_modules:
        for t in targets[:local_count]:
            imported = set()
            for f in t["files"]:
                for line in (root / f).read_text(errors="replace").splitlines():
                    m = IMPORT.match(line)
                    if m:
                        imported.add(m.group(3))
            implicit = sorted((linked_modules & imported) - set(t["deps"]) - {t["module"]})
            if implicit:
                t["deps"] = sorted(set(t["deps"]) | set(implicit))
                notes.append(f"package target {t['module']}: imports {', '.join(implicit)}, which its manifest doesn't declare and the Xcode project links")
    # Only the package targets the app's own targets reach are built. A local package neither the
    # Xcode project links (`productName = ...`) nor the app's files import is one Xcode never
    # builds (OldOS keeps a vendored SwiftUIReorderableForEach folder it doesn't use), so its
    # targets start no reach; one the used packages depend on is still reached through them.
    by = {t["module"]: t for t in targets}
    roots = [t for t in targets if not t.get("remote")]
    app_targets = [t for t in targets if t.get("app") and t["source_root"] == "."]
    projects = [f for f in root.rglob("project.pbxproj")
                if not excluded(f.relative_to(root), extra) and ".build" not in f.relative_to(root).parts]
    if app_targets and projects:
        linked = set()
        for f in projects:
            linked.update(m.group(1).strip('"') for m in PRODUCT_NAME.finditer(f.read_text(errors="replace")))
        imported = set()
        for t in app_targets:
            for f in t["files"]:
                for line in (root / f).read_text(errors="replace").splitlines():
                    m = IMPORT.match(line)
                    if m:
                        imported.add(m.group(3))
        used_dirs = {"."}
        for p in packages:
            if not p["dump"]:
                continue
            names = {t["name"] for t in p["dump"]["targets"]} | {prod["name"] for prod in p["dump"].get("products", [])}
            if names & linked or (names | {n.replace("-", "_") for n in names}) & imported:
                used_dirs.add(p["dir"])
        unused = sorted({t["package_dir"] for t in roots if "package_dir" in t and t["package_dir"] not in used_dirs})
        for d in unused:
            notes.append(f"{d}: local package the project neither links nor imports; started no build")
        dropped = {t["module"] for t in roots if t.get("package_dir", ".") not in used_dirs}
        for t in app_targets:
            t["deps"] = [d for d in t["deps"] if d not in dropped]
        roots = [t for t in roots if t.get("package_dir", ".") in used_dirs]
    reach, todo = set(), [t["module"] for t in roots]
    while todo:
        n = todo.pop()
        if n in reach or n not in by:
            continue
        reach.add(n)
        todo.extend(by[n]["deps"])
    targets = [t for t in targets if t["module"] in reach or any(t is r for r in roots)]
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


def xcode_asset_symbol_extensions(root: Path):
    """Whether the app's Xcode project asks for asset symbol extensions (`Color.accent` as well as
    `ColorResource.accent`), as ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS = YES
    on any of its targets."""
    setting = re.compile(r"ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS\s*[=:]\s*\"?YES")
    for pbx in root.rglob("project.pbxproj"):
        if any(EXCLUDE_DIR.match(p) for p in pbx.relative_to(root).parts[:-2]):
            continue
        if setting.search(pbx.read_text(errors="replace")):
            return True
    return any(setting.search(yml.read_text(errors="replace")) for yml in list(root.glob("project.yml")) + list(root.glob("*.yml")))


def xcode_regex_literals(root: Path):
    """Whether an app with no Xcode target the sweep could read (an XcodeGen `project.yml`)
    builds with bare `/.../` regex literals: Xcode's "Enable Bare Slash Regex Literals"
    (`SWIFT_ENABLE_BARE_SLASH_REGEX`) is on unless the spec turns it off."""
    off = re.compile(r"SWIFT_ENABLE_BARE_SLASH_REGEX\s*:\s*[\"']?NO")
    return not any(off.search(yml.read_text(errors="replace")) for yml in list(root.glob("project.yml")) + list(root.glob("*.yml")))


def xcode_settings(root: Path, conditions, regex=None, concurrency=None):
    """The Swift settings an Xcode app target builds with: its compilation conditions, and in
    Swift 5 mode the bare-slash regex literals Xcode turns on (Swift 6 always has them), so a
    Swift 5 app target parses `/[a-z]*/` (Mlem's sign-up and onboarding checks) where a plain
    Swift 5 compile reads a comment or a division. `regex` is the target's own Debug setting
    (`Project.regex_literals`), None when no target was read."""
    settings = [f".define({json.dumps(c)})" for c in conditions]
    if regex is None:
        regex = xcode_regex_literals(root)
    if xcode_language_mode(root) == "v5" and regex:
        settings.append('.enableUpcomingFeature("BareSlashRegexLiterals")')
    return settings + xcode_concurrency_settings(root, concurrency)


# Xcode 26's "Approachable Concurrency" (SWIFT_APPROACHABLE_CONCURRENCY = YES) turns these on.
APPROACHABLE_CONCURRENCY = ["DisableOutwardActorInference", "GlobalActorIsolatedTypesUsability",
                            "InferIsolatedConformances", "InferSendableFromCaptures", "NonisolatedNonsendingByDefault"]


def xcode_concurrency_settings(root: Path, concurrency=None):
    """The app target's concurrency defaults as settings: "Default Actor Isolation" MainActor
    (SWIFT_DEFAULT_ACTOR_ISOLATION, as IceCubes's targets set it, so its unannotated types are
    main-actor isolated) and Approachable Concurrency's upcoming features. `concurrency` is the
    target's own Debug settings (`Project.concurrency`); with no target read (an XcodeGen
    `project.yml`), what most of the project's configurations set."""
    if concurrency is not None:
        out = [DEFAULT_MAIN_ACTOR] if concurrency.get("main_actor") else []
        if concurrency.get("approachable"):
            out += [f'.enableUpcomingFeature("{f}")' for f in APPROACHABLE_CONCURRENCY]
        return out
    isolation, approachable = Counter(), Counter()
    texts = [pbx.read_text(errors="replace") for pbx in root.rglob("project.pbxproj")
             if not any(EXCLUDE_DIR.match(p) for p in pbx.relative_to(root).parts[:-2])]
    texts += [yml.read_text(errors="replace") for yml in list(root.glob("project.yml")) + list(root.glob("*.yml"))]
    for text in texts:
        isolation.update(v.lower() for v in re.findall(r"SWIFT_DEFAULT_ACTOR_ISOLATION\s*[=:]\s*\"?(\w+)", text))
        approachable.update(v.upper() for v in re.findall(r"SWIFT_APPROACHABLE_CONCURRENCY\s*[=:]\s*\"?(\w+)", text))
    out = []
    if isolation and isolation.most_common(1)[0][0] == "mainactor":
        out.append(DEFAULT_MAIN_ACTOR)
    if approachable and approachable.most_common(1)[0][0] == "YES":
        out += [f'.enableUpcomingFeature("{f}")' for f in APPROACHABLE_CONCURRENCY]
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
sys.path.insert(0, str(Path(__file__).resolve().parent))
import xcodeproj  # noqa: E402  (the iOS app target's files, from its project.pbxproj)


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


# The products every sweep target links, as Xcode links Apple's frameworks: SwiftUIWeb's, and the
# shadows of the Apple modules the SDK lacks.
WEB_PRODUCTS = [
    ("SwiftUI", "SwiftUIWeb"),
    ("SwiftUIWebCanvas", "SwiftUIWeb"),
    ("Charts", "SwiftUIWeb"),
    ("MapKit", "SwiftUIWeb"),
    ("AVFoundation", "SwiftUIWeb"),
    ("AVFAudio", "SwiftUIWeb"),
    ("AVKit", "SwiftUIWeb"),
    ("Speech", "SwiftUIWeb"),
    ("SwiftData", "SwiftUIWeb"),
    ("UserNotifications", "UIKitWeb"),
    ("CryptoKit", "SwiftUIWeb"),
    ("CoreHaptics", "SwiftUIWeb"),
    ("WidgetKit", "SwiftUIWeb"),
    ("StoreKit", "SwiftUIWeb"),
    ("AppIntents", "SwiftUIWeb"),
    ("Intents", "SwiftUIWeb"),
    ("IntentsUI", "SwiftUIWeb"),
    ("WebKit", "SwiftUIWeb"),
    ("AudioToolbox", "SwiftUIWeb"),
    ("EventKit", "SwiftUIWeb"),
    ("EventKitUI", "SwiftUIWeb"),
    ("Contacts", "SwiftUIWeb"),
    ("Photos", "SwiftUIWeb"),
    ("PhotosUI", "SwiftUIWeb"),
    ("AuthenticationServices", "SwiftUIWeb"),
    ("CoreMotion", "SwiftUIWeb"),
    ("ActivityKit", "SwiftUIWeb"),
    ("BackgroundTasks", "SwiftUIWeb"),
    ("TipKit", "SwiftUIWeb"),
    ("Symbols", "Shadows"),
    ("Translation", "SwiftUIWeb"),
    ("JavaScriptCore", "SwiftUIWeb"),
    ("CloudKit", "SwiftUIWeb"),
    ("PDFKit", "SwiftUIWeb"),
    ("CoreSpotlight", "SwiftUIWeb"),
    ("NaturalLanguage", "SwiftUIWeb"),
    ("QuickLook", "SwiftUIWeb"),
    ("LinkPresentation", "SwiftUIWeb"),
    ("WeatherKit", "SwiftUIWeb"),
    ("MediaPlayer", "SwiftUIWeb"),
    ("CoreTelephony", "SwiftUIWeb"),
    ("WatchConnectivity", "SwiftUIWeb"),
    ("GameKit", "SwiftUIWeb"),
    ("SceneKit", "SwiftUIWeb"),
    ("UIKit", "UIKitWeb"),
    ("Foundation", "Shadows"),
    ("Combine", "Shadows"),
    ("Security", "Shadows"),
    ("SafariServices", "Shadows"),
    ("os", "Shadows"),
    ("OSLog", "Shadows"),
    ("CoreGraphics", "Shadows"),
    ("CoreImage", "Shadows"),
    ("UniformTypeIdentifiers", "Shadows"),
    ("CoreData", "Shadows"),
    ("Dispatch", "Shadows"),
    ("CoreFoundation", "Shadows"),
    ("ImageIO", "Shadows"),
    ("MobileCoreServices", "Shadows"),
    ("SystemConfiguration", "Shadows"),
    ("Network", "Shadows"),
    ("LocalAuthentication", "Shadows"),
    ("FoundationNetworking", "Shadows"),
    ("FoundationXML", "Shadows"),
    ("CommonCrypto", "Shadows"),
    ("Compression", "Shadows"),
    ("zlib", "Shadows"),
    ("CoreText", "Shadows"),
    ("Accelerate", "Shadows"),
    ("XCTest", "Shadows"),
]


def _products(condition=""):
    return "".join(f'    .product(name: "{n}", package: "{p}"{condition}),\n' for n, p in WEB_PRODUCTS)


MANIFEST_HEAD = """// swift-tools-version: 6.1
// Generated by Tools/Coverage/sweep.py prepare: one target per local package target and one for
// each app of this batch, linking SwiftUIWeb's products where Xcode links Apple's frameworks.
import PackageDescription
import CompilerPluginSupport  // `.macro` targets (packages' macros, built for the host)

let web: [Target.Dependency] = [
""" + _products() + """]
// A target a macro uses (a package's macro support library, and what that imports) also builds
// for the host, as the macro's dependency, where Apple's Foundation and Dispatch are the real
// ones: there SwiftUIWeb's products and the shadows of Apple's modules (empty outside wasm, so
// they would hide the host's own) stay out.
let webOnWasm: [Target.Dependency] = [
""" + _products(", condition: .when(platforms: [.wasi])") + """]
let stack: [LinkerSetting] = [.unsafeFlags(["-Xlinker", "-z", "-Xlinker", "stack-size=4194304"])]
"""


DECL_NAME = re.compile(r'name: "([^"]+)"')

# A file that names a type through its module (`Foundation.Date`) without importing Foundation
# itself: on iOS `import UIKit` or `import SwiftUI` makes the module name visible, here neither
# can re-export the Foundation shadow (it lives in Packages/Shadows, which depends on them).
FOUNDATION_QUALIFIED = re.compile(r"(?<![\w.])Foundation\.[A-Za-z_]")
PRODUCT_NAME = re.compile(r"\bproductName = (\"[^\"\n]*\"|[^;\s]+);")
IMPORTS_FOUNDATION = re.compile(r"^\s*(?:@\w+\s+)*import\s+(?:\w+\s+)?Foundation\b", re.M)
# Such a target imports the shadow implicitly, as the app's own manifest would (README, "Naming
# Foundation"); only those targets, so Combine and the rest of what the shadow re-exports stay
# out of files that do not see them on iOS (a package's own `Future` beside Combine's).
PACKAGE_NAME_FLAG = '.unsafeFlags(["-package-name", {}])'


def package_name_of(target, app):
    """The package a target came from, as SwiftPM would name it: a pinned package's identity, a
    local package's folder, or the app for its own targets. A local package is a package of its
    own, so an app file's `@retroactive` conformance to one of its types holds (Harbour's
    PortainerKit) and its `package` declarations stay inside it."""
    if target.get("remote"):
        return target["remote"].split("@")[0]
    name = "app-" + (target.get("base") or app["name"])
    if target.get("package_dir") not in (None, "", "."):  # a root package is the app's own
        name += "/" + str(target["package_dir"])
    return name


IMPLICIT_FOUNDATION = '.unsafeFlags(["-Xfrontend", "-import-module", "-Xfrontend", "Foundation"], .when(platforms: [.wasi]))'
# A package's macro builds for the host against the swift-syntax SwiftUIWeb resolves, which can be
# newer than the one the package pins. Older swift-syntax modules imported Foundation, so a macro
# could use Foundation's String members (TCA's ReducerMacro, `capitalized`) without importing it.
# The host's own Foundation, imported implicitly, keeps those macros building as they do upstream.
MACRO_FOUNDATION = '.unsafeFlags(["-Xfrontend", "-import-module", "-Xfrontend", "Foundation"])'


# A file that calls POSIX threads with a C library import for Darwin and Glibc only (an older
# swift-openapi-urlsession's Lock.swift): on wasm it imports nothing, so it sees neither WASILibc's
# pthread types nor the shadow's single-threaded mutex functions. The implicit Foundation import
# brings both, as it does for a Foundation-qualified name.
CALLS_PTHREAD = re.compile(r"(?<![\w.])pthread_[a-z_]+\s*\(")
SEES_WASILIBC = re.compile(r"canImport\(\s*WASILibc\s*\)|^\s*(?:@\w+\s+)*import\s+WASILibc\b", re.M)


def names_foundation_without_importing(text):
    if IMPORTS_FOUNDATION.search(text):
        return False
    return bool(FOUNDATION_QUALIFIED.search(text)) or (bool(CALLS_PTHREAD.search(text)) and not SEES_WASILIBC.search(text))


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


IOS_CONDITION = re.compile(r"^(\s*#\s*(?:if|elseif)\b.*)$")
IOS_OS = re.compile(r"\bos\(\s*iOS\s*\)")


def ios_conditions(text):
    """The text with `os(iOS)` read as true in its `#if` and `#elseif` lines and nothing else
    changed, so its lines keep their numbers: decision 0025's rewrite (scripts/ios-conditions.py),
    which builds an app's iOS branches, as the browser runs it."""
    lines = text.split("\n")
    for i, line in enumerate(lines):
        if IOS_CONDITION.match(line):
            lines[i] = IOS_OS.sub("true", line)
    return "\n".join(lines)


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
    declared, uses_syntax, openapi_pin = set(), False, None
    batch_apps = [app for app in plan["apps"] if app.get("batch") == args.batch]
    # The targets a macro uses, directly or through others, in any app of the batch: they build
    # for the host too. A package two apps share is declared once, so whether it builds for the
    # host can't depend on which app comes first.
    for_host = set()
    for app in batch_apps:
        by_module = {t["module"]: t for t in app["targets"] if not t.get("skip")}
        pending = [d for t in by_module.values() if t.get("macro") for d in t["deps"]]
        while pending:
            m = pending.pop()
            if m in by_module and m not in for_host and not by_module[m].get("macro"):
                for_host.add(m)
                pending += by_module[m]["deps"]
    for app in batch_apps:
        local = {t["module"] for t in app["targets"]} | {t["module"].replace("-", "_") for t in app["targets"]}
        strip = (set(app["missing_imports"]) | set(strip_extra.get(app["name"], []))) - local
        strips[app["name"]] = sorted(strip)
        # A pinned package's Swift target over a C target of its own keeps its `os(iOS)` lines in
        # an --ios sweep: its iOS branches call C declarations that the C headers guard with
        # `__APPLE__`, which the rewrite can't change (swift-numerics' RealModule calls
        # `libm_exp10`, declared only `#if __APPLE__` in _NumericsShims).
        c_targets = {(t["remote"], t["module"]) for t in app["targets"] if t.get("c") and t.get("remote")}
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
                quote_dirs = vendored_quote_dirs(dest_root, t["public_headers"], t["c_settings"])
                settings = list(t["c_settings"])
                flags = [x for d in quote_dirs for x in ("-iquote", str(d.resolve()))]
                if quote_dirs:
                    print(f"{t['module']}: own headers on the quote path: "
                          + ", ".join(d.relative_to(dest_root).as_posix() or "." for d in quote_dirs), flush=True)
                missing = wasi_missing_calls(dest_root)
                if missing:
                    flags += ["-include", str(WASI_POSIX_COMPAT)]
                    print(f"{t['module']}: WASI stand-ins for " + ", ".join(sorted(missing)), flush=True)
                if flags:
                    settings.append(f".unsafeFlags({json.dumps(flags)})")
                decls.append(
                    f'        .target(\n            name: "{t["module"]}",\n            dependencies: [{", ".join(json.dumps(d) for d in t["deps"])}],\n'
                    f'            path: "Sources/{t["module"]}",\n'
                    + (f'            exclude: [{", ".join(json.dumps(e) for e in excludes)}],\n' if excludes else "")
                    + f'            publicHeadersPath: {json.dumps(t["public_headers"])},\n'
                    + f'            cSettings: [{", ".join(settings)}]\n        ),'
                )
                continue
            # SwiftPM gives each package its own -package-name, so `package` declarations stay
            # inside it. Here every app and pinned package is one package, so each target turns
            # SwiftPM's name off (`packageAccess: false`) and names the package it came from, or
            # swift-case-paths' package `UncheckedSendable` would clash with ConcurrencyExtras' in
            # swift-navigation. (With SwiftPM's name left on, it wins over the flag: PR 227's first
            # sweep.) Macro targets too, or a macro could not reach its own package's `package`
            # helpers (issue 228).
            package_flag = PACKAGE_NAME_FLAG.format(json.dumps(package_name_of(t, app)))
            if t.get("macro"):
                # Built for the host against the sweep package's swift-syntax; sources as they are.
                uses_syntax = True
                for f in t["files"]:
                    dest = dest_root / Path(f).relative_to(t["source_root"])
                    dest.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(clone_dir / f, dest)
                syntax = "".join(f', .product(name: "{n}", package: "swift-syntax")' for n in t.get("syntax", []))
                deps = (", ".join(json.dumps(d) for d in t["deps"]) + syntax).lstrip(", ")
                settings = ", ".join([f".swiftLanguageMode(.{t['mode']})"] + t["settings"] + [package_flag, MACRO_FOUNDATION])
                decls.append(
                    f'        .macro(\n            name: "{t["module"]}",\n            dependencies: [{deps}],\n'
                    f'            path: "Sources/{t["module"]}",\n'
                    f'            packageAccess: false,\n'
                    f'            swiftSettings: [{settings}]\n        ),'
                )
                continue
            used = set()
            foundation_name = False
            wraps_c = bool(t.get("remote")) and any((t["remote"], d) in c_targets for d in t["deps"])
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
                foundation_name = foundation_name or names_foundation_without_importing(text)
                if args.ios and not wraps_c:
                    text = ios_conditions(text)
                dest.write_text(strip_imports(text, strip))
                mapping[str(dest.resolve())] = {"app": app["name"], "file": f, "base": t.get("base") or app["name"],
                                                **({"package": t["remote"].split("@")[0]} if t.get("remote") else {}),
                                                **({"keep_os": True} if wraps_c else {})}
            if not t["files"]:
                # A target with no Swift sources (an Objective-C or C package, whose only Swift
                # file was its manifest) still needs its folder, so the module exists for the
                # targets that import it.
                dest_root.mkdir(parents=True, exist_ok=True)
                (dest_root / "_NoSwiftSources.swift").write_text(
                    "// This target has no Swift sources in the app's repository.\n")
            resources = []
            # A package target that declares no resources still gets the ones SwiftPM finds by
            # type (string catalogs, .lproj folders, asset catalogs), and with them `Bundle.module`
            # (BackyardBirds' data package). They are copied as they are, which needs no Xcode tool.
            resource_rules = [(r, "process") for r in t["resources"]]
            if not resource_rules and not t.get("app"):
                resource_rules = [(r, "copy") for r in auto_resources(clone_dir / t["source_root"])]
            for r, rule in resource_rules:
                src = clone_dir / t["source_root"] / r
                if src.exists():
                    dst = dest_root / r
                    if src.is_dir():
                        shutil.copytree(src, dst, dirs_exist_ok=True)
                    else:
                        dst.parent.mkdir(parents=True, exist_ok=True); shutil.copy2(src, dst)
                    resources.append(f'.{rule}({json.dumps(r)})')
            # Core Data models go next to the sources, out of the target's files, and the
            # CoreDataModel plugin generates their classes (as Xcode's codegen does).
            models = []
            if t.get("models"):
                traits_needed.add("CoreData")
            for m in t.get("models", []):
                name = Path(m).name
                if name in models:
                    continue
                # A model inside a resource folder that was copied above (Hipstapaper's
                # Resources/CD_MOM.xcdatamodeld) comes out of that copy, or the plugin, which
                # reads the whole target folder, would generate its classes twice.
                model_src = (clone_dir / m).resolve()
                for r, _ in resource_rules:
                    r_src = (clone_dir / t["source_root"] / r).resolve()
                    if r_src.is_dir() and r_src != model_src and model_src.is_relative_to(r_src):
                        shutil.rmtree(dest_root / r / model_src.relative_to(r_src), ignore_errors=True)
                shutil.copytree(clone_dir / m, dest_root / name, dirs_exist_ok=True)
                models.append(name)
            # Intent definitions go next to the sources, out of the target's files, and the
            # IntentDefinitions plugin generates their classes (as Xcode's codegen does). One
            # localised into several `.lproj` folders is generated once.
            for i, d in enumerate(t.get("intents", [])):
                out = dest_root / "_IntentDefinitions" / f"{i}-{Path(d).name}"
                out.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(clone_dir / d, out)
            if t.get("intents"):
                models.append("_IntentDefinitions")
            # The OpenAPI document and the generator's config go next to the sources, where the
            # OpenAPIGenerator plugin looks for them (SwiftPM leaves them out of the build).
            for f in t.get("openapi", []):
                shutil.copy2(clone_dir / f, dest_root / Path(f).name)
            if t.get("openapi"):
                openapi_pin = openapi_pin or t["openapi_pin"]
            # The app's catalogs (not its resources here): their folders and `Contents.json`, out
            # of the target's files, for the AssetSymbols plugin to read.
            for i, c in enumerate(t.get("catalogs", [])):
                skeleton = dest_root / "_AssetCatalogs" / f"{i}-{Path(c).name}"
                for d in sorted([clone_dir / c] + [x for x in (clone_dir / c).rglob("*") if x.is_dir()]):
                    out = skeleton / d.relative_to(clone_dir / c)
                    out.mkdir(parents=True, exist_ok=True)
                    if (d / "Contents.json").is_file():
                        shutil.copy2(d / "Contents.json", out / "Contents.json")
            if t.get("catalogs"):
                models.append("_AssetCatalogs")
                # The project's asset symbol extensions setting, as the plugin reads it.
                if t.get("symbol_extensions"):
                    (dest_root / "_AssetCatalogs" / "AssetSymbolExtensions").write_text("")
            # Asset catalogs among the resources get their symbols (`Image(.logo)`) from the
            # AssetSymbols plugin, as Xcode generates them.
            plugins = (['.plugin(name: "CoreDataModel", package: "SwiftUIWeb")'] if t.get("models") else []) + (
                ['.plugin(name: "AssetSymbols", package: "SwiftUIWeb")']
                if t.get("catalogs") or any(r.endswith('.xcassets")') for r in resources) else []) + (
                ['.plugin(name: "IntentDefinitions", package: "SwiftUIWeb")'] if t.get("intents") else []) + (
                ['.plugin(name: "OpenAPIGenerator", package: "swift-openapi-generator")'] if t.get("openapi") else [])
            kind = "executableTarget" if t.get("app") else "target"
            settings = [f".swiftLanguageMode(.{t['mode']})"] + t["settings"] + [package_flag]
            if foundation_name:
                settings.append(IMPLICIT_FOUNDATION)
            extra = [json.dumps(d) for d in t["deps"]]
            if t.get("syntax"):
                uses_syntax = True
                extra += [f'.product(name: "{n}", package: "swift-syntax")' for n in t["syntax"]]
            # One typed array, not a chain of `+`: a long chain is more than the manifest's type
            # checker will take (IcySky's 32 targets).
            base = "webOnWasm" if t["module"] in for_host else "web"
            deps = f"{base} + ([{', '.join(extra)}] as [Target.Dependency])" if extra else base
            decls.append(
                f'        .{kind}(\n            name: "{t["module"]}",\n            dependencies: {deps},\n'
                f'            path: "Sources/{t["module"]}",\n'
                + (f'            exclude: [{", ".join(json.dumps(m) for m in models)}],\n' if models else "")
                + (f'            resources: [{", ".join(resources)}],\n' if resources else "")
                + "            packageAccess: false,\n"
                + f'            swiftSettings: [{", ".join(settings)}]'
                + (",\n            linkerSettings: stack" if t.get("app") else "")
                + (f',\n            plugins: [{", ".join(plugins)}]' if plugins else "")
                + "\n        ),"
            )
    def traits_for(package):
        names = [t for t in app_traits.TRAITS if t in traits_needed and package in app_traits.TRAITS[t][1]]
        return f', traits: [{", ".join(json.dumps(t) for t in names)}]' if names else ""
    # The packages' macros build against the swift-syntax SwiftUIWeb already resolves.
    syntax_dependency = f'\n        .package(url: "{SYNTAX_PACKAGE}", from: "601.0.1"),' if uses_syntax else ""
    # The app's own pin of swift-openapi-generator, for its build plugin.
    if openapi_pin:
        syntax_dependency += f'\n        .package(url: {json.dumps(openapi_pin["url"])}, revision: {json.dumps(openapi_pin["revision"])}),'
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
    # Whether the sources were written with iOS conditions on, so a rewrite during the run keeps it.
    (pkg / "options.json").write_text(json.dumps({"ios": bool(args.ios)}))
    (pkg / "manifest.json").write_text(json.dumps(parts))
    print(f"wrote {pkg / 'Package.swift'} ({len(decls)} targets, {len(mapping)} files"
          + "".join(f", {t} trait" for t in app_traits.TRAITS if t in traits_needed) + ")")


# MARK: run and classify

ERROR = re.compile(r"^(/[^:\n]+\.swift):(\d+):(\d+): error: (.+)$", re.MULTILINE)
NO_MODULE = re.compile(r"no such module '([^']+)'")
UNATTRIBUTED = re.compile(r"^(.*\berror: .+)$", re.MULTILINE)
ERROR_LINE = re.compile(r"^(/[^:\n]+\.swift):(\d+):(\d+): error: (.+)$")
NOTE_LINE = re.compile(r"^/[^:\n]+:\d+:\d+: note: .+$")
OTHER_DIAGNOSTIC = re.compile(r"^/[^:\n]+:\d+:\d+: (?:error|warning): ")


# The lines of a crashed compile that say what crashed come before its backtrace's frames: the
# assertion or error, "Stack dump:" and the numbered requests ("3.\tWhile evaluating request
# ASTLoweringRequest(...)", "4.\tWhile silgen emitFunction ... (at file:line)").
CRASH_LINE = re.compile(r"^\s*\d+\.\t|Stack dump:|Assertion|error:")


def crash_tail(out: str, keep: int = 40, last: int = 20) -> str:
    """What a module that failed with none of its errors in the app keeps for the log: the lines
    that name a crash (at most `keep` of them) and then the output's last `last` lines."""
    lines = out.splitlines()
    named = [n for n, line in enumerate(lines) if CRASH_LINE.search(line)][:keep]
    picked = sorted(set(named) | set(range(max(0, len(lines) - last), len(lines))))
    text, previous = [], -1
    for n in picked:
        if previous >= 0 and n != previous + 1:
            text.append("    ...")
        text.append(lines[n][:400])
        previous = n
    return "\n".join(text)


def notes_of(out):
    """The compiler's `note:` lines after each error, keyed as ERROR's matches are (path, line,
    column, message): "found this candidate in module …" and the like, which --show prints."""
    notes, current = {}, None
    for text in out.splitlines():
        error = ERROR_LINE.match(text)
        if error:
            current = error.groups()
            notes.setdefault(current, [])
        elif current and NOTE_LINE.match(text):
            if text not in notes[current]:
                notes[current].append(text)
        elif OTHER_DIAGNOSTIC.match(text):
            current = None
    return notes


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


def rewrite_sources(mapping, work, app_name, strip, ios=False):
    """Writes an app's copied sources again with a larger set of imports taken out, the way
    prepare wrote them (with iOS conditions on in an --ios sweep)."""
    for dest, where in mapping.items():
        if where["app"] == app_name:
            source = work / where.get("base", app_name) / where["file"]
            text = source.read_text(errors="replace")
            if ios and not where.get("keep_os"):
                text = ios_conditions(text)
            text = strip_imports(text, strip)
            if Path(dest).read_text(errors="replace") != text:  # an unchanged file keeps its build
                Path(dest).write_text(text)


def source_line(path, line, width=200):
    """The text of `line` (1-based) in `path`, stripped and cut to `width`, or "" when unreadable."""
    try:
        with open(path, errors="replace") as f:
            for n, text in enumerate(f, 1):
                if n == int(line):
                    text = text.strip()
                    return text if len(text) <= width else text[:width] + " …"
    except (OSError, ValueError):
        pass
    return ""


def cmd_run(args):
    plan = json.loads(Path(args.plan).read_text())
    pkg = Path(args.pkg).resolve()
    work = Path(args.work)
    logs = pkg / "logs"
    logs.mkdir(exist_ok=True)
    mapping = json.loads((pkg / "mapping.json").read_text())
    strips = json.loads((pkg / "strip.json").read_text())
    options_file = pkg / "options.json"
    ios = bool(json.loads(options_file.read_text()).get("ios")) if options_file.exists() else False
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
    results = {"batch": args.batch, "sdk": args.sdk, "deps": "ok" if code == 0 else "failed", "apps": []}
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
                rewrite_sources(mapping, work, app["name"], set(strips[app["name"]]), ios)
            code, out = build(t["module"], 2400)
            # A module the wasm SDK turns out not to have (or not to show to this target) is
            # taken out like the others and the target built again, once.
            absent = set(NO_MODULE.findall(out)) - set(strips[app["name"]])
            if code != 0 and absent:
                strips[app["name"]] = sorted(set(strips[app["name"]]) | absent)
                rewrite_sources(mapping, work, app["name"], set(strips[app["name"]]), ios)
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
                               "raw": (path, line, col, msg),
                               **({"package": where["package"]} if where.get("package") else {})})
            # Kept for the log alone (--show), so the results' error rows stay as they were.
            notes = notes_of(out) if args.show else {}
            error_sources = [source_line(e["raw"][0], e["raw"][1]) if args.show else "" for e in errors]
            error_notes = [notes.get(e.pop("raw"), [])[:8] for e in errors]
            ok = code == 0
            if not ok:
                failed.add(t["module"])
            # A module that failed with none of its errors in the app's own files (they sit in
            # SwiftUIWeb's code, or carry no file) keeps the first of them, so the job log says why.
            outside = [] if ok or errors else UNATTRIBUTED.findall(out)[:5]
            status.append({"module": t["module"], "status": "ok" if ok else ("timeout" if code == "timeout" else "errors"),
                           "errors": errors, "tail": "" if ok or errors else crash_tail(out),
                           **({"outside": outside} if outside else {}),
                           **({"without": blocked} if blocked else {})})
            if t.get("remote"):
                status[-1]["package"] = t["remote"]
                built[t["module"]] = {k: v for k, v in status[-1].items() if k != "errors"}
            print(f"{app['name']} {t['module']}: {status[-1]['status']} ({len(errors)} errors)")
            for line in outside:
                print(f"  outside the app: {line}")
            if args.show and re.search(args.show, f"{app['name']} {t['module']}"):
                # The whole list in the job log, for a module a change is aimed at (the
                # artifacts hold it too, but a log is what every reader can open).
                for e, these, text in zip(errors, error_notes, error_sources):
                    print(f"  {e['file']}:{e['line']}: {e['msg']}")
                    if text:
                        # The line itself, as the sweep built it, since the app's source is
                        # in no artifact a reader of the log can open.
                        print(f"      | {text}")
                    for note in these:
                        print(f"      {note}")
                # A module that failed with no error of the app's (a compiler crash, say) shows
                # the end of its build output, which holds the crash's stack dump, since only
                # the results file keeps it otherwise.
                if status[-1]["tail"]:
                    print("  end of the build output:")
                    for line in status[-1]["tail"].splitlines():
                        print(f"    | {line}")
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
    p.add_argument("--ios", action="store_true", help="read `os(iOS)` as true in #if lines, as decision 0025 builds an app")
    p = sub.add_parser("run"); p.add_argument("--plan", required=True); p.add_argument("--work", required=True)
    p.add_argument("--pkg", required=True); p.add_argument("--batch", type=int, required=True)
    p.add_argument("--sdk", required=True); p.add_argument("-o", "--out", required=True)
    p.add_argument("--show", default="", help="print every error of the modules this pattern matches (`App Module`)")
    args = ap.parse_args()
    {"plan": cmd_plan, "fetch": cmd_fetch, "prepare": cmd_prepare, "run": cmd_run}[args.cmd](args)


if __name__ == "__main__":
    main()
