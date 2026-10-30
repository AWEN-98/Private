#!/usr/bin/env python3
"""Small antialiased native icon for iOS 8, stdlib only."""
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
            # 3x3 supersampling keeps curved vector marks legible at 57px.
            rr = gg = bb = 0.0
            for sy in (0.17, 0.50, 0.83):
                for sx in (0.17, 0.50, 0.83):
                    u = ((x + sx) / size - .5) * 2
                    v = ((y + sy) / size - .5) * 2
                    radial = min(1, math.hypot(u, v))
                    bg = (14 + 12 * radial, 49 - 7 * radial, 39 - 2 * radial)
                    # A phosphor ring and three uneven bars: XiaoFei's voice identity.
                    ring = abs(math.hypot(u, v) - .655) < .029
                    # Small open segment gives the monogram a distinct silhouette.
                    ring = ring and not (u > .30 and v > .31)
                    # Rounded vertical sound bars.
                    def bar(cx, half_h):
                        dx = max(0.0, abs(u-cx)-.070)
                        dy = max(0.0, abs(v)-half_h)
                        return math.hypot(dx,dy)<.050
                    mark = ring or bar(-.29,.12) or bar(0,.29) or bar(.29,.19)
                    # Glowing dot just outside upper-right voice ring.
                    spark = math.hypot(u-.61,v+.56)<.055
                    fg = (232,255,240) if mark else (105,236,170)
                    color = fg if mark or spark else bg
                    rr+=color[0];gg+=color[1];bb+=color[2]
            rgba.extend((round(rr/9),round(gg/9),round(bb/9),255))
    def chunk(tag, data):
        return struct.pack(">I",len(data))+tag+data+struct.pack(">I",zlib.crc32(tag+data)&0xffffffff)
    png=(b"\x89PNG\r\n\x1a\n"+
         chunk(b"IHDR",struct.pack(">IIBBBBB",size,size,8,6,0,0,0))+
         chunk(b"IDAT",zlib.compress(rgba,9))+
         chunk(b"IEND",b""))
    (root/filename).write_bytes(png)
icon(57,"Icon.png")
icon(114,"Icon@2x.png")
