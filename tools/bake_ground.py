#!/usr/bin/env python3
"""Bake the desert floor into three nested top-down ground textures.

    godot --headless --script res://tools/bake_terrain.gd   # first: heights
    python3 tools/bake_ground.py

Reads  build/terrain/height_bake.bin, assets/terrain/desert.json and the ground tiles
in assets_src/ground/<type>/originals/. Writes assets/terrain/ground_{near,mid,far}.png
(and ground.json describing their extents for the terrain shader).

The floor is built in layers, every layer a function of world position so the three
textures agree wherever they overlap:
  1. base sand, the smooth and the rippled tiles traded off by large-scale noise,
  2. terrain-driven dirt: hollows collect it and steep faces show it (mewd-engine's
     IslandField.splat_weights slope / concavity rules, remapped to the desert),
  3. splats: hundreds of irregular sand and dirt patches with noise-wobbled edges and a
     power-law size spread, so the ground reads as many overlapping deposits,
  4. the battery pad: asphalt inside the rounded rectangle, sandy asphalt in a ring
     around it with sand drifting in from the edges.
Layer edges are Bayer-dithered rather than blended (no mud), and the result is dithered
onto the game's 128-colour palette with the same quantiser as tools/build_assets.py.
"""
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_assets as BA  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
CFG = json.loads((ROOT / "assets/terrain/desert.json").read_text())
HEIGHTS = ROOT / "build/terrain/height_bake.bin"
TILES = ROOT / "assets_src/ground"
OUT = ROOT / "assets/terrain"
R = float(CFG["radius"])
PAD = CFG["pad"]
SEED = int(CFG["seed"])

# name, centre, size (m), texels per side
LEVELS = [("near", 0.0, 512.0, 2048), ("mid", 0.0, 1152.0, 1024), ("far", 0.0, 2 * R, 1024)]
# world size of one tile repeat, per ground type (metres)
TILE_M = {"sand": 14.0, "dirt": 11.0, "asphalt": 20.0, "sandy_asphalt": 16.0}
BAYER = BA.BAYER8
DEBUG = "--debug" in sys.argv


# ---------------------------------------------------------------- world-space helpers
class WorldNoise:
    """Smooth value noise on a fixed world lattice, sampled anywhere (cubic)."""

    def __init__(self, spacing: float, seed: int, octaves: int = 1):
        self.layers = []
        rng = np.random.default_rng(seed)
        amp, total = 1.0, 0.0
        for o in range(octaves):
            sp = spacing / (2 ** o)
            n = int(np.ceil(2 * R / sp)) + 4
            self.layers.append((sp, rng.random((n, n)).astype(np.float32), amp))
            total += amp
            amp *= 0.5
        self.total = total

    def __call__(self, x: np.ndarray, z: np.ndarray) -> np.ndarray:
        out = np.zeros(x.shape, np.float32)
        for sp, grid, amp in self.layers:
            u = (x + R) / sp + 1.0
            v = (z + R) / sp + 1.0
            out += amp * ndimage.map_coordinates(grid, [v, u], order=3, mode="nearest")
        return out / self.total     # roughly 0..1


def smoothstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def pad_sdf(x, z):
    c = PAD["corner"]
    qx = np.abs(x) - (PAD["half_x"] - c)
    qz = np.abs(z) - (PAD["half_z"] - c)
    outside = np.hypot(np.maximum(qx, 0), np.maximum(qz, 0))
    return outside + np.minimum(np.maximum(qx, qz), 0) - c


def read_heights(path):
    """Height grid written by tools/bake_terrain.gd: "HGT2" header + gzip float32 rows."""
    import gzip
    raw = path.read_bytes()
    if raw[:4] != b"HGT2":
        sys.exit(f"{path} missing or stale: run tools/bake_terrain.gd")
    size = int(np.frombuffer(raw[4:8], np.uint32)[0])
    step, origin = np.frombuffer(raw[8:16], np.float32)
    n = int(np.frombuffer(raw[16:20], np.uint32)[0])
    h = np.frombuffer(gzip.decompress(raw[20:20 + n]), np.float32).reshape(size, size)
    return h, float(step), float(origin)


def load_heights():
    return read_heights(HEIGHTS)


def load_tiles():
    tiles = {}
    for d in sorted(TILES.iterdir()):
        files = sorted(p for p in (d / "originals").iterdir() if p.suffix.lower() in BA.EXTS)
        tiles[d.name] = [np.asarray(Image.open(p).convert("RGB")).astype(np.float32) / 255.0 for p in files]
    return tiles


PATCHES = 5          # random offsets the tiles are cut from, so repeats never line up


