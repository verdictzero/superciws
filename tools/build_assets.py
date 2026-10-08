#!/usr/bin/env python3
"""Turn the original art in assets_src/ into the lo-fi copies the game loads.

    python3 tools/build_assets.py            # rebuild what changed
    python3 tools/build_assets.py --force    # rebuild everything
    python3 tools/build_assets.py ground     # only assets_src/ground/...

assets_src/<cat>/<set>/cutouts/<name>.webp  ->  assets/<cat>/<set>/<name>.png

The originals (assets_src/<cat>/<set>/originals/) and their high-res cutouts (made by
tools/cutout_assets.py) stay in assets_src/; Godot ignores that folder, so none of it
ships. The ground tiles are read straight from their originals by tools/bake_ground.py
and the mountain ring strips are composed by tools/bake_sky.py, both using the
quantiser in this file. Each sprite is:

  1. downsampled to its in-game size with a premultiplied Lanczos filter (so cutout
     edges don't pick up a dark matte),
  2. given 1-bit alpha at 50 %, with the edge colours bled into the clear texels so
     filtering and mips never show a halo,
  3. quantised through the same 32x32x32 lookup as the post shader onto the game's
     128-colour palette (scripts/palette.gd), with palette-aware 8x8 Bayer ordered
     dithering: each texel picks between its nearest palette colour and the next one
     along the quantisation error, so gradients cross-hatch without hue noise.

Sizes per category live in RULES below; the first matching pattern wins.
"""
import argparse
import fnmatch
import re
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "assets_src"
DST = ROOT / "assets"
PALETTE_GD = ROOT / "scripts" / "palette.gd"
EXTS = {".png", ".jpg", ".jpeg", ".webp", ".tga", ".bmp"}

# (glob on the path relative to assets_src, rule). Sizes are in texels, chosen from how
# big each thing can get on the 512x384 screen (a 10 m saguaro 30 m from the camera is
# about 100 px tall, most are far smaller).
#   max_w / max_h : fit inside, keeping aspect (never upscales)
#   alpha         : "cut" = 1-bit alpha with bleed, "opaque" = drop alpha
#   skip          : not shipped as single sprites (composed elsewhere)
RULES = [
    ("vegetation/cactus*/*",     {"max_w": 96, "max_h": 128, "alpha": "cut"}),
    ("vegetation/bush/*",        {"max_w": 128, "max_h": 96, "alpha": "cut"}),
    ("vegetation/grass/*",       {"max_w": 96, "max_h": 80, "alpha": "cut"}),
    ("rocks/huge_rocks/*",       {"max_w": 160, "max_h": 112, "alpha": "cut"}),
    ("rocks/big_rocks/*",        {"max_w": 128, "max_h": 96, "alpha": "cut"}),
    ("rocks/small_rocks/*",      {"max_w": 48, "max_h": 48, "alpha": "cut"}),
    ("sky/mountains/*",          {"skip": True}),                         # -> tools/bake_sky.py
    ("sky/clouds/*",             {"max_w": 512, "max_h": 256, "alpha": "cut"}),
    ("*",                        {"max_w": 128, "max_h": 128, "alpha": "cut"}),
]

BAYER8 = np.array([
    [0, 32, 8, 40, 2, 34, 10, 42],
    [48, 16, 56, 24, 50, 18, 58, 26],
    [12, 44, 4, 36, 14, 46, 6, 38],
    [60, 28, 52, 20, 62, 30, 54, 22],
    [3, 35, 11, 43, 1, 33, 9, 41],
    [51, 19, 59, 27, 49, 17, 57, 25],
    [15, 47, 7, 39, 13, 45, 5, 37],
    [63, 31, 55, 23, 61, 29, 53, 21]], dtype=np.float32)
BAYER8 = (BAYER8 + 0.5) / 64.0
DITHER_REACH = 0.16          # same as the post shader's dither_reach


def load_palette() -> np.ndarray:
    text = PALETTE_GD.read_text()
    block = text[text.index("const COLORS"):text.index("]", text.index("const COLORS"))]
    hexes = re.findall(r'Color\("#([0-9a-fA-F]{6})"\)', block)
    if len(hexes) < 2:
        sys.exit("could not read the palette from scripts/palette.gd")
    return np.array([[int(h[i:i + 2], 16) for i in (0, 2, 4)] for h in hexes], np.float32) / 255.0


def oklab(c: np.ndarray) -> np.ndarray:
    """sRGB (0..1) -> Oklab. Same maths as shaders/palette_lut.gdshader."""
    c = np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)
    l = 0.4122214708 * c[..., 0] + 0.5363325363 * c[..., 1] + 0.0514459929 * c[..., 2]
    m = 0.2119034982 * c[..., 0] + 0.6806995451 * c[..., 1] + 0.1073969566 * c[..., 2]
    s = 0.0883024619 * c[..., 0] + 0.2817188376 * c[..., 1] + 0.6299787005 * c[..., 2]
    l, m, s = np.cbrt(l), np.cbrt(m), np.cbrt(s)
    return np.stack([0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
                     1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
                     0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s], -1)


def build_lut(pal: np.ndarray) -> np.ndarray:
    """32^3 -> palette colour, nearest in Oklab (as the post shader's LUT)."""
    g = np.arange(32, dtype=np.float32) / 31.0
    r, gg, b = np.meshgrid(g, g, g, indexing="ij")
    cube = oklab(np.stack([r, gg, b], -1).reshape(-1, 3))
    d = ((cube[:, None, :] - oklab(pal)[None, :, :]) ** 2).sum(-1)
    return pal[np.argmin(d, axis=1)].reshape(32, 32, 32, 3)


