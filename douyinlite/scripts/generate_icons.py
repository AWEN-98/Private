#!/usr/bin/env python3
"""Generate an original monochrome-line video icon using only Python stdlib."""
import math,os,struct,zlib
BG=(22,23,29); ACCENT=(37,228,216); WHITE=(248,250,252)
def chunk(t,d):return struct.pack(">I",len(d))+t+d+struct.pack(">I",zlib.crc32(t+d)&0xffffffff)
def line(x,y,x1,y1,x2,y2):
 dx=x2-x1;dy=y2-y1
 t=max(0,min(1,((x-x1)*dx+(y-y1)*dy)/(dx*dx+dy*dy)))
 return math.hypot(x-(x1+t*dx),y-(y1+t*dy))
def glyph(x,y):
 frame=(.31<x<.69 and (.18<y<.21 or .79<y<.82)) or (.18<y<.82 and (.30<x<.33 or .67<x<.70))
 triangle=(line(x,y,.45,.39,.45,.61)<.017 or line(x,y,.45,.39,.61,.50)<.017 or line(x,y,.45,.61,.61,.50)<.017)
 return frame or triangle
def draw(w,h,launch=False):
 out=bytearray();samples=2
 for y in range(h):
  out.append(0)
  for x in range(w):
   c=[0,0,0]
   for sy in range(samples):
    for sx in range(samples):
     px=(x+(sx+.5)/samples)/w;py=(y+(sy+.5)/samples)/h
     if launch:
      size=.24;cx=.5;cy=.5
      within=abs(px-cx)<size/2 and abs(py-cy)<size*h/w/2
      u=(px-(cx-size/2))/size
      v=(py-(cy-size*h/w/2))/(size*h/w)
      color=ACCENT if within and glyph(u,v) else BG
     else:color=ACCENT if glyph(px,py) else BG
     for i in range(3):c[i]+=color[i]
   out.extend([round(v/(samples*samples)) for v in c]+[255])
 return b"\x89PNG\r\n\x1a\n"+chunk(b"IHDR",struct.pack(">IIBBBBB",w,h,8,6,0,0,0))+chunk(b"IDAT",zlib.compress(bytes(out),9))+chunk(b"IEND",b"")
os.makedirs("Resources",exist_ok=True)
for name,size in (("Icon.png",57),("Icon@2x.png",114),("Icon-120.png",120)):
 with open("Resources/"+name,"wb") as f:f.write(draw(size,size))
with open("Resources/Default@2x.png","wb") as f:f.write(draw(640,960,True))
print("Generated DouyinLite icon and launch image")
