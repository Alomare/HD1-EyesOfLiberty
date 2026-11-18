"""Builds the HUD art of Eyes of Liberty: three white images the game tints when it draws, and the
gui material that names them.

Usage: python tools/build_hud.py

  eol_idle  the game's idle aim cursor ("hud/cursors/game_inactive", a hardware cursor the shoulder
            view can't show), read from the game through Minediver and kept as it is, 32 by 32
  eol_ring  the ring where a throw lands, white, 256 by 256
  eol_hurt  the edges of the screen for Hurt feedback, white, stretched over the whole window

Writes res/hud_*.texture and res/hud.material, and internal/hud_preview.png. Needs Pillow and numpy,
and Minediver's CLI for the cursor (MINEDIVER, or the debug build beside this project).

The material is a list of records as the game's own gui materials have them (hud/cursors holds one,
cursor_game): the top 32 bits of murmur64 of the sprite name, the template of the game's font
material (it multiplies the texture by the colour of each draw), and the texture as the diffuse map.
"""
import math
import os
import struct
import subprocess
import tempfile
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
RES = ROOT / "res"
BASE = "eyesofliberty/hud"
MATERIAL_VERSION = 10
TEMPLATE, DIFFUSE_MAP, VARIABLE = 0xba25de35, 0x3aa8b87e, 0x46f80ade
MINEDIVER = Path(os.environ.get("MINEDIVER", ROOT.parent.parent.parent / "ProjectMinediver" / "Minediver" / "target" / "debug" / "minediver-cli.exe"))


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


