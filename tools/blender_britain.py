"""Run through Blender MCP execute_code. Authors and exports detailed mission assets."""
import bpy,math,sys,random
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'tools'))
from britain_landscape import coast,height
D=ROOT/'overrides/britain';DATA=ROOT/'redace/game_data';random.seed(1940)
# A dedicated scene preserves any scene the user already has open.
scene=bpy.data.scenes.get('Britain assets') or bpy.data.scenes.new('Britain assets');bpy.context.window.scene=scene
for o in list(scene.objects):bpy.data.objects.remove(o,do_unlink=True)
materials={}; parts=[]
def material(name,c,texture=None):
 m=bpy.data.materials.new('Britain_'+name);m.diffuse_color=(*c,1);m.use_nodes=True;p=m.node_tree.nodes.get('Principled BSDF');p.inputs['Base Color'].default_value=(*c,1);p.inputs['Roughness'].default_value=.78
 if texture:
  t=m.node_tree.nodes.new('ShaderNodeTexImage');t.image=bpy.data.images.load(str(D/(texture+'.png')),check_existing=True);t.image.reload();m.node_tree.links.new(t.outputs['Color'],p.inputs['Base Color'])
 materials[name]=m
for name,c,t in [('brick',(.6,.4,.3),'brick'),('slate',(.3,.3,.3),'slate'),('concrete',(.6,.6,.6),'concrete'),('metal',(.3,.35,.3),'metal'),('raf',(.4,.4,.2),'raf'),('luft',(.3,.4,.3),'luft'),('chalk',(1,1,1),'chalk'),('scorch',(.16,.14,.12),'metal'),('terrain',(1,1,1),'landscape'),('glass',(.15,.32,.39),None),('black',(.035,.04,.04),None),('white',(.82,.81,.71),None),('red',(.55,.06,.04),None),('blue',(.04,.09,.25),None),('green',(.18,.28,.09),None),('wood',(.25,.17,.09),None),('prop',(.1,.1,.09),None)]:material(name,c,t)
materials['prop'].name='soppropeller_britain'
for paint in ['raf','luft']:
 for stage in [1,2]:material(f'{paint}_damaged{stage}',(.4,.4,.3),f'{paint}_damaged{stage}')
materials['glass'].node_tree.nodes.get('Principled BSDF').inputs['Alpha'].default_value=.76
materials['glass'].node_tree.nodes.get('Principled BSDF').inputs['Roughness'].default_value=.18
if hasattr(materials['glass'],'surface_render_method'):materials['glass'].surface_render_method='DITHERED'
def mesh(name,verts,faces,mat,uvscale=8,terrain=False):
 me=bpy.data.meshes.new(name);me.from_pydata(verts,[],faces);me.update();o=bpy.data.objects.new(name,me);scene.collection.objects.link(o);me.materials.append(materials[mat]);uv=me.uv_layers.new()
 for poly in me.polygons:
  for li in poly.loop_indices:
   v=me.vertices[me.loops[li].vertex_index].co
   if terrain: uv.data[li].uv=(v.x/6000,1-v.z/6000)
   elif mat in ['raf','luft']:uv.data[li].uv=((v.x+25)/50,(v.z+25)/50)
   else:
    a=max(range(3),key=lambda j:abs(poly.normal[j]));axes=[j for j in range(3) if j!=a];uv.data[li].uv=(v[axes[0]]/uvscale,v[axes[1]]/uvscale)
 parts.append(o);return o
def box(name,pos,size,mat):
 x,y,z=pos;w,h,d=size;v=[(x+a*w/2,y+b*h/2,z+c*d/2) for a,b,c in [(-1,-1,-1),(1,-1,-1),(1,1,-1),(-1,1,-1),(-1,-1,1),(1,-1,1),(1,1,1),(-1,1,1)]]
 return mesh(name,v,[(0,3,2,1),(4,5,6,7),(0,4,7,3),(1,2,6,5),(3,7,6,2),(0,1,5,4)],mat)
