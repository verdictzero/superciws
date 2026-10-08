#!/usr/bin/env python3
"""Scatter plants and rocks over the desert and pack their sprites into one atlas.

    python3 tools/bake_vegetation.py        # after bake_terrain.gd and build_assets.py

Reads the in-game sprites in assets/vegetation/*/ and assets/rocks/*/, the height grid
(build/terrain/height_bake.bin) and assets/terrain/desert.json. Writes
  assets/terrain/scatter_atlas.png    every sprite, padded, one texture
  assets/terrain/bake/scatter.bin     "SCT2", count, stride, gzip length, then gzip'd float32
                                      rows: x, y, z, width, height, u0, v0, u1, v1
  assets/terrain/bake/scatter.json    counts and stats
The game draws all of it as ONE MultiMesh of camera-facing quads.

Placement is a cluster process, so things grow the way they do in a real desert:
  - patch centres are Poisson-disc spread, denser where a slow "fertility" noise is
    high and in hollows (water collects there), none on the battery pad;
  - each patch has a character (scrub, saguaro stand, rock outcrop, grass swale) that
    decides which species it holds and how many;
  - inside a patch, members fall off from the centre with a Gaussian, and the biggest
    individuals stand near the middle: size shrinks with distance from the centre
    (plus jitter), so every group has a natural radial size gradient;
  - a light rain of singles between patches keeps the open ground from looking empty;
  - members keep a spacing proportional to their size, and small things (grass,
    pebbles) are only placed as far out as they can still be seen.
"""
import json
import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage

sys.path.insert(0, str(Path(__file__).resolve().parent))
from bake_ground import read_heights  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
CFG = json.loads((ROOT / "assets/terrain/desert.json").read_text())
R = float(CFG["radius"])
PAD = CFG["pad"]
SEED = int(CFG["seed"]) + 77
OUT_BAKE = ROOT / "assets/terrain/bake"

# species: sprite globs, height range (m), sink (fraction of height pushed into the
# ground), max view distance for placement, min spacing as a multiple of width
SPECIES = {
    "saguaro":   {"sprites": ["vegetation/cactus/cactus_0[12467].png"], "h": (5.0, 12.5), "sink": 0.02, "view": 1200, "space": 0.9},
    "barrel":    {"sprites": ["vegetation/cactus/cactus_0[35].png", "vegetation/cactus_3/*.png"], "h": (0.7, 1.6), "sink": 0.05, "view": 560, "space": 0.8},
    "pear":      {"sprites": ["vegetation/cactus_2/*.png"], "h": (0.9, 2.1), "sink": 0.05, "view": 700, "space": 0.75},
    "bush":      {"sprites": ["vegetation/bush/*.png"], "h": (1.2, 2.8), "sink": 0.04, "view": 900, "space": 0.6},
    "grass":     {"sprites": ["vegetation/grass/*.png"], "h": (0.45, 1.1), "sink": 0.08, "view": 420, "space": 0.5},
    "pebble":    {"sprites": ["rocks/small_rocks/*.png"], "h": (0.25, 0.8), "sink": 0.12, "view": 300, "space": 0.9},
    "boulder":   {"sprites": ["rocks/big_rocks/*.png"], "h": (1.4, 3.6), "sink": 0.1, "view": 900, "space": 0.85},
    "outcrop":   {"sprites": ["rocks/huge_rocks/*.png"], "h": (5.0, 12.0), "sink": 0.08, "view": 1300, "space": 0.85},
}

# patch characters: weight, radius range (m), members {species: (min, max)}
PATCHES = {
    "scrub":    {"w": 0.42, "r": (7, 22), "m": {"bush": (3, 9), "grass": (6, 18), "pear": (0, 3), "barrel": (0, 3), "pebble": (0, 4)}},
    "saguaro":  {"w": 0.22, "r": (10, 28), "m": {"saguaro": (1, 5), "bush": (1, 5), "barrel": (1, 4), "grass": (4, 12), "pear": (0, 2)}},
    "outcrop":  {"w": 0.14, "r": (9, 24), "m": {"outcrop": (1, 2), "boulder": (2, 6), "pebble": (5, 14), "bush": (1, 4), "grass": (3, 9)}},
    "swale":    {"w": 0.22, "r": (8, 26), "m": {"grass": (14, 34), "bush": (1, 4), "pebble": (0, 5)}},
}
SINGLES = {"bush": 0.32, "grass": 0.36, "barrel": 0.1, "pebble": 0.12, "boulder": 0.05, "saguaro": 0.05}
PATCH_SPACING = 17.0         # Poisson-disc radius between patch centres (m)
SINGLE_DENSITY = 1 / 380.0  # singles per square metre (before distance thinning)
CLEAR = float(PAD["sandy"]) * 0.75   # nothing grows closer than this to the asphalt


# ------------------------------------------------------------------ helpers
def load_heights():
    return read_heights(ROOT / "build/terrain/height_bake.bin")


