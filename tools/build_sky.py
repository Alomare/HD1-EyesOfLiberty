"""Builds the skies of the sky fix, in res/: one per time of day (dawn, day, dusk, night).

Usage: python tools/build_sky.py [--preview]

Each sky is the dome the engine keeps for its editor (core/editor_slave/units/skydome/skydome, a
hemisphere 500 m across with a skirt below the horizon), taken here from Photo Mode's copy of it, with
three changes:
  - its texture coordinates are rewritten as a disk seen from below: the zenith in the middle, the
    horizon on a ring at HORIZON_R, the skirt out to the edge. The texture then holds the whole sky
    once, with no seam and no tiling
  - its material and texture are named unleashedcamera/sky/<time>, so they never clash with Photo Mode
  - the texture is drawn here, direction by direction: a sky that brightens toward the horizon, a sun
    with a glow, two layers of cloud on flat planes seen in perspective (thick low cloud and thin high
    streaks), haze toward the horizon, and stars at night. DXT1 with every mip, 2048 square.

The sun sits at azimuth 0 of the texture (+x of the dome); src/view.lua turns the dome so the glow sits
where the level's sun is, when the game tells.

Needs numpy and Pillow (13 or later, for DXT1). Writes res/sky_<time>.unit, .material and .texture, and
internal/sky_preview.png (each sky as seen from the ground, looking toward the sun and away).
"""
import io
import math
import struct
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
RES = ROOT / "res"
PHOTO = ROOT.parent / "PhotoMode" / "res"
SIZE = 2048
HORIZON_R = 0.44        # the horizon's ring in the texture (0.5 is the edge)
SKIRT_DEG = 18.0        # degrees below the horizon the edge of the texture stands for
TIMES = ["dawn", "day", "dusk", "night"]


def murmur64(data, seed=0):
    m, r, mask = 0xc6a4a7935bd1e995, 47, (1 << 64) - 1
    h = (seed ^ (len(data) * m)) & mask
    tail = len(data) & ~7
    for (k,) in struct.iter_unpack("<Q", data[:tail]):
        k = (k * m) & mask
        k ^= k >> r
        k = (k * m) & mask
        h = ((h ^ k) * m) & mask
    rest = data[tail:]
    if rest:
        h = ((h ^ int.from_bytes(rest, "little")) * m) & mask
    h ^= h >> r
    h = (h * m) & mask
    return h ^ (h >> r)


def replace_u64(data, old, new, expect=1):
    out, found, i = bytearray(data), 0, 0
    old_b, new_b = struct.pack("<Q", old), struct.pack("<Q", new)
    while True:
        i = out.find(old_b, i)
        if i < 0:
            break
        out[i:i + 8] = new_b
        found += 1
        i += 8
    if found != expect:
        raise SystemExit(f"expected {expect} of {old:016x}, found {found}")
    return bytes(out)


# The dome --------------------------------------------------------------------------------------------

def disk_uv(x, y, z):
    """Texture coordinates of a direction (any length) on the disk."""
    length = math.sqrt(x * x + y * y + z * z) or 1.0
    elevation = math.degrees(math.asin(max(-1.0, min(1.0, z / length))))
    azimuth = math.atan2(y, x)
    if elevation >= 0:
        r = HORIZON_R * (1 - elevation / 90.0)
    else:
        r = HORIZON_R + (0.5 - HORIZON_R) * min(1.0, -elevation / SKIRT_DEG)
    return 0.5 + r * math.cos(azimuth), 0.5 + r * math.sin(azimuth)


def remap_uvs(unit):
    """The unit with every vertex's first texture coordinates set by disk_uv (format 144, one geometry;
    see Minediver core/src/unit.rs for the layout)."""
    out = bytearray(unit)
    version, geometries = struct.unpack_from("<II", unit, 0)
    if version != 144 or geometries != 1:
        raise SystemExit(f"unexpected dome: version {version}, {geometries} geometries")
    p = 8
    (vbytes,) = struct.unpack_from("<I", unit, p)
    p += 4
    at = p
    p += vbytes + 8
    count, stride, channels = struct.unpack_from("<III", unit, p)
    p += 12
    pos_off = uv_off = None
    o = 0
    for _ in range(channels):
        semantic, fmt, layer = struct.unpack_from("<III", unit, p)
        p += 17
        if semantic == 0 and fmt == 2:
            pos_off = o
        if semantic == 4 and fmt == 1 and layer == 0 and uv_off is None:
            uv_off = o
        o += 4 * (fmt + 1)
    if pos_off is None or uv_off is None or o != stride:
        raise SystemExit("the dome has no position or texture coordinates where expected")
    for i in range(count):
        base = at + i * stride
        x, y, z = struct.unpack_from("<3f", unit, base + pos_off)
        u, v = disk_uv(x, y, z)
        struct.pack_into("<2f", out, base + uv_off, u, v)
    return bytes(out)


