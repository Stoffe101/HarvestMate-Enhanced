"""Makes the plain shapes HME's interface is drawn with (white, tinted in game):

    python tools/make_ui_art.py

Writes HarvestMateEnhanced/Media/UI/*.tga (32-bit, uncompressed, power-of-two sizes,
as the game wants): a rounded rectangle and its outline (drawn as nine slices, so any
size keeps its corners), a 2:1 pill for switches, a circle, a chevron and a soft shadow. Drawn at 8x and scaled
down for smooth edges. Needs Pillow. Generated here, so no third-party art is used.
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


if __name__ == "__main__":
    save(rounded(32, 6), "Round")
    save(outline(32, 6, 1), "RoundEdge")
    save(track(64, 32), "Track")
    save(circle(32), "Circle")
    save(chevron(16), "Chevron")
    save(shadow(64), "Shadow")
