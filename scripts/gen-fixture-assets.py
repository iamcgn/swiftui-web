#!/usr/bin/env python3
"""Writes Fixtures/Assets.xcassets: the asset catalog the image and colour fixtures draw from, in
the exact on-disk format Xcode writes (Contents.json per set, loose PNG/JPEG files). Deterministic
so the committed files never drift; rerun after changing an image and regenerate the goldens.
Every image is asymmetric so a flipped, offset, mis-scaled or mis-tiled draw shows up in pixels."""
import json, math, struct, subprocess, zlib
from pathlib import Path

root = Path(__file__).resolve().parent.parent
catalog = root / "Fixtures" / "Assets.xcassets"
INFO = {"author": "xcode", "version": 1}


def png(width, height, pixel):
    """RGBA PNG; `pixel(x, y)` returns (r, g, b, a) for device pixel (x, y), y down."""
    raw = bytearray()
    for y in range(height):
        raw.append(0)
        for x in range(width):
            raw += bytes(pixel(x, y))
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(bytes(raw), 9)) + chunk(b"IEND", b""))


def write(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)


def contents(path, doc):
    write(path / "Contents.json", (json.dumps(doc, indent=2, sort_keys=True) + "\n").encode())


def imageset(name, points, draw, scales=(1, 2), template=False, folder="", appearance_draw=None, idioms=None):
    """`draw(u, v)` takes point coordinates (floats) and returns (r, g, b, a). Supersampled 3×3
    so anti-aliased edges are the same shape at every scale."""
    w, h = points
    directory = catalog / folder / f"{name}.imageset"
    entries = []
    variants = [(None, draw)] + ([("dark", appearance_draw)] if appearance_draw else [])
    for idiom in (idioms or ["universal"]):
        for appearance, fn in variants:
            for scale in scales:
                suffix = ("~mac" if idiom == "mac" else "") + ("-dark" if appearance else "") + (f"@{scale}x" if scale > 1 else "")
                filename = f"{name}{suffix}.png"
                def pixel(x, y, fn=fn, scale=scale):
                    acc = [0, 0, 0, 0]
                    for i in range(3):
                        for j in range(3):
                            r, g, b, a = fn((x + (i + 0.5) / 3) / scale, (y + (j + 0.5) / 3) / scale)
                            acc[0] += r * a; acc[1] += g * a; acc[2] += b * a; acc[3] += a
                    a = acc[3] / 9
                    if a == 0: return (0, 0, 0, 0)
                    return tuple(int(round(c / acc[3])) for c in acc[:3]) + (int(round(a)),)
                write(directory / filename, png(w * scale, h * scale, pixel))
                entry = {"filename": filename, "idiom": idiom, "scale": f"{scale}x"}
                if appearance: entry["appearances"] = [{"appearance": "luminosity", "value": appearance}]
                entries.append(entry)
            if 3 not in scales and not appearance and idiom == "universal":
                entries.append({"idiom": "universal", "scale": "3x"})     # Xcode leaves the empty slot in
    doc = {"images": entries, "info": INFO}
    if template: doc["properties"] = {"template-rendering-intent": "template"}
    contents(directory, doc)


def colorset(name, components, dark=None):
    def entry(c, appearance=None):
        e = {"color": {"color-space": "srgb", "components": {"alpha": c[3], "blue": c[2], "green": c[1], "red": c[0]}}, "idiom": "universal"}
        if appearance: e["appearances"] = [{"appearance": "luminosity", "value": appearance}]
        return e
    colors = [entry(components)] + ([entry(dark, "dark")] if dark else [])
    contents(catalog / f"{name}.colorset", {"colors": colors, "info": INFO})


def solid(rgb):
    return lambda u, v: rgb + (255,)


def bordered(w, h, border, inner):
    def fn(u, v):
        if u < border or v < border or u >= w - border or v >= h - border: return (32, 32, 32, 255)
        return inner(u, v)
    return fn


# swatch 64×40: 2 pt border, four quadrants (1x + 2x).
def quadrants(u, v):
    return ((220, 40, 40) if u < 32 else (40, 180, 80)) if v < 20 else ((40, 90, 220) if u < 32 else (240, 200, 40))
