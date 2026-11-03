from pathlib import Path
import numpy as np
from PIL import Image,ImageDraw,ImageFilter
from britain_landscape import coast,height
ROOT=Path(__file__).resolve().parents[1];D=ROOT/'overrides/britain';D.mkdir(exist_ok=True)
rng=np.random.default_rng(1940)
for name,base in [('brick',(126,73,53)),('slate',(65,72,76)),('concrete',(139,137,120)),('chalk',(196,193,163)),('metal',(82,91,82))]:
 a=np.clip(np.array(base)[None,None,:]+rng.normal(0,10,(512,512,1)),0,255).astype('uint8');im=Image.fromarray(a);d=ImageDraw.Draw(im)
 if name=='brick':
  for y in range(0,512,20):
   d.line((0,y,512,y),fill=(68,66,57),width=2)
   for x in range(-40,550,60):d.line((x+(30 if y//20%2 else 0),y,x+(30 if y//20%2 else 0),y+20),fill=(68,66,57),width=2)
 if name in ['slate','metal']:
  for y in range(0,512,24):d.line((0,y,512,y),fill=(42,47,48),width=2)
  for x in range(0,512,64):d.line((x,0,x,512),fill=(53,59,60))
 im.save(D/(name+'.png'))
for name in ['raf','luft']:
 im=Image.new('RGB',(1024,1024));a=np.zeros((1024,1024,3),dtype=np.uint8);y,x=np.mgrid[:1024,:1024];mask=np.sin(x/90+np.sin(y/73)*2)+np.cos(y/110+x/180)>0
 a[:]=[78,86,57] if name=='raf' else [70,79,70];a[mask]=[108,89,60] if name=='raf' else [91,100,93];a=np.clip(a.astype(float)+rng.normal(0,3,(1024,1024,1)),0,255).astype('uint8');im=Image.fromarray(a);d=ImageDraw.Draw(im)
 for k in range(0,1024,64):
  d.line((k,0,k,1024),fill=(39,43,37));d.line((0,k,1024,k),fill=(39,43,37))
  for j in range(0,1024,12):d.point((k+3,j),fill=(153,151,127));d.point((j,k+3),fill=(153,151,127))
 im.save(D/(name+'.png'))
n=2048;z,x=np.mgrid[:n,:n]*6000/(n-1);c=3050+240*np.sin(z/540)+110*np.sin(z/173)-410*np.exp(-((z-1750)/500)**2);dist=c-x
base=np.zeros((n,n,3));base[:]=[66,94,43];field=((np.sin(x/180+np.sin(z/310))+.6*np.cos(z/130))>0);base[field]=[107,115,60]
noise=rng.normal(0,7,(n,n,1));base+=noise
hedge=(np.abs(np.sin(x/185+np.sin(z/500)*.4))<.035)|(np.abs(np.sin(z/160+np.sin(x/700)*.4))<.035);base[hedge]=[40,62,28]
base[(dist>0)&(dist<70)]=[195,190,155];sea=dist<0;depth=np.clip(-dist/600,0,1);base[sea]=np.stack([32-8*depth,105-38*depth,117-28*depth],axis=2)[sea]
ripples=(np.sin(z*.2+x*.025)+np.sin(z*.37-x*.013))*2;base[sea]+=ripples[sea,None];base[(dist<0)&(dist>-16)]=[174,192,170]
im=Image.fromarray(np.clip(base,0,255).astype('uint8'));draw=ImageDraw.Draw(im)
def line(points,color,width):draw.line([(int(a*n/6000),int(b*n/6000)) for a,b in points],fill=color,width=width)
line([(900,3300),(1800,3300),(2000,2850),(2200,2300),(2450,1700),(2700,1600)],(135,128,106),6)
for z0 in range(1400,1950,100):line([(2200,z0),(2650,z0)],(128,123,110),5)
for x0 in range(2200,2700,100):line([(x0,1400),(x0,1950)],(128,123,110),5)
im.save(D/'landscape.png');im.resize((1024,1024)).save(ROOT/'redace/game_data/maps/britain/map.png')
# CC0 photographic surface detail, retained locally so rebuilds do not need the network.
for source,target in [('red_brick_03.jpg','brick.png'),('concrete_wall_006.jpg','concrete.png')]:
 if (D/source).exists():Image.open(D/source).convert('RGB').save(D/target)
if (D/'rock_photo.jpg').exists():
 rock=Image.open(D/'rock_photo.jpg').convert('RGB');a=np.asarray(rock).astype(float);lum=a.mean(axis=2,keepdims=True);a=np.clip(lum*.65+np.array([94,92,80]),0,255).astype('uint8');Image.fromarray(a).save(D/'chalk.png')
# Weathered paint: fine panel seams, exhaust staining, scratches and irregular camouflage.
for name in ['raf','luft']:
 im=Image.open(D/(name+'.png')).resize((2048,2048));a=np.asarray(im).astype(float);y,x=np.mgrid[:2048,:2048]
 wear=(np.sin(x*.041+np.sin(y*.018))*np.sin(y*.051))*2+rng.normal(0,1.5,(2048,2048));a+=wear[:,:,None]
 im=Image.fromarray(np.clip(a,0,255).astype('uint8'));d=ImageDraw.Draw(im)
 for _ in range(1800):
  px=int(rng.integers(0,2048));py=int(rng.integers(0,2048));d.line((px,py,px+int(rng.integers(1,8)),py),fill=(130,133,119),width=1)
 for px in [980,1068]:
  for j in range(80):
   y0=1150+j*2;d.line((px-j//12,y0,px+j//12+1,y0),fill=(44+j//4,43+j//4,36+j//4))
 im.save(D/(name+'.png'))
# RAF roundels are paint on the wing UVs, never floating geometry. The upper-wing
# 1940 Type B marking is blue/red. UV v runs opposite the bitmap's row direction.
im=Image.open(D/'raf.png');d=ImageDraw.Draw(im)
for side in [-1,1]:
 px=(side*22*.33+25)/50*2048;py=1024
 for radius,color in [(1.45,(25,42,75)),(.58,(137,42,33))]:
  r=radius/50*2048;d.ellipse((px-r,py-r,px+r,py+r),fill=color)
im.save(D/'raf.png')
# Small entry holes, chipped edges and trailing soot accumulate between stages.
# Paint all hits onto existing surfaces, retaining identical undamaged geometry.
for name in ['raf','luft']:
 im=Image.open(D/(name+'.png')).convert('RGBA')
 for stage in [1,2]:
  soot=Image.new('RGBA',im.size);sd=ImageDraw.Draw(soot);hits=[]
  for _ in range(7 if stage==1 else 13):
   cx=float(rng.choice([-1,1]))*float(rng.uniform(2.5,8.8));cz=float(rng.uniform(-.8,.6))
   for j in range(int(rng.integers(3,6))):
    px=int((cx+25)/50*2048+j*7);py=int((25-cz)/50*2048+j*9)
    hits.append((px,py));sd.ellipse((px-6,py-4,px+6,py+26),fill=(12,12,10,100))
  # Engine/fuselage leak staining is stronger at severe damage.
  sd.ellipse((995,850,1045,1110+stage*50),fill=(12,12,10,45*stage))
  im=Image.alpha_composite(im,soot.filter(ImageFilter.GaussianBlur(5)));d=ImageDraw.Draw(im)
  for px,py in hits:
   d.polygon([(px-3,py-1),(px-1,py-4),(px+3,py-2),(px+4,py+2),(px,py+4),(px-3,py+2)],fill=(148,147,130))
   d.ellipse((px-2,py-2,px+2,py+2),fill=(12,14,13))
  im.convert('RGB').save(D/f'{name}_damaged{stage}.png')
# Blend real grass microdetail into the regional field atlas, without flattening map-scale features.
im=Image.open(D/'landscape.png');a=np.asarray(im).astype(float)
if (D/'leafy_grass.jpg').exists():
 grass=np.asarray(Image.open(D/'leafy_grass.jpg').convert('RGB').resize((256,256))).astype(float)
 detail=np.tile(grass.mean(axis=2),(8,8));detail=(detail-detail.mean())*.28
 land=dist>70;a[land]+=detail[land,None]
# Submerged shingle/sand replaces painted waves; the runtime transparent sea supplies wave shading.
sea=dist<0;shingle=rng.normal(0,9,dist.shape);a[sea]=np.stack([92+shingle,112+shingle,100+shingle],axis=2)[sea]
Image.fromarray(np.clip(a,0,255).astype('uint8')).save(D/'landscape.png')
