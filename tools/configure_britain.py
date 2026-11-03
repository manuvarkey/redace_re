"""Placement and flight tuning for the Blender-authored Dover-inspired mission."""
from pathlib import Path
import configparser,math,random
from britain_landscape import coast,height
R=Path(__file__).resolve().parents[1];D=R/'redace/game_data';random.seed(1940)
def read(p):
 c=configparser.ConfigParser(interpolation=None);c.read(p);return c
def save(c,p):
 with open(p,'w') as f:c.write(f)
 p.write_text(p.read_text().rstrip()+'\n')
m=read(D/'missions/26/mission.ini')
for k in list(m):
 if k.startswith('ground') or k.startswith('vehicle'):m.remove_section(k)
m['mod']={'init':'res://mods/britain/init.gd'}
m['mission'].pop('group6',None);m['mission']['group7']='100';m['objectives'].pop('group6',None);m['objectives']['group7']='aircraft factory'
identity={'up':'0 1 0','at':'0 0 1','right':'1 0 0'}
i=0
def obj(name,x,z,groups=0,y=None,yaw=0):
 global i
 a=math.radians(yaw)
 m['ground'+str(i)]={'name':name,'id':str(100 if i==0 else 1000+i),'groups':str(groups),'pos':f'{x} {height(x,z) if y is None else y} {z}',**identity,'at':f'{math.sin(a)} 0 {math.cos(a)}','right':f'{math.cos(a)} 0 {-math.sin(a)}'};i+=1
obj('britainfactory',1800,3300,384)
for z in range(1400,2000,100):
 for x in range(2200,2700,65):
  if x<coast(z)-80:obj('britaincottage',x,z)
for z in [1480,1600,1800,1930]:obj('britainwarehouse',2690,z,y=max(8,height(2690,z)))
for z in [1490,1740,1950]:obj('britaincrane',2770,z,y=8)
obj('britainlighthouse',3480,2180,y=8)
for z in [700,1050,2600,3000,4100,4800]:obj('britainbattery',coast(z)-120,z)
for x,z in [(1550,1600),(1550,1750)]:obj('britainhangar',x,z)
obj('britainradar',2250,3900)
for x,z,yaw in [(3150,1870,0),(3330,1610,0),(3910,2450,32),(4450,1750,-35),(4200,3600,18)]:
 obj('britainfreighter',x,z,y=0,yaw=yaw)
for x,z,yaw in [(2860,1800,0),(2900,1900,5),(3000,1650,-20),(3010,1510,0),
 (2980,1990,15),(3260,2010,0),(3360,1920,0),(3650,2300,35),(3800,1400,-25),
 (3760,2680,10),(4070,2870,-40),(4390,2690,65),(3850,1100,25),(4530,3300,-30),
 (4600,4200,40),(4050,4600,-15)]:obj('britainfishing',x,z,y=0,yaw=yaw)
# Functional AA uses the original vehicle/turret system, aimed exclusively at group 9.
for j,(x,z) in enumerate([(2800,1150),(2740,2450),(2150,3400),(2350,3850)]):
 m['vehicle'+str(j)]={'name':'britainaa','id':str(1900+j),'groups':'320','pos':f'{x} {height(x,z)} {z}','targetgroup':'9','range':'650','angle':'6.283185',**identity}
for j in range(150):
 x=random.uniform(400,2600);z=random.uniform(400,5600)
 if x<coast(z)-150 and math.hypot(x-1800,z-3300)>240 and math.hypot(x-2450,z-1700)>500:obj('tree'+str(j%4+1),x,z)
for j in range(4):
 s=m[f'air{j}'];s['pos']=f'{2450-j*65} {380+j*18} {2800-j*65}';s['at']='1 0 0';s['right']='0 0 -1';m[f'air{j}goal0']['pos']=s['pos']
for j in range(18):
 k=j+4;s=m[f'air{k}'];s['pos']=f'{5100+(j%3)*110} {440+(j%3)*45} {2300+(j//6)*330+(j%2)*140}';m[f'air{k}goal2']['pos']=s['pos']
 if j%6>=3:s['escortleader']=str(300+j-3)
 x,y,z=map(float,s['pos'].split());dx,dz=1800-x,3300-z;length=math.hypot(dx,dz)
 s['at']=f'{dx/length} 0 {dz/length}';s['right']=f'{dz/length} 0 {-dx/length}'
for j in range(18):
 if j%6<3:continue
 s=m[f'air{j+4}'];leader=m[f'air{j+1}']
 x,y,z=map(float,leader['pos'].split());fx,_,fz=map(float,leader['at'].split())
 s['pos']=f'{x+fz*100-fx*140} {y+45} {z-fx*100-fz*140}'
 s['at']=leader['at'];s['right']=leader['right'];m[f'air{j+4}goal2']['pos']=s['pos']
save(m,D/'missions/26/mission.ini')
for name in ['britaincottage','britainwarehouse','britainfactory','britainhangar','britainbattery','britainradar','britainlighthouse','britaincrane','britainaa','britainfishing','britainfreighter']:
 p=D/f'objects/ground/{name}/ground.ini';c=read(p)
 if not c.has_section('appearance'):c['appearance']={}
 c['appearance'].update({'dff':name+'.dff','damagedff1':'damaged1.dff','damagedff2':'damaged2.dff','damagedff3':'wreck.dff','deaddff':'wreck.dff','ambient':'0.6','diffuse':'0.65'})
 if not c.has_section('physics'):c['physics']={}
 c['physics']['endurance']=str(350 if name=='britainfactory' else 240 if name=='britainfreighter' else 100)
 if name=='britainaa':c['armaments']={'firerate':'2','fireon':'2','fireoff':'3'}
 save(c,p)
# Representative published maxima in mph: Spitfire I 355, Bf109 E3 354,
# He111H 270. Preserve ratios at the game's scale; see asset README for sources.
for name,speeds in [('spitfire',(145,122,110,175,70)),('bf109',(145*354/355,122,110,175,72)),('he111',(145*270/355,95,86,130,60))]:
 p=D/f'objects/planes/{name}/plane.ini';c=read(p)
 for key,val in zip(['highspeed','cruisespeed','climbspeed','divespeed','stallspeed'],speeds):c['physics'][key]=str(val)
 c['appearance'].update({'damagedff1':'damaged1.dff','damagedff2':'damaged2.dff','deaddff':'wreck.dff'})
 if name=='he111':c['physics'].update({'highroll':'20','lowroll':'15','highpitch':'12','lowpitch':'8','accel':'4'})
 c['collision'].update({'frontlength':'7','backlength':'8','portlength':'9' if name!='he111' else '17','starboardlength':'9' if name!='he111' else '17','uplength':'2','downlength':'2'})
 save(c,p)
p=D/'maps/britain/map.ini';p.write_text('[appearance]\nbsp = britain\nfogcolour = 193 213 226 255\nminimumviewdistance = 1800\n')
p=D/'language/english/missions/26/mission.html';s=p.read_text().replace('Southern England, September 1940.','Dover-inspired coast, September 1940.').replace('Their Heinkel bombers are making for our aircraft factory,','Their Heinkel bombers are making for the factory in the coastal hills,');p.write_text(s)
print('Placed',i,'ground objects; water fraction',sum(x>coast(z) for x in range(0,6000,30) for z in range(0,6000,30))/40000)