def lut_lookup(lut: np.ndarray, c: np.ndarray) -> np.ndarray:
    q = np.clip(np.floor(c * 31.0 + 0.5), 0, 31).astype(np.int32)
    return lut[q[..., 0], q[..., 1], q[..., 2]]


def palette_dither(rgb: np.ndarray, lut: np.ndarray) -> np.ndarray:
    """Palette-aware ordered dither: pick the nearest colour or the next one along the error."""
    h, w = rgb.shape[:2]
    c = np.clip(rgb, 0.0, 1.0)
    p0 = lut_lookup(lut, c)
    err = c - p0
    el = np.linalg.norm(err, axis=-1, keepdims=True)
    step = np.where(el > 0.004, err / np.maximum(el, 1e-6) * DITHER_REACH, 0.0)
    p1 = lut_lookup(lut, np.clip(c + step, 0.0, 1.0))
    span = p1 - p0
    sl = (span * span).sum(-1)
    t = np.where(sl > 1e-5, np.clip((err * span).sum(-1) / np.maximum(sl, 1e-6), 0.0, 1.0), 0.0)
    thresh = np.tile(BAYER8, (h // 8 + 1, w // 8 + 1))[:h, :w]
    return np.where((t > thresh)[..., None], p1, p0)


def fit_size(w: int, h: int, rule: dict) -> tuple:
    s = min(rule["max_w"] / w, rule["max_h"] / h, 1.0)
    return max(1, round(w * s)), max(1, round(h * s))


def resize_premultiplied(im: Image.Image, size: tuple) -> np.ndarray:
    a = np.asarray(im.convert("RGBA")).astype(np.float32) / 255.0
    pm = a.copy()
    pm[..., :3] *= pm[..., 3:4]
    if size != (im.width, im.height):
        chans = [np.asarray(Image.fromarray(pm[..., i]).resize(size, Image.LANCZOS)) for i in range(4)]
        pm = np.clip(np.stack(chans, -1), 0.0, 1.0)
    alpha = pm[..., 3:4]
    rgb = np.where(alpha > 1e-4, pm[..., :3] / np.maximum(alpha, 1e-4), 0.0)
    return np.concatenate([np.clip(rgb, 0, 1), alpha], -1)


def bleed(rgb: np.ndarray, solid: np.ndarray, rounds: int = 24) -> np.ndarray:
    """Spread the colours of solid texels outward into the clear ones."""
    rgb = rgb.copy()
    have = solid.copy()
    for _ in range(rounds):
        if have.all():
            break
        acc = np.zeros_like(rgb)
        n = np.zeros(have.shape, np.float32)
        for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1), (-1, -1), (-1, 1), (1, -1), (1, 1)):
            sh = np.roll(np.roll(have, dy, 0), dx, 1)
            acc += np.roll(np.roll(rgb, dy, 0), dx, 1) * sh[..., None]
            n += sh
        grow = (~have) & (n > 0)
        rgb[grow] = acc[grow] / n[grow][:, None]
        have = have | grow
    return rgb


def rule_for(rel: str) -> dict:
    for pat, rule in RULES:
        if fnmatch.fnmatch(rel, pat):
            return rule
    return RULES[-1][1]


def process(src: Path, dst: Path, rule: dict, lut: np.ndarray) -> str:
    im = Image.open(src)
    has_alpha = im.mode in ("RGBA", "LA") or (im.mode == "P" and "transparency" in im.info)
    size = fit_size(im.width, im.height, rule)
    px = resize_premultiplied(im, size)
    rgb, alpha = px[..., :3], px[..., 3]
    cut = rule["alpha"] == "cut" and has_alpha
    solid = alpha >= 0.5 if cut else np.ones(alpha.shape, bool)
    if cut and not solid.all():
        rgb = bleed(rgb, solid)
    out = palette_dither(rgb, lut)
    out8 = np.round(out * 255.0).astype(np.uint8)
    if cut:
        a8 = np.where(solid, 255, 0).astype(np.uint8)[..., None]
        Image.fromarray(np.concatenate([out8, a8], -1), "RGBA").save(dst)
    else:
        Image.fromarray(out8, "RGB").save(dst)
    return f"{im.width}x{im.height} -> {size[0]}x{size[1]}{' cut' if cut else ''}"


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("only", nargs="*", help="limit to these sub-paths of assets_src/")
    ap.add_argument("--force", action="store_true", help="rebuild even if up to date")
    args = ap.parse_args()
    if not SRC.exists():
        sys.exit("no assets_src/ folder")
    lut = build_lut(load_palette())
    done = skipped = 0
    for src in sorted(SRC.rglob("cutouts/*")):
        if src.suffix.lower() not in EXTS or not src.is_file():
            continue
        rel = src.relative_to(SRC).as_posix().replace("/cutouts/", "/")
        if args.only and not any(rel.startswith(o.rstrip("/")) for o in args.only):
            continue
        rule = rule_for(rel)
        if rule.get("skip"):
            continue
        dst = (DST / rel).with_suffix(".png")
        if not args.force and dst.exists() and dst.stat().st_mtime >= src.stat().st_mtime:
            skipped += 1
            continue
        dst.parent.mkdir(parents=True, exist_ok=True)
        print(f"{rel}: {process(src, dst, rule, lut)}")
        done += 1
    print(f"{done} built, {skipped} up to date")


if __name__ == "__main__":
    main()
