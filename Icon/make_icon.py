# Ícone do Tocando: um anel com uma nota musical, em roxo e branco.
# Gera icon_1024.png e AppIcon.icns (python3 make_icon.py, dentro da pasta Icon).
import math, os, shutil, subprocess
from PIL import Image, ImageDraw, ImageFilter
SS=4; N=1024*SS
k=824/150*SS; o=100*SS
P=lambda x,y:(o+x*k,o+y*k)
img=Image.new("RGBA",(N,N),(0,0,0,0))
# sombra
sh=Image.new("RGBA",(N,N),(0,0,0,0)); d=ImageDraw.Draw(sh)
d.rounded_rectangle([o,o+12*SS,o+824*SS,o+836*SS],radius=185*SS,fill=(0,0,0,90))
sh=sh.filter(ImageFilter.GaussianBlur(14*SS)); img.alpha_composite(sh)
# corpo: gradiente vertical roxo
body=Image.new("RGBA",(N,N)); bd=ImageDraw.Draw(body)
top=(132,104,255); bot=(78,46,196)
for y in range(o,o+824*SS):
    t=(y-o)/(824*SS); bd.line([(0,y),(N,y)],fill=tuple(int(a+(b-a)*t) for a,b in zip(top,bot))+(255,))
mask=Image.new("L",(N,N),0); ImageDraw.Draw(mask).rounded_rectangle([o,o,o+824*SS,o+824*SS],radius=185*SS,fill=255)
img.paste(body,(0,0),mask)
d=ImageDraw.Draw(img)
def dot(p,r,col):
    x,y=p; d.ellipse([x-r,y-r,x+r,y+r],fill=col)
def stroke(pts,w,col):
    r=w*k/2; pts=[P(*p) for p in pts]
    for (x1,y1),(x2,y2) in zip(pts,pts[1:]):
        L=math.hypot(x2-x1,y2-y1); nx,ny=-(y2-y1)/L*r,(x2-x1)/L*r
        d.polygon([(x1+nx,y1+ny),(x2+nx,y2+ny),(x2-nx,y2-ny),(x1-nx,y1-ny)],fill=col)
    for p in pts: dot(p,r,col)
def arc(cx,cy,R,a0,a1,w,col,caps=True):
    # ângulos em graus, 0 = 3h, sentido horário
    h=w/2; n=720
    angs=[math.radians(a0+(a1-a0)*i/n) for i in range(n+1)]
    outer=[P(cx+(R+h)*math.cos(a),cy+(R+h)*math.sin(a)) for a in angs]
    inner=[P(cx+(R-h)*math.cos(a),cy+(R-h)*math.sin(a)) for a in reversed(angs)]
    d.polygon(outer+inner,fill=col)
    if caps:
        for a in (angs[0],angs[-1]): dot(P(cx+R*math.cos(a),cy+R*math.sin(a)),h*k,col)
white=(255,255,255,255); track=(255,255,255,70)
# trilha do anel (translúcida) e progresso de 75%
ring=Image.new("RGBA",(N,N),(0,0,0,0)); rd=d; d=ImageDraw.Draw(ring)
arc(75,75,42,0,360,10,track,caps=False)
img.alpha_composite(ring); d=rd
arc(75,75,42,-90,180,10,white)
# nota dupla (♫): duas cabeças inclinadas, hastes e a barra, desenhada numa
# camada à parte e depois centralizada no anel pela caixa dos pixels.
note=Image.new("RGBA",(N,N),(0,0,0,0))
def head(cx,cy):
    hw,hh=8.5*k,6.2*k; x,y=P(cx,cy)
    el=Image.new("RGBA",(N,N),(0,0,0,0)); ImageDraw.Draw(el).ellipse([x-hw,y-hh,x+hw,y+hh],fill=white)
    el=el.rotate(22,center=(x,y),resample=Image.BICUBIC); note.alpha_composite(el)
head(64,91); head(88,86)
d=ImageDraw.Draw(note)
stroke([(71.5,89),(71.5,59)],4.5,white)
stroke([(95.5,84),(95.5,54)],4.5,white)
d.polygon([P(69.25,60.5),P(97.75,55.5),P(97.75,63.5),P(69.25,68.5)],fill=white)
x0,y0,x1,y1=note.getchannel("A").getbbox()
cx,cy=P(75,75)
img.alpha_composite(note,(round(cx-(x0+x1)/2),round(cy-(y0+y1)/2)))
img=img.resize((1024,1024),Image.LANCZOS)
img.save("icon_1024.png")

# AppIcon.icns
ics="AppIcon.iconset"; shutil.rmtree(ics,ignore_errors=True); os.makedirs(ics)
for s in (16,32,128,256,512):
    img.resize((s,s),Image.LANCZOS).save(f"{ics}/icon_{s}x{s}.png")
    img.resize((s*2,s*2),Image.LANCZOS).save(f"{ics}/icon_{s}x{s}@2x.png")
subprocess.run(["iconutil","-c","icns",ics,"-o","AppIcon.icns"],check=True)
shutil.rmtree(ics)
