"""Makes the plain shapes HME's interface is drawn with (white, tinted in game):

    python tools/make_ui_art.py

Writes HarvestMateEnhanced/Media/UI/*.tga (32-bit, uncompressed, power-of-two sizes,
as the game wants): a rounded rectangle and its outline (drawn as nine slices, so any
size keeps its corners), a 2:1 pill for switches, a circle, a chevron and a soft shadow. Drawn at 8x and scaled
down for smooth edges. Needs Pillow. Generated here, so no third-party art is used.

0.4.0's field-atlas look adds: Topo (contour lines, the header and hero cards), Glow (a soft
light), Medallion (a ring that frames profession icons), Pip (a diamond for confidence),
Compass (a compass star for empty states) and Tick (a corner ornament).
"""
import os

from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "HarvestMateEnhanced", "Media", "UI")
SS = 8  # supersampling


def save(img, name):
    os.makedirs(OUT, exist_ok=True)
    img.save(os.path.join(OUT, name + ".tga"), compression=None)
    print("wrote", name)


def big(size):
    return Image.new("RGBA", (size * SS, size * SS), (255, 255, 255, 0))


def small(img, size):
    return img.resize((size, size), Image.LANCZOS)


def rounded(size=32, radius=6):
    img = big(size)
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([0, 0, size * SS - 1, size * SS - 1], radius=radius * SS, fill=(255, 255, 255, 255))
    return small(img, size)


def outline(size=32, radius=6, width=1):
    img = big(size)
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([0, 0, size * SS - 1, size * SS - 1], radius=radius * SS, outline=(255, 255, 255, 255), width=width * SS)
    return small(img, size)


def track(w=64, h=32):
    img = Image.new("RGBA", (w * SS, h * SS), (255, 255, 255, 0))
    ImageDraw.Draw(img).rounded_rectangle([0, 0, w * SS - 1, h * SS - 1], radius=h * SS // 2, fill=(255, 255, 255, 255))
    return img.resize((w, h), Image.LANCZOS)


def circle(size=32):
    img = big(size)
    ImageDraw.Draw(img).ellipse([0, 0, size * SS - 1, size * SS - 1], fill=(255, 255, 255, 255))
    return small(img, size)


def chevron(size=16):
    img = big(size)
    s = size * SS
    ImageDraw.Draw(img).line([(s * 0.25, s * 0.38), (s * 0.5, s * 0.63), (s * 0.75, s * 0.38)], fill=(255, 255, 255, 255),
                             width=int(s * 0.12), joint="curve")
    return small(img, size)


def shadow(size=64, inset=16, blur=7):
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ImageDraw.Draw(img).rounded_rectangle([inset, inset, size - inset - 1, size - inset - 1], radius=6, fill=(0, 0, 0, 255))
    alpha = img.split()[3].filter(ImageFilter.GaussianBlur(blur))
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    out.putalpha(alpha)
    return out


def topo(w=512, h=128, bands=13, seed=7):
    """Contour lines of a smooth made-up landscape: white lines on transparent."""
    import math
    import random
    rnd = random.Random(seed)
    bumps = [(rnd.uniform(-0.2, 1.2) * w, rnd.uniform(-0.3, 1.3) * h, rnd.uniform(0.12, 0.35) * w, rnd.uniform(-1, 1))
             for _ in range(9)]
    W2, H2 = w * 2, h * 2
    img = Image.new("L", (W2, H2), 0)
    px = img.load()
    for y in range(H2):
        for x in range(W2):
            X, Y = x / 2, y / 2
            v = 0.0
            for bx, by, r, a in bumps:
                d2 = ((X - bx) ** 2 + ((Y - by) * 1.6) ** 2) / (r * r)
                v += a * math.exp(-d2)
            v += 0.15 * math.sin(X / w * 6.3 + Y / h * 1.7)
            f = (v * bands) % 1.0
            dist = min(f, 1 - f)            # distance to the nearest contour, in band units
            g = abs(v * bands - round(v * bands))
            a = max(0.0, 1 - dist / 0.06)
            px[x, y] = int(255 * a)
    alpha = img.resize((w, h), Image.LANCZOS)
    out = Image.new("RGBA", (w, h), (255, 255, 255, 0))
    out.putalpha(alpha)
    return out


def glow(size=64):
    img = Image.new("L", (size, size), 0)
    ImageDraw.Draw(img).ellipse([size * 0.2, size * 0.2, size * 0.8, size * 0.8], fill=255)
    alpha = img.filter(ImageFilter.GaussianBlur(size * 0.14))
    out = Image.new("RGBA", (size, size), (255, 255, 255, 0))
    out.putalpha(alpha)
    return out


def medallion(size=64, ring=3):
    img = big(size)
    d = ImageDraw.Draw(img)
    s = size * SS
    d.ellipse([0, 0, s - 1, s - 1], outline=(255, 255, 255, 255), width=ring * SS)
    d.ellipse([s * 0.13, s * 0.13, s * 0.87, s * 0.87], outline=(255, 255, 255, 110), width=SS)
    return small(img, size)


def pip(size=16):
    img = big(size)
    s = size * SS
    ImageDraw.Draw(img).polygon([(s / 2, s * 0.08), (s * 0.92, s / 2), (s / 2, s * 0.92), (s * 0.08, s / 2)], fill=(255, 255, 255, 255))
    return small(img, size)


def compass(size=64):
    import math
    img = big(size)
    d = ImageDraw.Draw(img)
    s = size * SS
    c = s / 2
    for i in range(8):
        ang = i * math.pi / 4
        long_ = i % 2 == 0
        r1 = s * (0.48 if long_ else 0.30)
        r2 = s * 0.08
        tip = (c + math.cos(ang) * r1, c + math.sin(ang) * r1)
        left = (c + math.cos(ang + math.pi / 2) * r2, c + math.sin(ang + math.pi / 2) * r2)
        right = (c + math.cos(ang - math.pi / 2) * r2, c + math.sin(ang - math.pi / 2) * r2)
        d.polygon([tip, left, (c, c)], fill=(255, 255, 255, 255 if long_ else 170))
        d.polygon([tip, right, (c, c)], fill=(255, 255, 255, 190 if long_ else 120))
    d.ellipse([c - s * 0.36, c - s * 0.36, c + s * 0.36, c + s * 0.36], outline=(255, 255, 255, 120), width=SS)
    return small(img, size)


def tick(size=16, width=2):
    img = big(size)
    s = size * SS
    d = ImageDraw.Draw(img)
    d.line([(width * SS / 2, s), (width * SS / 2, width * SS / 2), (s, width * SS / 2)], fill=(255, 255, 255, 255),
           width=width * SS)
    return small(img, size)


if __name__ == "__main__":
    save(rounded(32, 6), "Round")
    save(outline(32, 6, 1), "RoundEdge")
    save(track(64, 32), "Track")
    save(circle(32), "Circle")
    save(chevron(16), "Chevron")
    save(shadow(64), "Shadow")
    save(topo(512, 128), "Topo")
    save(glow(64), "Glow")
    save(medallion(64), "Medallion")
    save(pip(16), "Pip")
    save(compass(64), "Compass")
    save(tick(16), "Tick")
