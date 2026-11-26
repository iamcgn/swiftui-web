"""The Swift files of an Xcode project's iOS app target, read from its `project.pbxproj`.

A repository often holds several apps and extensions side by side (a macOS app, an iOS app, a
share extension, widgets, a watch app) that share some folders and each declare their own copy of
other types. Building every Swift file outside the packages as one module redeclares those types,
so the sweep takes the iOS app's own files when the project says which they are: the files of its
Sources build phase, the files of the folders it synchronises (Xcode 16's folder references, less
their membership exceptions, plus files other targets' folders lend it), and the same for the
frameworks and static libraries it depends on. Extensions it embeds are left out, and so are files
in the project's folder that no target compiles (Xcode does not build them either), and files the
project builds only for other platforms (a platform filter of macOS alone). Files outside the
project's folder (another project's app, in a repository of several) are the sweep's to keep. The
target's active compilation conditions (`TARGET_APP`) are read too, for the app module's defines.

The format is an old-style (OpenStep) property list; `parse` reads it into dictionaries, lists
and strings.
"""
import os
import re
from pathlib import Path

_TOKEN = re.compile(r'\s+|//[^\n]*|/\*.*?\*/|"((?:[^"\\]|\\.)*)"|([^\s{}()=;,"]+)|([{}()=;,])', re.S)
_ESCAPES = {"n": "\n", "t": "\t", '"': '"', "\\": "\\"}


def _tokens(text):
    pos = 0
    while pos < len(text):
        m = _TOKEN.match(text, pos)
        if not m:
            raise ValueError(f"pbxproj: unreadable at {pos}")
        pos = m.end()
        if m.group(1) is not None:
            yield ("str", re.sub(r"\\(.)", lambda e: _ESCAPES.get(e.group(1), e.group(1)), m.group(1)))
        elif m.group(2) is not None:
            yield ("str", m.group(2))
        elif m.group(3) is not None:
            yield (m.group(3), None)


def parse(text):
    """The property list in `text` (the `// !$*UTF8*$!` header line is a comment)."""
    tokens = list(_tokens(text))
    pos = 0

    def value():
        nonlocal pos
        kind, v = tokens[pos]
        pos += 1
        if kind == "str":
            return v
        if kind == "{":
            out = {}
            while tokens[pos][0] != "}":
                key = value()
                assert tokens[pos][0] == "=", "pbxproj: expected ="
                pos += 1
                out[key] = value()
                if tokens[pos][0] == ";":
                    pos += 1
            pos += 1
            return out
        if kind == "(":
            out = []
            while tokens[pos][0] != ")":
                out.append(value())
                if tokens[pos][0] == ",":
                    pos += 1
            pos += 1
            return out
        raise ValueError(f"pbxproj: unexpected {kind}")

    return value()


FRAMEWORK_TYPES = {"com.apple.product-type.framework", "com.apple.product-type.library.static",
                   "com.apple.product-type.library.dynamic"}
IOS_HINT = re.compile(r"ios|iphone|mobile|ipad", re.I)
CONDITION = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")


def builds_for_ios(filters):
    """Whether a file with these platform filters (none: every platform) is built for iOS."""
    return not filters or any(f in ("ios", "iphoneos") for f in filters)
OTHER_PLATFORM_HINT = re.compile(r"mac|watch|tv|vision|catalyst", re.I)


