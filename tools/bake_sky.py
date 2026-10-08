#!/usr/bin/env python3
"""Compose the mountain cutouts into the two horizon ring strips.

    python3 tools/bake_sky.py

Reads assets_src/sky/mountains/cutouts/*, writes assets/sky/mountains_near.png and
assets/sky/mountains_far.png, palette-dithered like every other in-game image.

Each strip wraps seamlessly and is drawn by shaders/horizon_band.gdshader with `tiles`
repeats around the circle, so its pixel aspect is matched to the shader's angular scale:
one strip pixel spans 2*pi / (tiles * width) radians horizontally and height / rows in
tan(elevation) vertically. Mountains stand on the strip's bottom row; the lowest rows are
filled solid so the ring has no gaps at the horizon (the shader carries that row on
downward to hide the terrain's rim).
"""
import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_assets as BA  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "assets_src/sky/mountains/cutouts"
OUT = ROOT / "assets/sky"

# name, tiles, width, shader height (tan), base (tan), peak range above the horizon (tan),
# haze mix, haze colour, seed. Must agree with scripts/terrain/horizon_ring.gd.
RINGS = [
    ("mountains_near", 2, 2048, 0.2, -0.06, (0.055, 0.105), 0.0, (0.0, 0.0, 0.0), 11),
    ("mountains_far", 3, 2048, 0.16, -0.045, (0.07, 0.11), 0.42, (0.72, 0.62, 0.70), 23),
]
SOLID_ROWS = 10


def load_cutouts():
    files = sorted(f for f in SRC.iterdir() if f.suffix.lower() in BA.EXTS)
    if not files:
        sys.exit("no mountain cutouts; run tools/cutout_assets.py")
    return [Image.open(f).convert("RGBA") for f in files]


def compose(name, tiles, width, height_tan, base_tan, peaks, haze_mix, haze, seed, cutouts, lut):
    rad_per_px = 2 * math.pi / (tiles * width)
    rows = int(round(height_tan / rad_per_px))
    canvas = np.zeros((rows, width, 4), np.float32)   # premultiplied
    rng = np.random.default_rng(seed)
    order = list(rng.permutation(len(cutouts)))
    order += list(rng.permutation(len(cutouts)))
    x = rng.integers(0, width)
    placed = 0
    covered = 0
    while covered < width * 1.15 and placed < len(order):
        im = cutouts[order[placed]]
        if rng.random() < 0.5:
            im = im.transpose(Image.FLIP_LEFT_RIGHT)
        peak = rng.uniform(*peaks)
        h = int(round((peak - base_tan) / rad_per_px))
        h = min(h, rows)
        w = int(round(im.width * h / im.height))
        px = BA.resize_premultiplied(im, (w, h))       # straight RGBA
        pm = px.copy()
        pm[..., :3] *= pm[..., 3:4]
        y0 = rows - h
        for dx in (0, -width):                          # wrap around the seam
            x0 = x + dx
            a0, a1 = max(0, x0), min(width, x0 + w)
            if a1 <= a0:
                continue
            src = pm[:, a0 - x0:a1 - x0]
            dst = canvas[y0:rows, a0:a1]
            # later (nearer) mountains overlap earlier ones
            canvas[y0:rows, a0:a1] = src + dst * (1.0 - src[..., 3:4])
        step = int(w * rng.uniform(0.55, 0.8))
        x = (x + step) % width
        covered += step
        placed += 1
    alpha = canvas[..., 3]
    rgb = np.where(alpha[..., None] > 1e-4, canvas[..., :3] / np.maximum(alpha[..., None], 1e-4), 0.0)
    solid = alpha >= 0.5
    rgb = BA.bleed(rgb, solid, rounds=64)
    solid[-SOLID_ROWS:] = True
    if haze_mix > 0:
        rgb = rgb * (1 - haze_mix) + np.array(haze, np.float32) * haze_mix
    out = BA.palette_dither(rgb, lut)
    a8 = np.where(solid, 255, 0).astype(np.uint8)[..., None]
    Image.fromarray(np.concatenate([np.round(out * 255).astype(np.uint8), a8], -1), "RGBA").save(OUT / f"{name}.png")
    print(f"{name}: {width}x{rows}, {placed} mountains, tiles {tiles}, height {rows * rad_per_px:.3f}")


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    lut = BA.build_lut(BA.load_palette())
    cutouts = load_cutouts()
    for ring in RINGS:
        compose(*ring, cutouts, lut)


if __name__ == "__main__":
    main()