def beam(name,a,b,r,mat,sides=8):
 a,b=Vector(a),Vector(b);v=(b-a).normalized();u=v.cross(Vector((0,1,0)))
 if u.length<.1:u=v.cross(Vector((1,0,0)))
 u.normalize();w=v.cross(u);vs=[tuple(p+r*(math.cos(i*math.tau/sides)*u+math.sin(i*math.tau/sides)*w)) for p in [a,b] for i in range(sides)]
 return mesh(name,vs,[tuple(range(sides-1,-1,-1)),tuple(range(sides,2*sides))]+[(i,(i+1)%sides,(i+1)%sides+sides,i+sides) for i in range(sides)],mat)
def body(name,pos,length,width,tall,mat):
 x,y,z=pos;v=[];n=32;rings=25
 for j in range(rings):
  t=j/(rings-1);r=max(.015,math.sin(math.pi*t)**.65);r*=.55+.65*t
  for i in range(n):a=i*math.tau/n;v.append((x+math.cos(a)*width*.5*r,y+math.sin(a)*tall*.5*r,z+(t-.5)*length))
 o=mesh(name,v,[(j*n+i,j*n+(i+1)%n,(j+1)*n+(i+1)%n,(j+1)*n+i) for j in range(rings-1) for i in range(n)],mat)
 for p in o.data.polygons:p.use_smooth=True
 return o
def export(name,path):
 global parts
 bpy.ops.object.select_all(action='DESELECT')
 for o in parts:o.select_set(True)
 bpy.context.view_layer.objects.active=parts[0]
 # Merge static details; propellers retain their own pivots for the existing animation.
 props=[o for o in parts if 'Propeller' in o.name]
 static=[o for o in parts if 'Propeller' not in o.name]
 bpy.ops.object.select_all(action='DESELECT')
 for o in static:o.select_set(True)
 bpy.context.view_layer.objects.active=static[0];bpy.ops.object.join();static[0].name=name
 objs=[static[0]]+props
 bpy.ops.object.select_all(action='DESELECT')
 for o in objs:o.select_set(True)
 path.parent.mkdir(exist_ok=True,parents=True)
 bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLTF_SEPARATE',use_selection=True,export_yup=False,export_apply=True,export_materials='EXPORT',export_texcoords=True)
 # Each damageable mod asset has visible progressive damage and a distinct wreck.
 if '/objects/' in str(path):
  originals=list(objs)
  for stage,filename in [(1,'damaged1'),(2,'damaged2'),(3,'wreck')]:
   clones=[]
   bpy.ops.object.select_all(action='DESELECT')
   for source in originals:
    c=source.copy();c.data=source.data.copy();scene.collection.objects.link(c);c.name=name+'_'+filename;clones.append(c)
    c.data.materials.append(materials['scorch']);burn=len(c.data.materials)-1
    aircraft='/planes/' in str(path)
    if aircraft and stage<3:
     # Combat damage changes paint, not airframe shape. Smoke comes from Aircraft.
     for slot,mat in enumerate(c.data.materials):
      for paint in ['raf','luft']:
       if mat==materials[paint]:c.data.materials[slot]=materials[f'{paint}_damaged{stage}']
    else:
     for poly in c.data.polygons:
      center=poly.center
      if (math.sin(center.x*.7+center.z*.53)+math.cos(center.y*.91)>1.1-stage*.5):poly.material_index=burn
    for v in c.data.vertices:
     q=v.co
     if aircraft:
      pass  # Even the falling wreck keeps a rigid airframe; no rubber-like wing bending.
     elif stage>1 and q.y>5:
      q.y=5+(q.y-5)*(1-.22*stage);q.x+=math.sin(q.z*.25)*stage*.6
    if stage==3:
     for poly in c.data.polygons:poly.material_index=burn
    c.select_set(True)
   bpy.ops.export_scene.gltf(filepath=str(path.with_name(filename+'.gltf')),export_format='GLTF_SEPARATE',use_selection=True,export_yup=False,export_apply=True,export_materials='EXPORT')
   for c in clones:c.hide_set(True);c.select_set(False)
 for o in objs:o.hide_set(True);o.select_set(False)
 parts=[]