imageset("swatch", (64, 40), lambda u, v: bordered(64, 40, 2, lambda a, b: quadrants(a, b) + (255,))(u, v))

# tall 20×64, 2x only: four 16 pt bands.
bands = [(255, 120, 0), (0, 150, 200), (120, 60, 180), (30, 30, 30)]
imageset("tall", (20, 64), lambda u, v: bands[min(3, int(v // 16))] + (255,), scales=(2,))

# icon 24×24 template: a disc with a hole, anti-aliased, black (only its alpha matters).
def disc(u, v):
    d = math.hypot(u - 12, v - 12)
    if d > 10.5 or d < 4: return (0, 0, 0, 0)
    cover = min(1.0, 10.5 - d) * min(1.0, d - 4)
    return (0, 0, 0, int(round(255 * cover)))
imageset("icon", (24, 24), disc, template=True)

# panel 40×40 for cap insets: distinct 8 pt corners, edges and centre.
def panel(u, v):
    x = 0 if u < 8 else 2 if u >= 32 else 1
    y = 0 if v < 8 else 2 if v >= 32 else 1
    table = {(0, 0): (200, 0, 0), (2, 0): (0, 160, 0), (0, 2): (0, 0, 200), (2, 2): (200, 160, 0),
             (1, 0): (255, 128, 128), (1, 2): (128, 128, 255), (0, 1): (128, 255, 128), (2, 1): (255, 255, 128), (1, 1): (200, 200, 200)}
    return table[(x, y)] + (255,)
imageset("panel", (40, 40), panel)

# Folder/nested (namespace on) and loose (folder without a namespace).
contents(catalog / "Folder", {"info": INFO, "properties": {"provides-namespace": True}})
imageset("nested", (32, 16), bordered(32, 16, 2, solid((0, 160, 160))), folder="Folder")
contents(catalog / "Plain", {"info": INFO})
imageset("loose", (32, 16), bordered(32, 16, 2, solid((200, 40, 160))), folder="Plain")

# dual 48×24: light and dark appearance variants, 2x only.
def dual(base, mark):
    return lambda u, v: (mark if 4 <= u < 12 and 8 <= v < 16 else base) + (255,)
imageset("dual", (48, 24), dual((230, 230, 235), (0, 180, 220)), scales=(2,), appearance_draw=dual((40, 40, 45), (255, 140, 0)))

# badge 20×20: universal and mac idioms, 2x only; macOS must pick the mac one (blue).
directory = catalog / "badge.imageset"
write(directory / "badge@2x.png", png(40, 40, lambda x, y: (220, 40, 40, 255)))
write(directory / "badge~mac@2x.png", png(40, 40, lambda x, y: (40, 90, 220, 255)))
contents(directory, {"images": [{"filename": "badge@2x.png", "idiom": "universal", "scale": "2x"},
                                {"filename": "badge~mac@2x.png", "idiom": "mac", "scale": "2x"}], "info": INFO})

# photo 80×60 JPEG, 2x only: a gradient (pixel checks are tolerant; decoders differ slightly).
directory = catalog / "photo.imageset"
directory.mkdir(parents=True, exist_ok=True)
tmp = directory / "photo@2x.png"
write(tmp, png(160, 120, lambda x, y: (int(255 * x / 159), int(255 * (1 - y / 119)), int(255 * (1 - x / 159)), 255)))
subprocess.run(["sips", "-s", "format", "jpeg", "-s", "formatOptions", "90", str(tmp), "--out", str(directory / "photo@2x.jpg")], check=True, capture_output=True)
tmp.unlink()
contents(directory, {"images": [{"filename": "photo@2x.jpg", "idiom": "universal", "scale": "2x"}], "info": INFO})

# Colour sets, in the three component spellings Xcode writes.
colorset("Accent", ("0.000", "0.533", "1.000", "1.000"))
colorset("Panel", ("0xF2", "0xF2", "0xF7", "1.000"), dark=("0x1C", "0x1C", "0x1E", "1.000"))
colorset("Warm", ("255", "141", "40", "0.500"))

contents(catalog, {"info": INFO})
print(f"wrote {catalog.relative_to(root)}")
