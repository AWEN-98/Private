#!/usr/bin/env python3
import os,struct,zlib
def chunk(k,d):return struct.pack(">I",len(d))+k+d+struct.pack(">I",zlib.crc32(k+d)&0xffffffff)
def png(w,h):
 b=bytearray()
 for y in range(h):
  b.append(0)
  for x in range(w):
   a=x/w;v=y/h
   on=(.19<a<.74 and abs(v-.50)<.055) or (.52<a<.76 and abs(v-(.50+(a-.63)*.64))<.07) or (.52<a<.76 and abs(v-(.50-(a-.63)*.64))<.07)
   b.extend((255,255,255,255) if on else (78,99,205,255))
 return b"\x89PNG\r\n\x1a\n"+chunk(b"IHDR",struct.pack(">IIBBBBB",w,h,8,6,0,0,0))+chunk(b"IDAT",zlib.compress(bytes(b),9))+chunk(b"IEND",b"")
os.makedirs("Resources",exist_ok=True)
for name,size in [("Icon.png",57),("Icon@2x.png",114),("Icon-120.png",120),("Default@2x.png",640)]:
 with open("Resources/"+name,"wb") as f:f.write(png(size,960 if name.startswith("Default") else size))