def dds_rgba(image):
    """Uncompressed BGRA with mips, a form the game's own textures take."""
    image = image.convert("RGBA")
    width, height = image.size
    mips = [image]
    while mips[-1].size != (1, 1):
        w, h = mips[-1].size
        mips.append(mips[-1].resize((max(1, w // 2), max(1, h // 2)), Image.Resampling.BOX))
    header = bytearray(128)
    header[:4] = b"DDS "
    struct.pack_into("<IIIIIII", header, 4, 124, 0x0002100F, height, width, width * 4, 0, len(mips))
    struct.pack_into("<II4sIIIII", header, 76, 32, 0x41, b"\0\0\0\0", 32, 0x00FF0000, 0x0000FF00, 0x000000FF, 0xFF000000)
    struct.pack_into("<I", header, 108, 0x00401008)
    body = b""
    for mip in mips:
        r, g, b, a = mip.split()
        body += Image.merge("RGBA", (b, g, r, a)).tobytes()
    return bytes(header) + body + bytes(4)


def white(alpha):
    """A white image with this alpha (floats 0 to 1)."""
    a = (np.clip(alpha, 0, 1) * 255 + 0.5).astype(np.uint8)
    rgb = np.full(a.shape + (3,), 255, np.uint8)
    return Image.fromarray(np.dstack([rgb, a]), "RGBA")


def idle_cursor():
    """The game's own idle cursor, 32 by 32 BGRA after a 20-byte head."""
    with tempfile.TemporaryDirectory() as out:
        subprocess.run([str(MINEDIVER), "extract", "--text", "hud/cursors/game_inactive", "--raw", "-o", out],
                       check=True, capture_output=True)
        found = list(Path(out).rglob("game_inactive.mouse_cursor"))
        data = found[0].read_bytes()
    w, h = struct.unpack_from("<II", data, 0)
    assert (w, h) == (32, 32), (w, h)
    return Image.frombytes("RGBA", (w, h), data[20:20 + w * h * 4], "raw", "BGRA")


def ring(size=256, thickness=0.075):
    """A ring as wide as the image, with soft edges a pixel or two wide."""
    y, x = np.mgrid[0:size, 0:size] + 0.5
    r = np.hypot(x - size / 2, y - size / 2) / (size / 2)
    edge = 1.5 / (size / 2)
    outer, inner = 1 - edge, 1 - edge - thickness
    a = np.clip((outer - r) / edge + 0.5, 0, 1) * np.clip((r - inner) / edge + 0.5, 0, 1)
    return white(a)


def noise(shape, cells, seed):
    """Smooth value noise, cells across the width."""
    rng = np.random.default_rng(seed)
    h, w = shape
    gw, gh = cells + 2, max(2, round(cells * h / w)) + 2
    grid = rng.random((gh, gw))
    y, x = np.mgrid[0:h, 0:w]
    fx, fy = x / w * (gw - 2), y / h * (gh - 2)
    ix, iy = fx.astype(int), fy.astype(int)
    tx, ty = fx - ix, fy - iy
    tx, ty = tx * tx * (3 - 2 * tx), ty * ty * (3 - 2 * ty)
    a = grid[iy, ix] * (1 - tx) + grid[iy, ix + 1] * tx
    b = grid[iy + 1, ix] * (1 - tx) + grid[iy + 1, ix + 1] * tx
    return a * (1 - ty) + b * ty


def hurt(w=512, h=288):
    """The edges of the screen, strongest at the border and the corners, with an uneven inner edge
    that reaches in further in places, like the rim of a wound rather than a smooth vignette."""
    y, x = np.mgrid[0:h, 0:w] + 0.5
    u, v = x / w, y / h
    # Distance to the nearest edge, in heights, so the band is as thick on every side.
    d = np.minimum(np.minimum(u, 1 - u) * (w / h), np.minimum(v, 1 - v))
    # Corners reach further in.
    cu, cv = np.abs(u - 0.5) * 2, np.abs(v - 0.5) * 2
    corner = (cu * cv) ** 2
    reach = 0.16 + 0.10 * corner
    rough = 0.65 * noise((h, w), 9, 7) + 0.35 * noise((h, w), 23, 11)
    reach = reach * (0.7 + 0.6 * rough)
    t = np.clip(1 - d / reach, 0, 1)
    a = t ** 1.8
    # A thin brighter rim at the very border.
    a = np.maximum(a, np.clip(1 - d / 0.012, 0, 1) * 0.9)
    return white(a)


def material(names):
    records = []
    for sprite in names:
        name = murmur64(sprite.encode()) >> 32
        tex = murmur64(f"{BASE}/{sprite}".encode())
        records.append((name, struct.pack("<13I", name, TEMPLATE, 0, 0, 1, DIFFUSE_MAP, tex & 0xFFFFFFFF, tex >> 32, 1, VARIABLE, 0, 0, 0)))
    records.sort()
    return struct.pack("<II", MATERIAL_VERSION, len(records)) + b"".join(r for _, r in records)


def main():
    images = {"eol_idle": idle_cursor(), "eol_ring": ring(), "eol_hurt": hurt()}
    RES.mkdir(exist_ok=True)
    for sprite, image in images.items():
        (RES / f"hud_{sprite[4:]}.texture").write_bytes(dds_rgba(image))
    (RES / "hud.material").write_bytes(material(images))
    # A look at all three over a dark green, the hurt edge tinted as the game draws it.
    preview = Image.new("RGBA", (512 + 256 + 64 + 32, 288), (30, 44, 30, 255))
    tint = Image.new("RGBA", images["eol_hurt"].size, (210, 24, 18, 255))
    tint.putalpha(images["eol_hurt"].getchannel("A"))
    preview.alpha_composite(tint, (0, 0))
    preview.alpha_composite(images["eol_ring"], (512 + 16, 16))
    preview.alpha_composite(images["eol_idle"].resize((64, 64), Image.Resampling.NEAREST), (512 + 256 + 24, 16))
    (ROOT / "internal").mkdir(exist_ok=True)
    preview.save(ROOT / "internal" / "hud_preview.png")
    for sprite in images:
        print(sprite, f"{BASE}/{sprite}", hex(murmur64(f'{BASE}/{sprite}'.encode())))


if __name__ == "__main__":
    main()