def pad_sdf(x, z):
    c = PAD["corner"]
    qx = np.abs(x) - (PAD["half_x"] - c)
    qz = np.abs(z) - (PAD["half_z"] - c)
    return np.hypot(np.maximum(qx, 0), np.maximum(qz, 0)) + np.minimum(np.maximum(qx, qz), 0) - c


def value_noise(spacing, seed):
    rng = np.random.default_rng(seed)
    n = int(2 * R / spacing) + 4
    grid = rng.random((n, n)).astype(np.float32)
    def sample(x, z):
        xs, zs = np.atleast_1d(np.asarray(x, np.float64)), np.atleast_1d(np.asarray(z, np.float64))
        out = ndimage.map_coordinates(grid, [(zs + R) / spacing + 1, (xs + R) / spacing + 1], order=3, mode="nearest")
        return out if np.ndim(x) else float(out[0])
    return sample


def poisson_disc(radius, rmax, rng, k=20):
    """Bridson sampling in a disc."""
    cell = radius / math.sqrt(2)
    n = int(2 * rmax / cell) + 2
    grid = -np.ones((n, n), np.int64)
    pts = []
    active = []

    def gi(p):
        return int((p[0] + rmax) / cell), int((p[1] + rmax) / cell)
    p0 = np.array([0.0, 0.0])
    pts.append(p0); active.append(0); grid[gi(p0)] = 0
    while active:
        i = active[rng.integers(len(active))]
        base = pts[i]
        found = False
        for _ in range(k):
            a = rng.random() * 2 * math.pi
            d = radius * (1 + rng.random())
            q = base + d * np.array([math.cos(a), math.sin(a)])
            if np.hypot(*q) > rmax:
                continue
            cx, cy = gi(q)
            ok = True
            for yy in range(max(cy - 2, 0), min(cy + 3, n)):
                for xx in range(max(cx - 2, 0), min(cx + 3, n)):
                    j = grid[xx, yy]
                    if j >= 0 and np.hypot(*(pts[j] - q)) < radius:
                        ok = False
                        break
                if not ok:
                    break
            if ok:
                grid[cx, cy] = len(pts)
                pts.append(q); active.append(len(pts) - 1)
                found = True
                break
        if not found:
            active.remove(i)
    return np.array(pts)


class Spacing:
    """Spatial hash refusing a new item that overlaps an existing one."""

    def __init__(self, cell=4.0):
        self.cell = cell
        self.items = {}

    def ok(self, x, z, r):
        cx, cz = int(math.floor(x / self.cell)), int(math.floor(z / self.cell))
        reach = int(math.ceil((r + 6.0) / self.cell))
        for i in range(cx - reach, cx + reach + 1):
            for j in range(cz - reach, cz + reach + 1):
                for (ox, oz, orad) in self.items.get((i, j), ()):
                    if (ox - x) ** 2 + (oz - z) ** 2 < (orad + r) ** 2:
                        return False
        return True

    def add(self, x, z, r):
        key = (int(math.floor(x / self.cell)), int(math.floor(z / self.cell)))
        self.items.setdefault(key, []).append((x, z, r))


# ------------------------------------------------------------------ atlas
def build_atlas():
    sprites = {}
    files = []
    for sp, d in SPECIES.items():
        sprites[sp] = []
        for pattern in d["sprites"]:
            for f in sorted((ROOT / "assets").glob(pattern)):
                sprites[sp].append(len(files))
                files.append(f)
        if not sprites[sp]:
            sys.exit(f"no sprites for {sp}: run tools/build_assets.py")
    ims = [Image.open(f).convert("RGBA") for f in files]
    pad = 8
    W = 1024
    order = sorted(range(len(ims)), key=lambda i: -ims[i].height)
    rects = [None] * len(ims)
    x = y = shelf = 0
    for i in order:
        w, h = ims[i].width + 2 * pad, ims[i].height + 2 * pad
        if x + w > W:
            x, y, shelf = 0, y + shelf, 0
        rects[i] = (x + pad, y + pad, ims[i].width, ims[i].height)
        x += w
        shelf = max(shelf, h)
    H = 1 << int(math.ceil(math.log2(y + shelf)))
    atlas = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    for i, im in enumerate(ims):
        rx, ry, w, h = rects[i]
        # edge colours smeared into the padding so mipmaps don't bleed neighbours in
        padded = np.asarray(im).copy()
        padded = np.pad(padded, ((pad, pad), (pad, pad), (0, 0)), mode="edge")
        padded[..., 3] = np.pad(np.asarray(im)[..., 3], pad)
        atlas.paste(Image.fromarray(padded, "RGBA"), (rx - pad, ry - pad))
    atlas.save(ROOT / "assets/terrain/scatter_atlas.png", optimize=True)
    uv = [(rx / W, ry / H, (rx + w) / W, (ry + h) / H, w / h) for (rx, ry, w, h) in rects]
    return sprites, uv, files