# Curved, solid wings; fuselage, frames, exhausts, radiators and national markings.
for name in ['spitfire','bf109','he111']:
 bomber=name=='he111';span=40 if bomber else 22;L=31 if bomber else 20;mat='raf' if name=='spitfire' else 'luft'
 body('Fuselage',(0,0,0),L,3.8 if bomber else 2.3,4 if bomber else 2.6,mat)
 for side in [-1,1]:
  vs=[];steps=24
  for j in range(steps+1):
   t=j/steps;x=side*span*.5*t;chord=(6.3 if bomber else 5.2)*(math.sqrt(max(.005,1-t*t)) if name=='spitfire' else 1-.65*t);lead=2.6-t*2;dy=.25+t*.7
   for z,y in [(lead,0),(lead-chord*.28,.32*(1-t*.8)),(lead-chord,0),(lead-chord*.28,-.14)]:vs.append((x,dy+y,z))
  mesh('Airfoil wing',vs,[(j*4+k,j*4+(k+1)%4,(j+1)*4+(k+1)%4,(j+1)*4+k) for j in range(steps) for k in range(4)],mat)
  mesh('Tailplane',[(0,.6,-L*.33),(side*span*.22,.7,-L*.35),(side*span*.20,.7,-L*.46),(0,.6,-L*.46)],[(0,1,2,3),(3,2,1,0)],mat)
  box('Radiator',(side*3,-.65,-.6),(1.6,.8,2.2),'metal')
  for j in range(6):beam('Exhaust',(side*1.1,.3,2+j*.38),(side*1.65,.15,2+j*.38),.14,'metal')
  for x in [3.5,4.4,5.1,5.8] if name=='spitfire' else [4.5]:beam('Gun barrel',(side*x,.4,1.2),(side*x,.4,3.0),.075,'black')
  x=side*span*.33
  if name!='spitfire':
   for w,h,c,y in [(3,.7,'white',1.12),(.7,3,'white',1.14),(2.7,.35,'black',1.16),(.35,2.7,'black',1.18)]:box('Balkenkreuz',(x,y,0),(w,.02,h),c)
 body('Canopy',(0,1.35,.3 if not bomber else 9),4.8 if not bomber else 7,1.9 if not bomber else 3.1,1.7,'glass')
 for z in [-1.6,-.5,.8,2]:
  beam('Canopy frame',(-.8,1.5,z),(0,2.25,z),.065,'metal');beam('Canopy frame',(0,2.25,z),(.8,1.5,z),.065,'metal')
 beam('Canopy spine',(0,2.25,-1.6),(0,2.25,2),.055,'metal')
 fin=[(0,.5,-L*.31)]
 for j in range(17):
  a=j*math.pi/16;fin.append((0,.5+3.2*math.sin(a),-L*.4+L*.09*math.cos(a)))
 mesh('Rounded fin',fin,[tuple(range(len(fin))),tuple(range(len(fin)-1,-1,-1))],mat)
 # Wheel wells, navigation lamps, trim tabs and internal cockpit furniture.
 for side in [-1,1]:
  box('Wheel well',(side*3,-.38,-.2),(1.25,.12,2.3),'black')
  body('Navigation lamp',(side*(span*.5-.3),.8,-.3),.4,.25,.25,'red' if side<0 else 'green')
  beam('Tail trim hinge',(side*.4,.7,-L*.44),(side*span*.18,.7,-L*.44),.035,'metal')
 box('Pilot seat',(0,1.1,-.5),(.65,.9,.6),'wood')
 body('Pilot head',(0,1.8,-.4),.5,.45,.5,'wood')
 if bomber:
  body('Dorsal gun canopy',(0,2,-4),3,2,1.6,'glass')
  beam('Dorsal MG15',(0,2.5,-4),(0,3,-7.3),.10,'black')
  body('Ventral gondola',(0,-1.8,-2),5,1.8,1.3,'glass')
  beam('Ventral MG15',(0,-2,-3),(0,-2.8,-6),.10,'black')
  # The He 111's greenhouse nose has longitudinal and transverse glazing ribs.
  for z in [8,9,10,11,12]:
   beam('Nose glazing rib',(-1.25,.8,z),(0,2.1,z),.055,'metal');beam('Nose glazing rib',(0,2.1,z),(1.25,.8,z),.055,'metal')
 beam('Aerial mast',(0,1.6,-2),(0,3.3,-2),.06,'metal');beam('Aerial wire',(0,3.3,-2),(0,3.5,-L*.42),.015,'black')
 for x in [-7,7] if bomber else [0]:
  z=6 if bomber else L*.5
  if bomber:body('Nacelle',(x,-.1,3.5),9,2.6,3,mat)
  body('Spinner',(x,0,z),1.5,1.1,1.1,'black')
  o=mesh('Propeller',[(0,.2,0),(.22,3.1,0),(-.22,3.1,0),(-.12,.1,0),(-2.7,-1.6,0),(-2.5,-1.9,0),(.1,-.1,0),(2.5,-1.9,0),(2.7,-1.6,0)],[(0,1,2),(3,4,5),(6,7,8)],'prop');o.location=(x,0,z+.6)
 export(name,DATA/f'objects/planes/{name}/{name}.gltf')
