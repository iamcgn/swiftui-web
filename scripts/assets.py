#!/usr/bin/env python3
"""Reads Xcode asset catalogs (`*.xcassets`) the way actool would, without Xcode, and writes what
SwiftUIWeb needs at run time: a manifest of image sets (variants per scale, idiom and appearance,
pixel sizes, template intent) and colour sets, plus a copy of every image file it references.

    scripts/assets.py <dir> --out <bundle-dir>/assets   # every *.xcassets under <dir>
    scripts/assets.py Fixtures --json Fixtures/Assets.manifest.json --out .build/assets

Outputs (all optional): --json <file> the manifest as JSON; --js <file> the same wrapped as
`window.__swiftuiwebAssets = …` for a <script> tag; --out <dir> the referenced files, laid out as
<catalog>/<set>.imageset/<file> so names never collide. File paths in the manifest are relative to
--out. Names follow the catalog: a folder with `provides-namespace` prefixes its contents
("Folder/nested"), any other folder is transparent. Unsupported: PDF/SVG images (Xcode rasterises
them), symbol sets, sprite atlases, slicing metadata, high-contrast and Display P3 variants (recorded
but ignored by the runtime), data sets, app icons. Each is reported on stderr."""
import argparse, json, shutil, struct, sys
from pathlib import Path

SKIPPED_DIRS = {".build", "node_modules", ".git", ".swiftpm"}
IDIOMS = {"universal", "mac", "iphone", "ipad", "tv", "watch", "car", "vision"}


def warn(message):
    print(f"assets: {message}", file=sys.stderr)


def read_contents(directory):
    file = directory / "Contents.json"
    if not file.exists(): return {}
    try:
        return json.loads(file.read_text())
    except json.JSONDecodeError as error:
        warn(f"{file}: {error}")
        return {}


def image_size(path):
    """(width, height) in pixels for PNG, JPEG and GIF; None for anything else."""
    data = path.read_bytes()
    if data[:8] == b"\x89PNG\r\n\x1a\n":
        return struct.unpack(">II", data[16:24])
    if data[:6] in (b"GIF87a", b"GIF89a"):
        return struct.unpack("<HH", data[6:10])
    if data[:2] == b"\xff\xd8":
        i = 2
        while i + 9 < len(data):
            if data[i] != 0xFF: i += 1; continue
            marker = data[i + 1]
            if marker in (0xD8, 0x01) or 0xD0 <= marker <= 0xD7: i += 2; continue
            length = struct.unpack(">H", data[i + 2:i + 4])[0]
            if marker in (0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7, 0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF):
                height, width = struct.unpack(">HH", data[i + 5:i + 9])
                return (width, height)
            i += 2 + length
    return None


def appearance(entry):
    """'any', 'light' or 'dark', plus flags for the variants the runtime ignores."""
    value, contrast = "any", None
    for item in entry.get("appearances", []):
        if item.get("appearance") == "luminosity": value = item.get("value", "any")
        elif item.get("appearance") == "contrast": contrast = item.get("value")
    return value, contrast


def component(text):
    """Colour components come as "0.533", "0x88" or "136"."""
    text = str(text).strip()
    if text.lower().startswith("0x"): return int(text, 16) / 255
    if "." in text: return float(text)
    return int(text) / 255