def tile_sampler(tile: np.ndarray, tile_m: float, texel_m: float, seed: int):
    """Pre-shrink a (seamless) tile to the texel size and wrap it. The world is cut into
    irregular patches about a tile across; each patch reads the tile at its own random
    offset, which breaks up the grid a plain repeat shows from the air."""
    px = max(4, int(round(tile_m / texel_m)))
    small = np.asarray(Image.fromarray(np.round(tile * 255).astype(np.uint8)).resize((px, px), Image.LANCZOS)).astype(np.float32) / 255.0
    rng = np.random.default_rng(seed)
    offs = rng.integers(0, px, size=(PATCHES, 2))
    patch_noise = WorldNoise(tile_m * 1.3, seed, 2)

    def sample(x, z):
        k = np.clip((patch_noise(x, z) * PATCHES * 1.6 - 0.3 * PATCHES).astype(np.int64), 0, PATCHES - 1)
        u = (np.floor(x / texel_m).astype(np.int64) + offs[k, 0]) % px
        v = (np.floor(z / texel_m).astype(np.int64) + offs[k, 1]) % px
        return small[v, u]
    return sample


# ---------------------------------------------------------------- splats
def make_splats(rng):
    """Irregular patches: (x, z, radius, kind). Power-law radii, many small, few huge."""
    out = []
    area = (2 * R) ** 2
    for kind, count, rmin, rmax in (("dirt", 900, 2.5, 60.0), ("ripple", 700, 3.0, 70.0),
                                    ("dirt_small", 2600, 0.8, 4.0)):
        n = int(count * area / (2304.0 ** 2))
        # inverse-CDF power law, exponent ~ -2.2 on the radius
        u = rng.random(n)
        a = 1.2
        r = (rmin ** -a - u * (rmin ** -a - rmax ** -a)) ** (-1 / a)
        ang = rng.random(n) * 2 * np.pi
        dist = np.sqrt(rng.random(n)) * R
        out += [(dist[i] * np.cos(ang[i]), dist[i] * np.sin(ang[i]), r[i], kind) for i in range(n)]
    return out


def stamp_splats(splats, kind_prefix, xs, zs, edge_noise, texel_m):
    """Coverage 0..1 of every splat whose kind starts with kind_prefix, on a level grid."""
    n = xs.shape[1]
    x0, z0 = xs[0, 0], zs[0, 0]
    cov = np.zeros(xs.shape, np.float32)
    for (sx, sz, r, kind) in splats:
        if not kind.startswith(kind_prefix):
            continue
        reach = r * 1.4
        i0 = int(np.floor((sx - reach - x0) / texel_m)); i1 = int(np.ceil((sx + reach - x0) / texel_m))
        j0 = int(np.floor((sz - reach - z0) / texel_m)); j1 = int(np.ceil((sz + reach - z0) / texel_m))
        i0, j0 = max(i0, 0), max(j0, 0)
        i1, j1 = min(i1, n), min(j1, n)
        if i1 <= i0 or j1 <= j0:
            continue
        if r < texel_m * 0.75:
            continue
        px = xs[j0:j1, i0:i1]
        pz = zs[j0:j1, i0:i1]
        d = np.hypot(px - sx, pz - sz) / r
        wob = edge_noise(px, pz) - 0.5
        m = smoothstep(1.05, 0.8, d + wob * 0.55)
        cov[j0:j1, i0:i1] = np.maximum(cov[j0:j1, i0:i1], m)
    return cov