# Detailed modular architecture.
def house(name,w=20,h=13,d=18):
 box('Brick walls',(0,h/2,0),(w,h,d),'brick')
 mesh('Pitched roof',[(-w/2-1,h,-d/2-1),(w/2+1,h,-d/2-1),(0,h+6,-d/2-1),(-w/2-1,h,d/2+1),(w/2+1,h,d/2+1),(0,h+6,d/2+1)],[(0,3,5,2),(2,5,4,1),(0,2,1),(3,4,5)],'slate')
 for side in [-1,1]:
  for x in range(int(-w/2+3),int(w/2),6):
   for y in [4,10]:
    box('Window surround',(x,y,side*(d/2+.12)),(2.9,3.6,.3),'white');box('Window glass',(x,y,side*(d/2+.31)),(2.3,3,.12),'glass');box('Window mullion',(x,y,side*(d/2+.4)),(.15,3.1,.12),'white')
 box('Door',(0,2, d/2+.5),(2.5,4,.3),'wood');box('Chimney',(w*.28,h+5,0),(2.4,6,2.6),'brick')
 # Drainpipes, gutters, door lintel and a garden boundary give each street frontage depth.
 for side in [-1,1]:
  beam('Gutter',(-w/2,h,side*d/2),(w/2,h,side*d/2),.12,'metal')
  beam('Drainpipe',(w/2-.4,0,side*d/2),(w/2-.4,h,side*d/2),.10,'metal')
 box('Door lintel',(0,4.2,d/2+.6),(3.2,.35,.5),'concrete')
 for x in [-.6,.6]:beam('Chimney pot' ,(w*.28+x,h+8,0),(w*.28+x,h+9,0),.35,'brick')
