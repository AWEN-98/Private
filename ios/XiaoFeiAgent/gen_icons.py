#!/usr/bin/env python3
"""Transparent, antialiased 4S SpringBoard icon. No nonstdlib dependencies."""
import math
import struct
import zlib
from pathlib import Path

root = Path(__file__).parent / "Resources"
root.mkdir(parents=True, exist_ok=True)

def icon(size, filename):
    rgba = bytearray()
    for y in range(size):
        rgba.append(0)
        for x in range(size):
            hits = 0
            for sy in (0.17, 0.50, 0.83):
                for sx in (0.17, 0.50, 0.83):
                    u = ((x + sx) / size - .5) * 2
                    v = ((y + sy) / size - .5) * 2
                    ring = abs(math.hypot(u, v) - .68) < .035 and not (u > .32 and v > .32)
                    def bar(cx, half_h):
                        dx = max(0.0, abs(u-cx)-.035)
                        dy = max(0.0, abs(v)-half_h)
                        return math.hypot(dx,dy)<.043
                    if ring or bar(-.29,.12) or bar(0,.29) or bar(.29,.19):
                        hits += 1
            rgba.extend((74,124,255,round(255*hits/9)))
    def chunk(tag, data):
        return struct.pack(">I",len(data))+tag+data+struct.pack(">I",zlib.crc32(tag+data)&0xffffffff)
    png=(b"\x89PNG\r\n\x1a\n"+
         chunk(b"IHDR",struct.pack(">IIBBBBB",size,size,8,6,0,0,0))+
         chunk(b"IDAT",zlib.compress(rgba,9))+
         chunk(b"IEND",b""))
    (root/filename).write_bytes(png)
icon(57,"Icon.png")
icon(114,"Icon@2x.png")
