#!/usr/bin/env python3
"""Create tiny PNG icons using Python stdlib. Runs during GitHub Actions build."""
import math
import struct
import zlib
from pathlib import Path

root = Path(__file__).parent / "Resources"
root.mkdir(parents=True, exist_ok=True)

def write_icon(size, name):
    raw = bytearray()
    for y in range(size):
        raw.append(0)
        for x in range(size):
            # Purple-blue background and a simple white "AI" orbit symbol.
            nx = (x + 0.5) / size
            ny = (y + 0.5) / size
            r = round(45 + 32 * ny)
            g = round(60 + 42 * (1 - nx))
            b = round(137 + 48 * (1 - ny))
            radius = math.hypot(nx-.5, ny-.5)
            orbit = abs(radius - .31) < .026 and nx < .78
            center = radius < .075
            spark = (abs(nx-.79)<.05 and abs(ny-.24)<.05 and abs(nx-.79)+abs(ny-.24)<.065)
            if orbit or center or spark:
                r,g,b = 245,249,255
            raw.extend((r,g,b,255))
    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag+data)&0xffffffff)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB",size,size,8,6,0,0,0)) + chunk(b"IDAT",zlib.compress(raw,9)) + chunk(b"IEND",b"")
    (root/name).write_bytes(png)

write_icon(57,"Icon.png")
write_icon(114,"Icon@2x.png")
