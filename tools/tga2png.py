"""Converts an uncompressed 32-bit TGA to PNG (for previews; no library).
    python tools/tga2png.py in.tga out.png [scale]
"""
import struct
import sys
import zlib


def main(src, dst, scale=1):
    raw = open(src, "rb").read()
    idlen, _, itype, _, _, _, _, _, w, h, bpp, desc = struct.unpack("<BBBHHBHHHHBB", raw[:18])
    assert itype == 2 and bpp == 32, "only uncompressed 32-bit"
    px = raw[18 + idlen:]
    top_down = bool(desc & 0x20)
    rows = []
    for y in range(h):
        sy = y if top_down else h - 1 - y
        row = bytearray()
        for x in range(w):
            b, g, r, a = px[(sy * w + x) * 4:(sy * w + x) * 4 + 4]
            row += bytes((r, g, b, a)) * scale
        for _ in range(scale):
            rows.append(b"\x00" + bytes(row))

    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xffffffff)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w * scale, h * scale, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(b"".join(rows))) + chunk(b"IEND", b"")
    open(dst, "wb").write(png)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2], int(sys.argv[3]) if len(sys.argv) > 3 else 1)