for name in ['britaincottage','britainwarehouse','britainfactory','britainhangar','britainbattery','britainradar','britainlighthouse','britaincrane','britainaa','britainfishing','britainfreighter']:
 if name=='britaincottage':house(name)
 if name=='britainwarehouse':house(name,38,20,65)
 if name=='britainfactory':
  for x in [-38,0,38]:
   start=len(parts);house(name,36,23,100)
   for o in parts[start:]:o.location.x+=x
  beam('Brick stack',(60,0,32),(60,78,32),4,'brick',24)
  for y in range(7,75,9):beam('Stack band',(60,y,32),(60,y+.65,32),4.2,'metal',24)
  for x in [-25,0,25]:box('Loading bay',(x,5,51),(16,10,1),'metal')
  box('Yard',(0,.2,0),(155,.4,145),'concrete')
 if name=='britainhangar':
  box('Hangar shell',(0,10,0),(62,20,48),'metal')
  for x in range(-30,32,6):box('Ribs',(x,21,0),(.4,2,50),'metal')
  box('Hangar doors',(0,9,24.3),(56,18,.5),'slate')
 if name=='britainbattery':
  for a in range(12):
   angle=a*math.tau/12;x=math.cos(angle)*14;z=math.sin(angle)*14;box('Concrete emplacement',(x,2,z),(7,4,6),'concrete')
  beam('Gun pedestal',(0,0,0),(0,4,0),2.4,'metal');box('Gun shield',(0,5,1),(7,5,1),'metal');beam('Coastal gun',(0,5,0),(0,7,15),.55,'metal',12)
  box('Magazine bunker',(-25,3,-14),(22,6,18),'concrete');box('Bunker roof',(-25,6.4,-14),(24,1.4,20),'concrete');box('Embrasure',(-25,4,-4.8),(10,1,.2),'black')
 if name=='britainradar':
  for y in range(0,72,12):
   for a in [-1,1]:
    for b in [-1,1]:beam('Lattice leg',(a*5,y,b*5),(a*5,y+12,b*5),.25,'metal');beam('Cross brace',(a*5,y,b*5),(-a*5,y+12,b*5),.12,'metal')
  for y in range(30,75,10):beam('Radar antenna',(-15,y,0),(15,y,0),.18,'metal')
 if name=='britainradar':
  box('Transmitter hut',(17,4,-13),(18,8,15),'brick');box('Hut roof',(17,8.4,-13),(20,1,17),'slate')
  for level in [30,50,70]:
   for side in [-1,1]:
    box('Aerial platform',(side*8,level,0),(8,.4,5),'metal')
    for z in [-2,2]:beam('Array wire',(side*12,level,z),(side*12,level+8,z),.045,'metal')
  for x,z in [(-22,0),(22,0),(0,-22),(0,22)]:beam('Tower stay',(0,55,0),(x,0,z),.055,'metal')
 if name=='britainlighthouse':
  beam('White tower',(0,0,0),(0,35,0),5,'white',24);beam('Lantern room',(0,35,0),(0,40,0),4.5,'glass',16);beam('Lantern roof',(0,40,0),(0,41,0),5.5,'black',24)
 if name=='britaincrane':
  for x in [-4,4]:beam('Crane legs',(x,0,0),(x,25,0),.7,'metal')
  box('Cab',(0,25,0),(8,6,7),'metal');beam('Boom',(0,27,0),(0,40,30),.8,'metal');beam('Hook cable',(0,40,30),(0,7,30),.07,'black')
 if name=='britainaa':
  # 3.7-inch-style static mount, cruciform base, angled barrel and gunner stations.
  box('Cross mounting',(0,.6,0),(13,1.2,2),'metal');box('Cross mounting',(0,.6,0),(2,1.2,13),'metal')
  beam('Gun mounting',(0,0,0),(0,2.7,0),2,'metal',16)
  box('Breech',(0,3.3,0),(2,2,3),'metal');beam('AA barrel',(0,3.5,0),(0,9,7),.24,'metal',16)
  beam('Recoil cylinder',(.45,3.4,0),(.45,6.3,3.5),.16,'metal')
  for side in [-1,1]:
   box('Gunner seat',(side*2,2,0),(1.1,.3,1.2),'wood')
   beam('Elevation handwheel',(side*2,2.8,1),(side*2.1,2.8,1),.55,'metal',16)
  for j in range(14):
   a=j*math.tau/14;box('Sandbag revetment',(math.cos(a)*10,1,math.sin(a)*10),(3,2,2),'concrete')
 if name in ['britainfishing','britainfreighter']:
  cargo=name=='britainfreighter';length=105 if cargo else 26;width=17 if cargo else 7
  # Closed rounded hull with curved sheer and a defined bow.
  vs=[];rings=33
  for j in range(rings):
   t=j/(rings-1);half=width*.5*max(.04,math.sin(math.pi*t)**.45);z=(t-.5)*length;sheer=1.8+2*(abs(t-.5)*2)**4
   for x,y in [(-half,sheer),(-half*.8,-1.3),(0,-3),(half*.8,-1.3),(half,sheer)]:vs.append((x,y,z))
  faces=[(j*5+k,j*5+(k+1)%5,(j+1)*5+(k+1)%5,(j+1)*5+k) for j in range(rings-1) for k in range(5)]
  mesh('Riveted hull',vs,faces,'metal' if cargo else 'wood');box('Deck',(0,1.8,0),(width*.8,.4,length*.8),'wood')
  box('Wheelhouse',(0,4,-length*.16),(width*.65,4,length*.14),'white');box('Wheelhouse window',(0,4.8,-length*.09),(width*.6,1.5,.1),'glass')
  beam('Mast',(0,2,length*.16),(0,20 if cargo else 13,length*.16),.3,'wood')
  for side in [-1,1]:
   beam('Rigging',(side*width*.4,2,0),(0,20 if cargo else 13,length*.16),.035,'black')
   for z in range(int(-length*.35),int(length*.4),4):beam('Rail stanchion',(side*width*.43,2,z),(side*width*.43,3,z),.045,'white')
   beam('Deck rail',(side*width*.43,3,-length*.35),(side*width*.43,3,length*.35),.055,'white')
  if cargo:
   beam('Funnel',(0,4,-27),(0,14,-27),2,'black',16)
   for z in [5,20,35]:box('Cargo hatch',(0,2.7,z),(11,1.4,10),'slate')
   beam('Derrick',(0,16,17),(0,8,33),.22,'metal')
  else:
   for z in [-6,-3,0]:box('Fish crates',(1,2.6,z),(2,1.2,2),'wood')
  # Same ~2 game units/metre as the aircraft: 107 m cargo ship, 21 m fishing trawler.
  vessel_scale=2.0 if cargo else 1.6
  for o in parts:
   for v in o.data.vertices:v.co*=vessel_scale
   o.location*=vessel_scale
 export(name,DATA/f'objects/ground/{name}/{name}.gltf')
