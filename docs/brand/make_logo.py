"""Original Sanjaal mark: two Himal peaks joined by a network node. Run: python3 docs/brand/make_logo.py"""
from PIL import Image, ImageDraw
import os
RED=(200,16,46); BLUE=(0,56,147); WHITE=(255,255,255)
S=4096
def draw(size, rounded, fg=False):
    im=Image.new('RGBA' if fg else 'RGB',(S,S),(0,0,0,0) if fg else RED)
    d=ImageDraw.Draw(im)
    # big peak and small peak, white, flat base
    base=0.70*S
    big=[(0.14*S,base),(0.44*S,0.26*S),(0.74*S,base)]
    small=[(0.46*S,base),(0.68*S,0.42*S),(0.90*S,base)]
    d.polygon(small,fill=(255,214,218))
    d.polygon(big,fill=WHITE)
    # snow line notch on the big peak
    d.polygon([(0.44*S,0.26*S),(0.375*S,0.385*S),(0.41*S,0.37*S),(0.44*S,0.42*S),(0.475*S,0.37*S),(0.51*S,0.385*S)],fill=(255,214,218))
    # network node and two links (the jaal) under the peaks
    pts=[(0.28*S,0.82*S),(0.50*S,0.80*S),(0.72*S,0.82*S)]
    d.line([pts[0],pts[1],pts[2]],fill=WHITE,width=int(0.022*S))
    r=int(0.04*S)
    for i,(x,y) in enumerate(pts):
        c=BLUE if i==1 else WHITE
        rr=int(r*1.35) if i==1 else r
        d.ellipse([x-rr,y-rr,x+rr,y+rr],fill=c,outline=WHITE,width=int(0.012*S))
    if fg:
        # Adaptive icon layer: art kept inside the central safe zone, transparent elsewhere.
        k=0.60
        small_=im.resize((int(S*k),int(S*k)),Image.LANCZOS)
        canvas=Image.new('RGBA',(S,S),(0,0,0,0))
        canvas.paste(small_,((S-small_.width)//2,(S-small_.height)//2),small_)
        im=canvas
    return im.resize((size,size),Image.LANCZOS)
root=os.path.join(os.path.dirname(__file__),'..','..','app')
draw(1024,False).save(os.path.join(root,'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png'))
for d,px in {'mdpi':48,'hdpi':72,'xhdpi':96,'xxhdpi':144,'xxxhdpi':192}.items():
    draw(px,False).save(os.path.join(root,f'android/app/src/main/res/mipmap-{d}/ic_launcher.png'))
draw(512,False).save(os.path.join(os.path.dirname(__file__),'logo-512.png'))

res=os.path.join(root,'android/app/src/main/res')
for d,px in {'mdpi':108,'hdpi':162,'xhdpi':216,'xxhdpi':324,'xxxhdpi':432}.items():
    draw(px,False,True).save(os.path.join(res,f'mipmap-{d}/ic_launcher_foreground.png'))
os.makedirs(os.path.join(res,'mipmap-anydpi-v26'),exist_ok=True)
open(os.path.join(res,'mipmap-anydpi-v26/ic_launcher.xml'),'w').write('<?xml version="1.0" encoding="utf-8"?>\n<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n    <background android:drawable="@color/ic_launcher_background"/>\n    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n</adaptive-icon>\n')
open(os.path.join(res,'values/ic_launcher_background.xml'),'w').write('<?xml version="1.0" encoding="utf-8"?>\n<resources>\n    <color name="ic_launcher_background">#C8102E</color>\n</resources>\n')
