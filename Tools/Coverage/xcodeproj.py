"""The Swift files of an Xcode project's iOS app target, read from its `project.pbxproj`.

A repository often holds several apps and extensions side by side (a macOS app, an iOS app, a
share extension, widgets, a watch app) that share some folders and each declare their own copy of
other types. Building every Swift file outside the packages as one module redeclares those types,
so the sweep takes the iOS app's own files when the project says which they are: the files of its
Sources build phase, the files of the folders it synchronises (Xcode 16's folder references, less
their membership exceptions, plus files other targets' folders lend it), and the same for the
frameworks and static libraries it depends on. Extensions it embeds are left out, and so are files
in the project's folder that no target compiles (Xcode does not build them either). Files outside
the project's folder (another project's app, in a repository of several) are the sweep's to keep.

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
                ref = self.obj(bid).get("fileRef")
                if not ref:
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
            listed = set()
            for eid in group.get("exceptions", []):
                exception = self.obj(eid)
                if exception.get("target") == tid:
                    listed.update(exception.get("membershipExceptions", []))
            if gid in owned:
                for p in (self.root / folder).rglob("*.swift"):
                    if p.relative_to(self.root / folder).as_posix() not in listed:
                        files.add(p.relative_to(self.root))
            else:
                files.update(folder / f for f in listed if f.endswith(".swift") and (self.root / folder / f).is_file())
        return files

    def dependencies(self, tid):
        out = []
        for did in self.obj(tid).get("dependencies", []):
            dep = self.obj(did).get("target")
            if dep and self.obj(dep).get("isa") == "PBXNativeTarget":
                out.append(dep)
        return out


def app_target_files(root: Path, pbx_files):
    """The iOS app target's name, its Swift files (and those of the frameworks it builds) and the
    folder holding its project, from the project whose application is likeliest the iOS app; None
    when no project says."""
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
    return project.obj(tid).get("name", ""), {f.as_posix() for f in files}, project.base