# Terrain mesh, coastal cliffs, textured sea and harbour infrastructure in one map.
# Coast-aligned topology: one continuous surface, so detailed cliff faces never intersect
# a second coarse slope. Dense 8-unit cross-sections resolve the eroded chalk escarpment.
vs=[];rows=501;cols=251
for row in range(rows):
 z=row*12;c=coast(z)
 xs=[(c-80)*j/140 for j in range(140)]+[c-80+j*8 for j in range(11)]+[c+(6000-c)*j/100 for j in range(1,101)]
 for x in xs:
  d=c-x;y=height(x,z)
  if 0<d<80:y+=math.sin(z*.17)*math.sin(d*math.pi/80)*1.8
  vs.append((x,y,z))
faces=[]
for row in range(rows-1):
 for j in range(cols-1):
  i=row*cols+j;faces.append((i,i+cols,i+cols+1,i+1))
o=mesh('Chalk downs',vs,faces,'terrain',terrain=True);o.data.materials.append(materials['chalk'])
for poly in o.data.polygons:
 column=poly.index%(cols-1)
 if 140<=column<150:
  poly.material_index=1
  for li in poly.loop_indices:
   v=o.data.vertices[o.data.loops[li].vertex_index].co;o.data.uv_layers.active.data[li].uv=(v.z/32,v.y/24)
# Runtime mod owns the translucent sea surface above this textured seabed.
# Chalk talus below the cliffs, leaving the harbour entrance clear.
for z in range(100,5900,70):
 if 1250<z<2300:continue
 x=coast(z)+random.uniform(2,13)
 body('Fallen chalk boulder',(x,-.4,z),random.uniform(4,11),random.uniform(3,8),random.uniform(3,7),'chalk')
for x,z,w,d in [(2900,1350,650,55),(3090,2200,850,55),(3480,1830,55,770),(2720,1700,170,580)]:box('Harbour breakwater',(x,4,z),(w,8,d),'concrete')
export('Dover coast',DATA/'maps/britain/britain.gltf')
for o in scene.objects:o.hide_set(False)
bpy.ops.wm.save_as_mainfile(filepath=str(D/'britain.blend'))
print('BRITAIN BLENDER EXPORT COMPLETE')