# Drawing ---------------------------------------------------------------------------------------------

def smoothstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def tiling_noise(rng, cells, size):
    lattice = rng.random((cells, cells)).astype(np.float32)
    big = Image.fromarray(np.tile(lattice, (3, 3)) * 255).convert("F")
    big = big.resize((size * 3, size * 3), Image.Resampling.BICUBIC)
    return np.asarray(big)[size:size * 2, size:size * 2] / 255.0


def fbm(rng, size, base, octaves, gain=0.5):
    total, weight, norm = np.zeros((size, size), np.float32), 1.0, 0.0
    for o in range(octaves):
        total += tiling_noise(rng, base * 2 ** o, size) * weight
        norm += weight
        weight *= gain
    return total / norm


def sample(field, x, y):
    """Bilinear, wrapping: field indexed [y, x] in texels."""
    n = field.shape[0]
    x0, y0 = np.floor(x).astype(np.int64), np.floor(y).astype(np.int64)
    fx, fy = x - x0, y - y0
    x0, y0 = x0 % n, y0 % n
    x1, y1 = (x0 + 1) % n, (y0 + 1) % n
    a = field[y0, x0] * (1 - fx) + field[y0, x1] * fx
    b = field[y1, x0] * (1 - fx) + field[y1, x1] * fx
    return a * (1 - fy) + b * fy


def directions(size):
    """Each texel's direction and elevation (degrees)."""
    c = (np.arange(size, dtype=np.float64) + 0.5) / size - 0.5
    dx, dy = np.meshgrid(c, c)        # [row = v, column = u]
    r = np.sqrt(dx * dx + dy * dy)
    az = np.arctan2(dy, dx)
    el = np.where(r <= HORIZON_R, 90.0 * (1 - r / HORIZON_R), -SKIRT_DEG * np.clip((r - HORIZON_R) / (0.5 - HORIZON_R), 0, 1))
    e = np.radians(el)
    d = np.stack([np.cos(e) * np.cos(az), np.cos(e) * np.sin(az), np.sin(e)], axis=-1)
    return d, el


# Each time of day: colours as linear 0..1 RGB (written out in sRGB), the sun's elevation and size.
LOOKS = {
    "day": dict(zenith=(0.05, 0.17, 0.52), horizon=(0.55, 0.67, 0.82), ground=(0.50, 0.52, 0.55),
                sun_el=52, sun=(1.0, 0.96, 0.88), glow=0.35, halo=0.18, disk=1.0,
                cloud_lit=(1.0, 0.99, 0.97), cloud_dark=(0.42, 0.47, 0.56), cover=0.48, high=0.35, stars=0.0),
    "dawn": dict(zenith=(0.10, 0.16, 0.40), horizon=(0.85, 0.55, 0.40), ground=(0.40, 0.33, 0.33),
                 sun_el=5, sun=(1.0, 0.70, 0.40), glow=0.9, halo=0.45, disk=1.0,
                 cloud_lit=(1.0, 0.68, 0.50), cloud_dark=(0.30, 0.26, 0.40), cover=0.36, high=0.55, stars=0.0),
    "dusk": dict(zenith=(0.06, 0.08, 0.26), horizon=(0.85, 0.40, 0.22), ground=(0.30, 0.22, 0.24),
                 sun_el=3, sun=(1.0, 0.52, 0.22), glow=1.0, halo=0.5, disk=1.0,
                 cloud_lit=(1.0, 0.50, 0.30), cloud_dark=(0.22, 0.16, 0.30), cover=0.40, high=0.6, stars=0.15),
    "night": dict(zenith=(0.0008, 0.0015, 0.006), horizon=(0.008, 0.011, 0.022), ground=(0.006, 0.007, 0.011),
                  sun_el=35, sun=(0.75, 0.82, 1.0), glow=0.10, halo=0.05, disk=0.55,
                  cloud_lit=(0.030, 0.036, 0.055), cloud_dark=(0.005, 0.006, 0.010), cover=0.30, high=0.2, stars=1.0),
}


def to_srgb(c):
    c = np.clip(c, 0, 1)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * np.power(c, 1 / 2.4) - 0.055)