# ---------------------------------------------------------------- level bake
def bake_level(name, centre, size, n, tiles, heights, splats):
    texel = size / n
    coords = centre - size / 2 + (np.arange(n, dtype=np.float32) + 0.5) * texel
    xs, zs = np.meshgrid(coords, coords)
    hgrid, hstep, horigin = heights

    # terrain shape at this level: slope and convexity from the height grid (4 m radius)
    def hs(x, z):
        return ndimage.map_coordinates(hgrid, [(z - horigin) / hstep, (x - horigin) / hstep], order=1, mode="nearest")
    d = 4.0
    h = hs(xs, zs)
    hx0, hx1, hz0, hz1 = hs(xs - d, zs), hs(xs + d, zs), hs(xs, zs - d), hs(xs, zs + d)
    nrm_y = 1.0 / np.sqrt(1.0 + ((hx1 - hx0) / (2 * d)) ** 2 + ((hz1 - hz0) / (2 * d)) ** 2)
    slope = 1.0 - nrm_y
    convex = (4 * h - (hx0 + hx1 + hz0 + hz1)) / (2 * d)

    big = WorldNoise(180.0, SEED + 1, 3)
    mid = WorldNoise(40.0, SEED + 2, 2)
    edge = WorldNoise(6.0, SEED + 3, 2)
    drift = WorldNoise(9.0, SEED + 4, 3)
    tone = WorldNoise(70.0, SEED + 5, 2)

    bay = np.tile(BAYER, (n // 8 + 1, n // 8 + 1))[:n, :n]

    def pick(weight):
        """Ordered-dither a 0..1 weight into a hard per-texel choice."""
        return weight > bay

    samp = {k: [tile_sampler(t, TILE_M[k], texel, SEED + 100 * i + j)
                for j, t in enumerate(v)] for i, (k, v) in enumerate(sorted(tiles.items()))}

    smooth_sand = samp["sand"][1](xs, zs)
    ripple_sand = samp["sand"][0](xs, zs)
    dirt_a = samp["dirt"][0](xs, zs)
    dirt_b = samp["dirt"][1](xs, zs)

    # 1. base: smooth sand, ripples where the big noise is high and on dune crests
    ripple_w = smoothstep(0.52, 0.62, big(xs, zs)) + smoothstep(0.02, 0.06, convex) * 0.6
    ripple_w = np.maximum(ripple_w, stamp_splats(splats, "ripple", xs, zs, edge, texel))
    col = np.where(pick(np.clip(ripple_w, 0, 1))[..., None], ripple_sand, smooth_sand)

    # 2. terrain-driven dirt (mewd: soil in hollows, rock band on steep faces)
    soil = smoothstep(0.0, 0.12, -convex) * 0.8
    steep = smoothstep(0.10, 0.22, slope)
    dirt_w = np.maximum(soil, steep)
    # 3. dirt splats, big and small
    dirt_w = np.maximum(dirt_w, stamp_splats(splats, "dirt", xs, zs, edge, texel))
    dirt_w *= smoothstep(0.25, 0.45, mid(xs, zs)) * 0.5 + 0.5
    dirt = np.where(pick(smoothstep(0.35, 0.65, mid(xs, zs)))[..., None], dirt_a, dirt_b)
    col = np.where(pick(np.clip(dirt_w, 0, 1))[..., None], dirt, col)

    # 4. the pad: asphalt, then sandy asphalt, sand drifting over both edges
    sdf = pad_sdf(xs, zs)
    asphalt = samp["asphalt"][0](xs, zs) if len(samp["asphalt"]) < 2 else np.where(
        pick(smoothstep(0.45, 0.55, mid(xs * 3, zs * 3)))[..., None], samp["asphalt"][0](xs, zs), samp["asphalt"][1](xs, zs))
    sa = samp["sandy_asphalt"]
    sandy = sa[0](xs, zs)
    if len(sa) > 1:
        sel = mid(xs * 2.5 + 400, zs * 2.5)
        sandy = np.where((sel > 0.45)[..., None], sa[1](xs, zs), sandy)
        if len(sa) > 2:
            sandy = np.where((sel > 0.6)[..., None], sa[2](xs, zs), sandy)
    dn = drift(xs, zs)
    band = float(PAD["sandy"])
    # sandy asphalt fades out into the desert with a ragged, drifted outer edge
    sandy_w = 1.0 - smoothstep(band * 0.45, band * 1.15, sdf + (dn - 0.5) * band * 0.9)
    col = np.where(pick(np.clip(sandy_w, 0, 1))[..., None], sandy, col)
    # clean asphalt inside, sand-strewn toward its rim
    asph_w = 1.0 - smoothstep(-6.0, 0.5, sdf + (dn - 0.5) * 7.0)
    col = np.where(pick(np.clip(asph_w, 0, 1))[..., None], asphalt, col)

    # broad tone variation so the far desert isn't one flat colour
    t = (tone(xs, zs) - 0.5) * 0.14
    col = np.clip(col * (1.0 + t[..., None]), 0, 1)

    if DEBUG:
        Image.fromarray(np.round(col * 255).astype(np.uint8), "RGB").save(ROOT / f"build/terrain/ground_{name}_raw.png")
    out = BA.palette_dither(col, LUT)
    img = Image.fromarray(np.round(out * 255).astype(np.uint8), "RGB")
    img.save(OUT / f"ground_{name}.png", optimize=True)
    return {"name": name, "centre": [centre, centre], "size": size, "texels": n}


def main():
    global LUT
    LUT = BA.build_lut(BA.load_palette())
    tiles = load_tiles()
    for k in TILE_M:
        if k not in tiles or not tiles[k]:
            sys.exit(f"missing ground tiles: assets_src/ground/{k}/originals")
    heights = load_heights()
    splats = make_splats(np.random.default_rng(SEED))
    info = []
    for name, centre, size, n in LEVELS:
        print(f"ground_{name}: {n}x{n} over {size:.0f} m ({size / n:.2f} m/texel)")
        info.append(bake_level(name, centre, size, n, tiles, heights, splats))
    (OUT / "ground.json").write_text(json.dumps({"levels": info}, indent=2))
    print("done")


if __name__ == "__main__":
    main()