class Project:
    def __init__(self, pbx: Path, root: Path):
        self.pbx = pbx
        self.root = root
        self.base = pbx.parent.parent.relative_to(root)   # the folder holding the .xcodeproj
        data = parse(pbx.read_text(errors="replace"))
        self.objects = data["objects"]
        self.project = self.objects[data["rootObject"]]
        self.parents = {}
        for oid, obj in self.objects.items():
            for child in obj.get("children", []) if isinstance(obj, dict) else []:
                self.parents[child] = oid

    def obj(self, oid):
        return self.objects.get(oid, {})

    def path_of(self, oid):
        """The repository-relative path of a file reference or group, or None outside the project's
        own tree (SDK, built products, absolute paths)."""
        parts = []
        while oid:
            o = self.obj(oid)
            tree = o.get("sourceTree", "<group>")
            if o.get("path"):
                parts.append(o["path"])
            if tree == "SOURCE_ROOT":
                break
            if tree != "<group>":
                return None
            oid = self.parents.get(oid)
        # Normalized: a file a group reaches through `..` (a group at `Sources`, a file at
        # `../Shared/X.swift`) must match the folder walk's `Shared/X.swift`, or the sweep leaves it out.
        path = Path(os.path.normpath(self.base.joinpath(*reversed(parts)))) if parts else self.base
        return None if path.parts[:1] == ("..",) else path

    def build_setting(self, target, key):
        values = []
        for cid in self.obj(target.get("buildConfigurationList")).get("buildConfigurations", []):
            v = self.obj(cid).get("buildSettings", {}).get(key)
            if v:
                values.append(v if isinstance(v, str) else " ".join(v))
        if not values:
            for cid in self.obj(self.project.get("buildConfigurationList")).get("buildConfigurations", []):
                v = self.obj(cid).get("buildSettings", {}).get(key)
                if v:
                    values.append(v if isinstance(v, str) else " ".join(v))
        return " ".join(values)

    def setting_in(self, config_list, key, name="Debug"):
        """`key` in the configuration called `name` of a configuration list (the first one when
        none has that name), as words; None when it isn't set there."""
        configs = [self.obj(c) for c in self.obj(config_list).get("buildConfigurations", [])]
        config = next((c for c in configs if c.get("name") == name), configs[0] if configs else {})
        v = config.get("buildSettings", {}).get(key)
        if v is None:
            return None
        return v.split() if isinstance(v, str) else [w for item in v for w in item.split()]

    def compilation_conditions(self, target):
        """The conditions a Debug build of the target defines: its own, with the project's where it
        inherits them (or sets none)."""
        own = self.setting_in(target.get("buildConfigurationList"), "SWIFT_ACTIVE_COMPILATION_CONDITIONS")
        project = self.setting_in(self.project.get("buildConfigurationList"), "SWIFT_ACTIVE_COMPILATION_CONDITIONS") or []
        words = project if own is None else [w for x in own for w in (project if x == "$(inherited)" else [x])]
        out = []
        for w in words:
            if CONDITION.match(w) and w not in out:
                out.append(w)
        return out

    def regex_literals(self, target):
        """Whether a Debug build of the target parses bare `/.../` regex literals: its own
        `SWIFT_ENABLE_BARE_SLASH_REGEX`, else the project's where it inherits or sets none, else
        Xcode's default, which is on."""
        own = self.setting_in(target.get("buildConfigurationList"), "SWIFT_ENABLE_BARE_SLASH_REGEX")
        project = self.setting_in(self.project.get("buildConfigurationList"), "SWIFT_ENABLE_BARE_SLASH_REGEX")
        words = project if own is None else [w for x in own for w in ((project or []) if x == "$(inherited)" else [x])]
        words = [w.strip('"').upper() for w in words or []]
        return not words or words[-1] != "NO"

    def concurrency(self, target):
        """The concurrency defaults a Debug build of the target sets: whether its unannotated
        declarations are main-actor isolated (`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`) and
        whether Approachable Concurrency is on (`SWIFT_APPROACHABLE_CONCURRENCY = YES`), each its
        own setting, else the project's where it inherits or sets none, else off as Xcode has it."""
        def last(key):
            own = self.setting_in(target.get("buildConfigurationList"), key)
            project = self.setting_in(self.project.get("buildConfigurationList"), key)
            words = project if own is None else [w for x in own for w in ((project or []) if x == "$(inherited)" else [x])]
            words = [w.strip('"').lower() for w in words or []]
            return words[-1] if words else None
        return {"main_actor": last("SWIFT_DEFAULT_ACTOR_ISOLATION") == "mainactor",
                "approachable": last("SWIFT_APPROACHABLE_CONCURRENCY") == "yes"}

    def targets(self):
        return [(tid, self.obj(tid)) for tid in self.project.get("targets", [])
                if self.obj(tid).get("isa") == "PBXNativeTarget"]

    def is_ios(self, target):
        sdk = self.build_setting(target, "SDKROOT")
        platforms = self.build_setting(target, "SUPPORTED_PLATFORMS")
        if "iphoneos" in sdk or "iphoneos" in platforms:
            return True
        if sdk or platforms:
            return False
        return bool(self.build_setting(target, "IPHONEOS_DEPLOYMENT_TARGET"))

    def swift_files(self, tid):
        """The Swift files the target compiles, repository-relative, or None if the project names
        a source the sweep cannot place (a file outside the tree)."""
        target = self.obj(tid)
        files = set()
        for phase in target.get("buildPhases", []):
            if self.obj(phase).get("isa") != "PBXSourcesBuildPhase":
                continue
            for bid in self.obj(phase).get("files", []):
                build_file = self.obj(bid)
                ref = build_file.get("fileRef")
                if not ref:
                    continue
                filters = build_file.get("platformFilters") or ([build_file["platformFilter"]] if build_file.get("platformFilter") else [])
                if not builds_for_ios(filters):
                    continue
                kind = self.obj(ref).get("isa")
                if kind == "PBXFileSystemSynchronizedRootGroup":
                    continue   # read below
                path = self.path_of(ref)
                if path is None:
                    return None
                if path.suffix == ".swift":
                    files.add(path)
                elif kind in ("PBXGroup", "PBXFileReference") and (self.root / path).is_dir():
                    files.update(p.relative_to(self.root) for p in (self.root / path).rglob("*.swift"))
        owned = set(target.get("fileSystemSynchronizedGroups", []))
        for gid, group in self.objects.items():
            if not isinstance(group, dict) or group.get("isa") != "PBXFileSystemSynchronizedRootGroup":
                continue
            folder = self.path_of(gid)
            if folder is None:
                continue
            listed, other_platforms = set(), set()
            for eid in group.get("exceptions", []):
                exception = self.obj(eid)
                if exception.get("target") == tid:
                    listed.update(exception.get("membershipExceptions", []))
                    filters = exception.get("platformFiltersByRelativePath", {})
                    other_platforms.update(f for f, platforms in filters.items() if not builds_for_ios(platforms))
            if gid in owned:
                for p in (self.root / folder).rglob("*.swift"):
                    rel = p.relative_to(self.root / folder).as_posix()
                    if rel not in listed and rel not in other_platforms:
                        files.add(p.relative_to(self.root))
            else:
                files.update(folder / f for f in listed
                             if f.endswith(".swift") and f not in other_platforms and (self.root / folder / f).is_file())
        return files

    def dependencies(self, tid):
        out = []
        for did in self.obj(tid).get("dependencies", []):
            dep = self.obj(did).get("target")
            if dep and self.obj(dep).get("isa") == "PBXNativeTarget":
                out.append(dep)
        return out