def draw(name, size=SIZE, seed=7):
    look = LOOKS[name]
    rng = np.random.default_rng(seed)
    d, el = directions(size)
    up = np.clip(el, 0, 90) / 90.0
    se = math.radians(look["sun_el"])
    sun = np.array([math.cos(se), 0.0, math.sin(se)])
    cos_g = np.clip(d @ sun, -1, 1)
    gamma = np.arccos(cos_g)

    # Sky: zenith to horizon, the horizon band narrow; warmer and brighter toward the sun.
    zen, hor, gnd = (np.array(look[k]) for k in ("zenith", "horizon", "ground"))
    t = np.power(1 - up, 3.2)[..., None]
    sky = zen * (1 - t) + hor * t
    toward = (0.5 + 0.5 * cos_g)[..., None]
    sky = sky * (0.85 + 0.3 * toward)
    sunc = np.array(look["sun"])
    glow = look["glow"] * np.exp(-gamma / 0.45) * np.power(1 - up, 1.5) + look["halo"] * np.exp(-gamma / 0.12)
    sky = sky + sunc * glow[..., None]
    # Below the horizon: into a haze the colour of the far ground.
    below = smoothstep(0, -6, el)[..., None]
    sky = sky * (1 - below) + (gnd * 0.6 + hor * 0.4) * below

    # Stars, thinning toward the horizon, and a faint band across the sky.
    if look["stars"] > 0:
        stars = np.zeros((size, size), np.float32)
        n = 9000
        ys, xs = rng.integers(0, size, n), rng.integers(0, size, n)
        stars[ys, xs] = (rng.random(n) ** 4) * 0.9 + 0.08
        # A few brighter ones, a texel round.
        for i in rng.integers(0, n, 300):
            y, x = int(ys[i]), int(xs[i])
            if 1 <= y < size - 1 and 1 <= x < size - 1:
                stars[y - 1:y + 2, x - 1:x + 2] = np.maximum(stars[y - 1:y + 2, x - 1:x + 2], 0.22)
                stars[y, x] = 1.0
        fade = smoothstep(2, 25, el) * look["stars"]
        band_axis = np.array([0.3, 0.8, 0.52])
        band_axis /= np.linalg.norm(band_axis)
        band = np.exp(-np.square(d @ band_axis) / 0.04) * fbm(rng, size, 6, 5) * 0.05 * fade
        sky = sky + (stars * fade)[..., None] * np.array([0.85, 0.9, 1.0]) + band[..., None] * np.array([0.6, 0.65, 0.85])

    # Clouds: low thick cloud on a plane 1.5 km up, high thin streaks at 7 km, both seen in perspective.
    low_field = fbm(rng, 1024, 4, 7, 0.55)
    detail = fbm(rng, 1024, 32, 4, 0.5)
    high_field = fbm(rng, 1024, 3, 6, 0.6)
    sin_e = np.maximum(np.sin(np.radians(el)), 1e-3)
    above = smoothstep(0.3, 4, el)

    def layer(height, field, span, stretch, cover, softness, amount):
        dist = height / sin_e                       # metres along the view to the plane
        px, py = d[..., 0] * dist, d[..., 1] * dist
        tx, ty = px / span * field.shape[0], py / (span * stretch) * field.shape[0]
        v = sample(field, tx, ty)
        edge = float(np.quantile(field, 1 - cover))
        dens = smoothstep(edge, edge + softness, v) * above * amount
        # Far cloud fades into the haze, and sky shows through the thinnest.
        haze = np.exp(-dist / 60000.0)
        return dens * haze, v, dist, tx, ty

    lit, dark = np.array(look["cloud_lit"]), np.array(look["cloud_dark"])
    dens, v, dist, tx, ty = layer(1500.0, low_field, 9000.0, 1.0, look["cover"], 0.09, 1.0)
    # Lit from the sun's side: the noise a little toward the sun is thinner where light comes through.
    toward_sun = sample(low_field, tx + 4, ty) - v
    shade = np.clip(0.6 - toward_sun * 8 + (sample(detail, tx * 4, ty * 4) - 0.5) * 0.6, 0, 1)
    rim = np.exp(-gamma / 0.25) * 0.8
    ccol = dark * (1 - shade[..., None]) + lit * shade[..., None] + sunc * rim[..., None] * (1 - dens[..., None]) * 0.6
    ccol = ccol * (0.9 + 0.2 * toward)
    # Cloud near the horizon takes the horizon colour.
    far = smoothstep(4000, 40000, dist)[..., None]
    ccol = ccol * (1 - far * 0.65) + hor * far * 0.65
    sky = sky * (1 - dens[..., None]) + ccol * dens[..., None]

    hdens, *_ = layer(7000.0, high_field, 60000.0, 4.0, look["high"], 0.25, 0.45)
    hcol = lit * 0.9 + sunc * np.exp(-gamma / 0.35)[..., None] * 0.4
    sky = sky * (1 - hdens[..., None]) + hcol * hdens[..., None]

    # The sun's disk, over thin cloud only.
    disk = np.exp(-np.square(gamma / 0.012)) * look["disk"] * (1 - dens) * (1 - below[..., 0])
    sky = sky + sunc * disk[..., None] * 3

    rgb = to_srgb(sky)
    # A little noise breaks up the steps DXT1 leaves in a smooth gradient.
    rgb = rgb + (rng.random(rgb.shape) - 0.5) * (2.0 / 255.0)
    return (np.clip(rgb, 0, 1) * 255 + 0.5).astype(np.uint8)


