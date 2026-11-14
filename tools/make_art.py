"""Draws HarvestMate Enhanced's own artwork as TGA files (no image library
needed): the logo, a leaf on a dark disc in a gold ring with an ore nugget.
Original work for this project (GPL-3.0-or-later). From the repo root:

    python tools/make_art.py
"""
import math
import os
import struct

OUT = os.path.join("HarvestMateEnhanced", "Media")


def write_tga(path, size, pixel):
    """pixel(x, y) -> (r, g, b, a) in 0..1, sampled 4x4 per pixel."""
    data = bytearray()
    ss = 4
    for y in range(size - 1, -1, -1):  # TGA rows go bottom-up
        for x in range(size):
            acc = [0.0, 0.0, 0.0, 0.0]
            for sy in range(ss):
                for sx in range(ss):
                    u = (x + (sx + 0.5) / ss) / size
                    v = (y + (sy + 0.5) / ss) / size
                    r, g, b, a = pixel(u, v)
                    acc[0] += r * a
                    acc[1] += g * a
                    acc[2] += b * a
                    acc[3] += a
            n = ss * ss
            a = acc[3] / n
            if a > 0:
                r, g, b = acc[0] / acc[3], acc[1] / acc[3], acc[2] / acc[3]
            else:
                r = g = b = 0
            data += bytes((int(b * 255 + 0.5), int(g * 255 + 0.5), int(r * 255 + 0.5), int(a * 255 + 0.5)))
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, size, size, 32, 8)
    with open(path, "wb") as f:
        f.write(header)
        f.write(data)


def over(dst, src):
    sr, sg, sb, sa = src
    dr, dg, db, da = dst
    a = sa + da * (1 - sa)
    if a == 0:
        return (0, 0, 0, 0)
    return ((sr * sa + dr * da * (1 - sa)) / a, (sg * sa + dg * da * (1 - sa)) / a,
            (sb * sa + db * da * (1 - sa)) / a, a)


def logo(u, v):
    x, y = u - 0.5, v - 0.5
    r = math.hypot(x, y)
    col = (0, 0, 0, 0)
    # dark disc with a soft radial gradient
    if r < 0.47:
        k = r / 0.47
        col = (0.10 + 0.06 * (1 - k), 0.08 + 0.05 * (1 - k), 0.06, 1)
    # gold ring
    if 0.41 < r < 0.48:
        t = 1 - abs(r - 0.445) / 0.035
        col = over(col, (0.98, 0.78 * (0.85 + 0.15 * t), 0.25, 1))
    # leaf: the intersection of two circles, tilted 40 degrees
    a = math.radians(40)
    lx = x * math.cos(a) + y * math.sin(a)
    ly = -x * math.sin(a) + y * math.cos(a)
    lx += 0.04
    d1 = math.hypot(lx, ly - 0.17)
    d2 = math.hypot(lx, ly + 0.17)
    if d1 < 0.27 and d2 < 0.27 and abs(lx) < 0.30:
        shade = 0.55 + 0.45 * (1 - min(1, abs(ly) / 0.10))
        col = over(col, (0.28 * shade, 0.78 * shade, 0.36 * shade, 1))
        if abs(ly) < 0.012 and abs(lx) < 0.22:
            col = over(col, (0.12, 0.42, 0.18, 1))
    # ore nugget, lower right
    nx, ny = x - 0.17, y - 0.19
    if abs(nx) + abs(ny) * 1.2 < 0.10:
        col = over(col, (0.93, 0.56, 0.22, 1))
        if nx - ny > 0.02:
            col = over(col, (1.0, 0.82, 0.45, 0.8))
    return col


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    write_tga(os.path.join(OUT, "Logo.tga"), 64, logo)
    print("wrote", os.path.join(OUT, "Logo.tga"))