def app_target_files(root: Path, pbx_files, ios_only=False):
    """The iOS app target's name, its Swift files (and those of the frameworks it builds), the
    folder holding its project, its Debug compilation conditions, whether its Debug build
    parses bare-slash regex literals and its concurrency defaults, from the project whose
    application is likeliest the iOS app; None when no project says (or, with `ios_only`, when
    none builds an iOS application)."""
    candidates = []
    for pbx in pbx_files:
        try:
            project = Project(pbx, root)
        except Exception:
            continue
        for tid, target in project.targets():
            if target.get("productType") != "com.apple.product-type.application":
                continue
            name = target.get("name", "")
            ios = project.is_ios(target)
            if ios_only and not ios:
                continue
            score = (0 if ios else 1, 0 if IOS_HINT.search(name) else 1,
                     1 if OTHER_PLATFORM_HINT.search(name) else 0, len(name))
            candidates.append((score, str(pbx), tid, project))
    if not candidates:
        return None
    _, _, tid, project = min(candidates, key=lambda c: (c[0], c[1]))
    files, seen, todo = set(), set(), [tid]
    while todo:
        t = todo.pop()
        if t in seen:
            continue
        seen.add(t)
        if t != tid and project.obj(t).get("productType") not in FRAMEWORK_TYPES:
            continue
        own = project.swift_files(t)
        if own is None:
            return None
        files |= own
        todo.extend(project.dependencies(t))
    if not files:
        return None
    return (project.obj(tid).get("name", ""), {f.as_posix() for f in files}, project.base,
            project.compilation_conditions(project.obj(tid)), project.regex_literals(project.obj(tid)),
            project.concurrency(project.obj(tid)))
