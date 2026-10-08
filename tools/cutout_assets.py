#!/usr/bin/env python3
"""Cut the subjects out of the magenta-backed originals, at full resolution.

    python3 tools/cutout_assets.py            # every set that has originals/
    python3 tools/cutout_assets.py --force
    python3 tools/cutout_assets.py vegetation/cactus

assets_src/<cat>/<set>/originals/*.jpg  ->  assets_src/<cat>/<set>/cutouts/<set>_NN.webp

The originals are kept untouched; the cutouts are the high-res RGBA masters (lossless WebP: every visible pixel
exact, the colour under fully clear pixels dropped, about 60 % smaller than PNG) that
tools/build_assets.py then shrinks and palette-dithers for the game.

Keying: the backdrops are a magenta gradient, so "magenta-ness" = min(R, B) - G is high
on the backdrop and low on every subject (greens, tans, rock oranges, greys). Alpha
is a soft ramp on that score, the magenta spill is pulled out of the edge colours, and
only the main subject is kept (stray blurred props and seed specks are dropped). Sets
listed in SPLIT keep every large object as its own sprite (sheets of small rocks).
Exact duplicate originals are cut once. The ground textures are full tiles, not
cutouts; tools/bake_ground.py reads those originals directly.
"""
import argparse
import hashlib
import sys
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "assets_src"
EXTS = {".png", ".jpg", ".jpeg", ".webp"}
SKIP_CATEGORIES = {"ground"}          # tiles, not sprites
SPLIT = {"rocks/small_rocks"}         # one sprite per object on the sheet
KEY_LO, KEY_HI = 0.10, 0.30           # magenta score ramp: below LO solid, above HI clear
MARGIN = 6                            # px of clear border kept around each crop


def key(rgb: np.ndarray) -> tuple:
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    m = np.minimum(r, b) - g
    t = np.clip((m - KEY_LO) / (KEY_HI - KEY_LO), 0.0, 1.0)
    alpha = 1.0 - t * t * (3.0 - 2.0 * t)
    # despill: no texel keeps more magenta than green allows
    spill = np.clip(np.minimum(r, b) - g, 0.0, None)
    out = rgb.copy()
    out[..., 0] -= spill
    out[..., 2] -= spill
    return np.clip(out, 0.0, 1.0), alpha


def objects(alpha: np.ndarray, split: bool) -> list:
    solid = ndimage.binary_opening(alpha > 0.5, iterations=1)
    lab, n = ndimage.label(solid)
    if n == 0:
        return []
    areas = ndimage.sum(solid, lab, range(1, n + 1))
    biggest = areas.max()
    if not split:
        keep = [int(np.argmax(areas)) + 1]
    else:
        keep = [i + 1 for i, a in enumerate(areas) if a >= 0.2 * biggest]
    out = []
    for k in keep:
        mask = lab == k
        # grow a little so the soft edge of the kept object survives the selection
        grown = ndimage.binary_dilation(mask, iterations=4)
        ys, xs = np.nonzero(mask)
        out.append((grown, xs.min(), ys.min(), xs.max(), ys.max()))
    out.sort(key=lambda o: o[1])      # left to right on a sheet
    return out


def cut_set(set_dir: Path, force: bool) -> int:
    originals = sorted(p for p in (set_dir / "originals").iterdir() if p.suffix.lower() in EXTS)
    dst_dir = set_dir / "cutouts"
    dst_dir.mkdir(exist_ok=True)
    rel = set_dir.relative_to(SRC).as_posix()
    name = set_dir.name
    seen = set()
    n = 0
    made = 0
    for src in originals:
        digest = hashlib.md5(src.read_bytes()).hexdigest()
        if digest in seen:
            print(f"  {src.name}: duplicate, skipped")
            continue
        seen.add(digest)
        rgb = np.asarray(Image.open(src).convert("RGB")).astype(np.float32) / 255.0
        clean, alpha = key(rgb)
        objs = objects(alpha, rel in SPLIT)
        for grown, x0, y0, x1, y1 in objs:
            n += 1
            dst = dst_dir / f"{name}_{n:02d}.webp"
            if dst.exists() and not force and dst.stat().st_mtime >= src.stat().st_mtime:
                continue
            a = np.where(grown, alpha, 0.0)
            h, w = a.shape
            x0, y0 = max(0, x0 - MARGIN), max(0, y0 - MARGIN)
            x1, y1 = min(w, x1 + MARGIN + 1), min(h, y1 + 1)     # sprites stand on their bottom edge
            px = np.concatenate([clean, a[..., None]], -1)[y0:y1, x0:x1]
            Image.fromarray(np.round(px * 255).astype(np.uint8), "RGBA").save(dst, lossless=True, method=4)
            made += 1
            print(f"  {src.name} -> {dst.name} {x1 - x0}x{y1 - y0}")
    return made


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("only", nargs="*")
    ap.add_argument("--force", action="store_true")
    args = ap.parse_args()
    total = 0
    for orig in sorted(SRC.rglob("originals")):
        set_dir = orig.parent
        rel = set_dir.relative_to(SRC).as_posix()
        if rel.split("/")[0] in SKIP_CATEGORIES:
            continue
        if args.only and not any(rel.startswith(o.rstrip("/")) for o in args.only):
            continue
        print(rel)
        total += cut_set(set_dir, args.force)
    print(f"{total} cutouts written")


if __name__ == "__main__":
    sys.exit(main())