# Writing ---------------------------------------------------------------------------------------------

def dxt1_texture(rgb):
    """DXT1 DDS with every mip, and the four-byte category every texture resource ends with."""
    image = Image.fromarray(rgb, "RGB")
    mips = [image]
    while mips[-1].size[0] > 1:
        w, h = mips[-1].size
        mips.append(mips[-1].resize((max(1, w // 2), max(1, h // 2)), Image.Resampling.BOX))
    body = bytearray()
    for m in mips:
        if m.size[0] < 4:
            m = m.resize((4, 4), Image.Resampling.BOX)
        buf = io.BytesIO()
        m.save(buf, "DDS", pixel_format="DXT1")
        data = buf.getvalue()
        body += data[128:]
    w = rgb.shape[1]
    header = bytearray(128)
    header[:4] = b"DDS "
    # size, flags (caps, height, width, pixel format, mipmap count, linear size), height, width,
    # linear size, depth, mip count
    struct.pack_into("<IIIIIII", header, 4, 124, 0x000A1007, w, w, max(1, w // 4) * max(1, w // 4) * 8, 0, len(mips))
    struct.pack_into("<II4sIIIII", header, 76, 32, 0x4, b"DXT1", 0, 0, 0, 0, 0)
    struct.pack_into("<I", header, 108, 0x00401008)     # caps: complex, texture, mipmap
    return bytes(header) + bytes(body) + bytes(4)


def preview(rgb, name):
    """The sky as seen from the ground: toward the sun and away, 60 degrees across."""
    h, w = 160, 320
    out = []
    for yaw in (0.0, 180.0):
        ys, xs = np.mgrid[0:h, 0:w]
        fx = (xs - w / 2) / (w / 2) * math.tan(math.radians(30))
        fy = (h / 2 - ys) / (w / 2) * math.tan(math.radians(30)) + 0.18
        yr = math.radians(yaw)
        # forward along +x turned by yaw, up z
        dx = np.cos(yr) - fx * np.sin(yr)
        dy = np.sin(yr) + fx * np.cos(yr)
        dz = fy
        n = np.sqrt(dx * dx + dy * dy + dz * dz)
        el = np.degrees(np.arcsin(dz / n))
        az = np.arctan2(dy, dx)
        r = np.where(el >= 0, HORIZON_R * (1 - el / 90), HORIZON_R + (0.5 - HORIZON_R) * np.clip(-el / SKIRT_DEG, 0, 1))
        u = ((0.5 + r * np.cos(az)) * rgb.shape[1]).astype(int).clip(0, rgb.shape[1] - 1)
        v = ((0.5 + r * np.sin(az)) * rgb.shape[0]).astype(int).clip(0, rgb.shape[0] - 1)
        out.append(rgb[v, u])
    return np.concatenate(out, axis=1)


def main():
    RES.mkdir(exist_ok=True)
    source_unit = (PHOTO / "sky_day.unit").read_bytes()
    source_material = (PHOTO / "sky_day.material").read_bytes()
    unit = remap_uvs(source_unit)
    sheets = []
    for name in TIMES:
        base = f"unleashedcamera/sky/{name}"
        rgb = draw(name)
        (RES / f"sky_{name}.texture").write_bytes(dxt1_texture(rgb))
        material = replace_u64(source_material, murmur64(b"photomode/sky/day_map"), murmur64((base + "_map").encode()))
        (RES / f"sky_{name}.material").write_bytes(material)
        (RES / f"sky_{name}.unit").write_bytes(replace_u64(unit, murmur64(b"photomode/sky/day"), murmur64(base.encode())))
        sheets.append(preview(rgb, name))
        print("sky", name)
    if True:
        (ROOT / "internal").mkdir(exist_ok=True)
        Image.fromarray(np.concatenate(sheets, axis=0)).save(ROOT / "internal" / "sky_preview.png")


if __name__ == "__main__":
    main()