# ------------------------------------------------------------------ scatter
def main():
    rng = np.random.default_rng(SEED)
    sprites, uv, files = build_atlas()
    hgrid, hstep, horigin = load_heights()

    def height(x, z):
        return float(ndimage.map_coordinates(hgrid, [[(z - horigin) / hstep], [(x - horigin) / hstep]], order=1, mode="nearest")[0])

    def hollow(x, z, d=6.0):
        h = height(x, z)
        return (height(x - d, z) + height(x + d, z) + height(x, z - d) + height(x, z + d)) / 4.0 - h

    fert = value_noise(160.0, SEED + 1)
    fert2 = value_noise(45.0, SEED + 2)
    space = Spacing()
    inst = []
    counts = {k: 0 for k in SPECIES}

    def place(sp, x, z, scale_t):
        d = SPECIES[sp]
        dist = math.hypot(x, z)
        if dist > min(d["view"], R * 0.97):
            return False
        sdf = float(pad_sdf(np.array(x), np.array(z)))
        if sdf < CLEAR and sp not in ("grass", "pebble"):
            return False
        if sdf < CLEAR * 0.45:
            return False
        lo, hi = d["h"]
        h = (lo + (hi - lo) * scale_t) * rng.uniform(0.88, 1.12)
        si = sprites[sp][rng.integers(len(sprites[sp]))]
        u0, v0, u1, v1, aspect = uv[si]
        w = h * aspect
        if not space.ok(x, z, w * 0.5 * d["space"]):
            return False
        space.add(x, z, w * 0.5 * d["space"])
        y = height(x, z) - h * d["sink"]
        flip = rng.random() < 0.5
        if flip:
            u0, u1 = u1, u0
        inst.append((x, y, z, w, h, u0, v0, u1, v1))
        counts[sp] += 1
        return True

    # patches, biggest members first so they claim the middle
    centres = poisson_disc(PATCH_SPACING, R * 0.97, rng)
    kinds = list(PATCHES)
    weights = np.array([PATCHES[k]["w"] for k in kinds])
    for (cx, cz) in centres:
        if float(pad_sdf(np.array(cx), np.array(cz))) < CLEAR + 4:
            continue
        f = float(fert(cx, cz)) * 0.7 + float(fert2(cx, cz)) * 0.3
        f += max(0.0, min(hollow(cx, cz), 1.5)) * 0.25
        if rng.random() > smooth(0.12, 0.5, f):
            continue
        kind = kinds[rng.choice(len(kinds), p=weights / weights.sum())]
        p = PATCHES[kind]
        pr = rng.uniform(*p["r"]) * (0.8 + 0.5 * f)
        members = []
        for sp, (lo, hi) in p["m"].items():
            n = int(round(rng.uniform(lo, hi) * (0.9 + 0.9 * f)))
            members += [sp] * n
        # big species first, so they take the centre
        members.sort(key=lambda s: -SPECIES[s]["h"][1])
        for sp in members:
            for _try in range(6):
                r = abs(rng.normal(0.0, 0.5)) * pr
                a = rng.random() * 2 * math.pi
                x, z = cx + r * math.cos(a), cz + r * math.sin(a)
                # radial size gradient: centre individuals are the largest
                t = max(0.0, 1.0 - (r / pr) * 0.75) * rng.uniform(0.75, 1.0)
                if place(sp, x, z, t):
                    break

    # singles between the patches
    n_single = int(math.pi * R * R * SINGLE_DENSITY)
    names = list(SINGLES)
    sw = np.array([SINGLES[k] for k in names])
    for _ in range(n_single):
        a = rng.random() * 2 * math.pi
        dist = math.sqrt(rng.random()) * R * 0.97
        x, z = dist * math.cos(a), dist * math.sin(a)
        sp = names[rng.choice(len(names), p=sw / sw.sum())]
        place(sp, x, z, rng.random() ** 1.6)

    arr = np.array(inst, np.float32)
    # nearest first: front-to-back draw order helps the GPU reject hidden fragments
    arr = arr[np.argsort(np.hypot(arr[:, 0], arr[:, 2]))]
    import gzip
    packed = gzip.compress(arr.tobytes(), 9)
    with open(OUT_BAKE / "scatter.bin", "wb") as fh:
        fh.write(b"SCT2")
        fh.write(np.array([len(arr), 9, len(packed)], np.uint32).tobytes())
        fh.write(packed)
    stats = {"instances": len(arr), "patches": int(len(centres)), "species": counts,
             "atlas": "scatter_atlas.png", "sprites": [str(f.relative_to(ROOT / "assets")) for f in files]}
    (OUT_BAKE / "scatter.json").write_text(json.dumps(stats, indent=2))
    print(json.dumps({k: stats[k] for k in ("instances", "patches", "species")}))


def smooth(a, b, x):
    t = min(max((x - a) / (b - a), 0.0), 1.0)
    return t * t * (3 - 2 * t)


if __name__ == "__main__":
    main()