class Catalog:
    def __init__(self, out):
        self.out = out
        self.images = {}
        self.colors = {}

    def read(self, root):
        self.root = root
        self.walk(root, "")

    def walk(self, directory, prefix):
        for child in sorted(directory.iterdir()):
            if not child.is_dir(): continue
            if child.suffix == ".imageset": self.imageset(child, prefix + child.stem)
            elif child.suffix == ".colorset": self.colorset(child, prefix + child.stem)
            elif child.suffix in (".appiconset", ".launchimage", ".brandassets", ".imagestack", ".cubetextureset", ".textureset"):
                pass
            elif child.suffix in (".symbolset", ".dataset", ".spriteatlas"):
                warn(f"{child.relative_to(self.root.parent)}: {child.suffix[1:]} is not supported")
            elif child.suffix == "":
                properties = read_contents(child).get("properties", {})
                self.walk(child, prefix + child.name + "/" if properties.get("provides-namespace") else prefix)

    def imageset(self, directory, name):
        doc = read_contents(directory)
        variants = []
        for entry in doc.get("images", []):
            filename = entry.get("filename")
            if not filename: continue           # an empty slot Xcode leaves for a scale
            path = directory / filename
            if not path.exists():
                warn(f"{name}: missing file {filename}"); continue
            if path.suffix.lower() in (".pdf", ".svg"):
                warn(f"{name}: vector asset {filename} is not supported"); continue
            size = image_size(path)
            if size is None:
                warn(f"{name}: cannot read the size of {filename}"); continue
            scale_text = entry.get("scale", "1x")
            try:
                scale = int(scale_text.rstrip("x"))
            except ValueError:
                warn(f"{name}: unknown scale {scale_text!r} for {filename}"); continue
            idiom = entry.get("idiom", "universal")
            if idiom not in IDIOMS:
                warn(f"{name}: unknown idiom {idiom!r} for {filename}")
            luminosity, contrast = appearance(entry)
            variant = {"file": self.copy(path), "scale": scale, "width": size[0], "height": size[1],
                       "idiom": idiom, "appearance": luminosity}
            if contrast: variant["contrast"] = contrast
            if entry.get("display-gamut"): variant["gamut"] = entry["display-gamut"]
            if entry.get("subtype"): variant["subtype"] = entry["subtype"]
            variants.append(variant)
        if not variants:
            warn(f"{name}: no usable image"); return
        if name in self.images: warn(f"{name}: defined twice; the later one wins")
        properties = doc.get("properties", {})
        image = {"variants": variants}
        intent = properties.get("template-rendering-intent")
        if intent == "template": image["template"] = True
        if intent == "original": image["template"] = False
        if properties.get("resizing"): warn(f"{name}: slicing metadata is ignored")
        self.images[name] = image

    def colorset(self, directory, name):
        doc = read_contents(directory)
        variants = []
        for entry in doc.get("colors", []):
            color = entry.get("color", {})
            components = color.get("components", {})
            if not components: continue
            luminosity, contrast = appearance(entry)
            variant = {"idiom": entry.get("idiom", "universal"), "appearance": luminosity,
                       "colorSpace": color.get("color-space", "srgb")}
            try:
                for key in ("red", "green", "blue", "alpha"):
                    variant[key] = component(components.get(key, "1.0" if key == "alpha" else "0"))
            except ValueError as error:
                warn(f"{name}: bad component ({error})"); continue
            if contrast: variant["contrast"] = contrast
            if entry.get("display-gamut"): variant["gamut"] = entry["display-gamut"]
            variants.append(variant)
        if not variants:
            warn(f"{name}: no usable colour"); return
        self.colors[name] = {"variants": variants}

    def copy(self, path):
        relative = path.relative_to(self.root.parent)
        if self.out:
            target = self.out / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(path, target)
        return relative.as_posix()


def find_catalogs(source):
    if source.suffix == ".xcassets": return [source]
    found = []
    for path in sorted(source.rglob("*.xcassets")):
        if any(part in SKIPPED_DIRS for part in path.relative_to(source).parts): continue
        found.append(path)
    return found


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("source", help="a directory to search for *.xcassets, or one catalog")
    parser.add_argument("--out", help="directory to copy the image files into")
    parser.add_argument("--json", help="write the manifest as JSON to this file")
    parser.add_argument("--js", help="write the manifest as a script setting window.__swiftuiwebAssets")
    args = parser.parse_args()
    source = Path(args.source).resolve()
    out = Path(args.out).resolve() if args.out else None
    catalogs = find_catalogs(source)
    if not catalogs:
        warn(f"no *.xcassets under {source}")
    catalog = Catalog(out)
    for path in catalogs:
        catalog.read(path)
    manifest = {"version": 1, "catalogs": [p.name for p in catalogs],
                "images": dict(sorted(catalog.images.items())), "colors": dict(sorted(catalog.colors.items()))}
    text = json.dumps(manifest, indent=2, sort_keys=True)
    if args.json:
        Path(args.json).parent.mkdir(parents=True, exist_ok=True)
        Path(args.json).write_text(text + "\n")
    if args.js:
        Path(args.js).parent.mkdir(parents=True, exist_ok=True)
        # `base` resolves image files relative to this script's own URL, wherever the page lives.
        Path(args.js).write_text("(function(){var s=document.currentScript;var base=s&&s.src?s.src.replace(/[^/]*$/,''):'';"
                                 "var m=" + json.dumps(manifest, separators=(",", ":")) + ";m.base=base;window.__swiftuiwebAssets=m;})();\n")
    print(f"assets: {len(catalog.images)} image set(s), {len(catalog.colors)} colour set(s) from {len(catalogs)} catalog(s)", file=sys.stderr)


if __name__ == "__main__":
    main()
