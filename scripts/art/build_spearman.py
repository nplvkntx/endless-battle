"""Original medium-detail spearman; shares the worker's mesh/rig authoring helpers."""
from pathlib import Path
base=Path(__file__).with_name('build_worker.py').read_text()
exec(compile(base.split('# Join the character')[0], str(Path(__file__)), 'exec'))
OUT=ROOT/'assets/art/endless_spearman'; OUT.mkdir(parents=True,exist_ok=True)
SOURCE=OUT/'source'; SOURCE.mkdir(exist_ok=True); (SOURCE/'.gdignore').write_text('')

# Retain the articulated anatomy, replace the silhouette-defining clothes/equipment.
remove_prefix=('Cargo','Tool_','Scarf fold','Front scarf tail','Back mantle','Split blue apron','Apron hem','Back emblem','Hair cap','Swept hair','Headband','Chest harness','Cheek')
parts=[o for o in parts if not o.name.startswith(remove_prefix)]
for o in list(bpy.data.objects):
    if o.type=='MESH' and o.name.startswith(remove_prefix): bpy.data.objects.remove(o,do_unlink=True)
props=[]
for o in parts:
    for polygon in o.data.polygons: polygon.use_smooth=True
    if o.name.startswith(('Eye','Iris')): o.scale.z=.7; o.scale.x=.8
    if o.name.startswith('Nose'): o.scale*=.8
    if o.name.startswith('Shirt torso'): o.scale.z=.86
    if o.name.startswith('Chest harness'): o.location.y-=.05
rig.name='SpearmanRig'

def surface(name,verts,faces,material,bone,smooth=True):
    mesh=bpy.data.meshes.new(name); mesh.from_pydata(verts,[],faces); mesh.update()
    obj=bpy.data.objects.new(name,mesh); bpy.context.collection.objects.link(obj)
    for p in mesh.polygons: p.use_smooth=smooth
    return finish(obj,name,material,bone)

def dome(name,center,radii,material,bone):
    verts=[]; faces=[]; seg=32; rows=12
    for j in range(rows+1):
        phi=(j+.02)/(rows+.02)*math.pi/2
        for i in range(seg):
            a=i*math.tau/seg
            verts.append((center[0]+radii[0]*math.sin(phi)*math.cos(a),center[1]+radii[1]*math.sin(phi)*math.sin(a),center[2]+radii[2]*math.cos(phi)))
    for j in range(rows):
        for i in range(seg):
            a=j*seg+i; b=j*seg+(i+1)%seg; faces.append((a,b,b+seg,a+seg))
    return surface(name,verts,faces,material,bone)

def ring(name,center,rx,ry,tube,material,bone,wave=0):
    verts=[]; faces=[]; n=48; m=8
    for i in range(n):
        a=i*math.tau/n
        for j in range(m):
            b=j*math.tau/m
            verts.append((center[0]+(rx+tube*math.cos(b))*math.cos(a),center[1]+(ry+tube*math.cos(b))*math.sin(a),center[2]+tube*math.sin(b)+wave*math.sin(a)))
    for i in range(n):
        for j in range(m): faces.append((i*m+j,((i+1)%n)*m+j,((i+1)%n)*m+(j+1)%m,i*m+(j+1)%m))
    return surface(name,verts,faces,material,bone)

# Forged steel helm with nasal guard, cheek plates, rim and rivets.
dome('Helmet dome',(0,.005,1.835),(.203,.178,.205),steel,'Head')
ring('Helmet brass rim',(0,.005,1.839),.207,.181,.013,edge,'Head')
box('Nasal guard',(0,-.18,1.807),(.045,.034,.18),steel,'Head',.011)
for s in [-1,1]:
    box('Cheek plate',(s*.172,.005,1.746),(.037,.19,.19),steel,'Head',.024,rot=(0,s*.12,0))
    for z in [1.74,1.81]: ell('Helmet rivet',(s*.197,-.07,z),(.009,.01,.009),trim,'Head')
crest=[]
for i in range(25):
    a=i*math.pi/24
    for x in [-.018,.018]: crest.append((x,-.180*math.cos(a),1.841+.208*math.sin(a)))
surface('Helmet crest band',crest,[(i*2,i*2+1,i*2+3,i*2+2) for i in range(24)],edge,'Head')
for i in range(12):
    a=i*math.tau/12; ell('Rim rivet',(.211*math.cos(a),.005+.186*math.sin(a),1.84),(.010,.010,.010),trim,'Head')

# Articulated shoulder cups, turned edges, gauntlets and plated shins.
for side,s in [('L',1),('R',-1)]:
    bone='UpperArm.'+side
    dome('Pauldron',(s*.35,0,1.445),(.23,.225,.20),steel,bone)
    ring('Pauldron rolled edge',(s*.35,0,1.445),.224,.218,.014,edge,bone)
    for i in range(7):
        a=math.pi+i*math.pi/6
        ell('Shoulder rivet',(s*.35+.193*math.cos(a),.203*math.sin(a),1.49),(.012,.012,.012),trim,bone)
    box('Arm plate',(s*.51,-.104,1.005),(.17,.06,.20),steel,'Forearm.'+side,.028)
    box('Shin plate',(s*.20,-.10,.31),(.14,.055,.21),steel,'Shin.'+side,.025)

# Continuous folded cowl rather than the worker's faceted collar beads.
for i in range(4):
    ring('Cowl fold',(0,-.012,1.49-i*.016),.235+i*.012,.182+i*.013,.026,blue,'Spine',.043)

def cloth(name,y,z0,z1,width,bone):
    verts=[];faces=[];nx=12;nz=12
    for j in range(nz+1):
        t=j/nz
        for i in range(nx+1):
            u=i/nx; x=(u-.5)*width*(1-.08*t)
            verts.append((x,y+.018*math.cos(u*5*math.pi)+.025*math.sin(t*math.pi),z0+(z1-z0)*t+.015*math.sin(u*8)*t))
    for j in range(nz):
        for i in range(nx):
            a=j*(nx+1)+i;faces.append((a,a+1,a+nx+2,a+nx+1))
    obj=surface(name,verts,faces,blue,bone)
    mod=obj.modifiers.new('Cloth thickness','SOLIDIFY');mod.thickness=.014
    bpy.context.view_layer.objects.active=obj;bpy.ops.object.modifier_apply(modifier=mod.name)
cloth('Front tabard',-.205,1.45,1.075,.31,'Spine')
cloth('Apron tabard',-.21,.98,.60,.30,'Hips')
cloth('Back mantle',.23,1.48,1.13,.44,'Spine')

panel('Leather baldric',[(-.25,-.266,1.46),(-.19,-.27,1.47),(.205,-.265,1.07),(.145,-.265,1.06)],leatherlight,'Spine')

# Geometric interlinked mail along the visible skirt and side panels.
for side,s in [('L',1),('R',-1)]:
    for row in range(9):
        for col in range(8):
            x=s*(.17+col*.013); z=.68+row*.037; y=-.18+.025*math.sin(col*.4)
            bpy.ops.mesh.primitive_torus_add(major_segments=8,minor_segments=4,location=(x,y,z),rotation=(math.pi/2,0,(row%2)*.45),major_radius=.022,minor_radius=.0045)
            finish(bpy.context.object,'Mail ring',steel,'Hips')

# Convex heater shield, steel rim and crossed-tool emblem, attached to shield hand.
outline=[(-.25,.40),(.25,.40),(.29,.19),(.23,-.18),(0,-.48),(-.23,-.18),(-.29,.19)]
cx=.57;cy=-.18;cz=1.03
verts=[(cx,cy-.08,cz)]+[(cx+x,cy,cz+z) for x,z in outline]
faces=[(0,i+1,(i+1)%len(outline)+1) for i in range(len(outline))]
surface('Shield blue face',verts,faces,blue,'Forearm.L')
for i,(x,z) in enumerate(outline):
    xx,zz=outline[(i+1)%len(outline)]
    rod('Shield metal rim',(cx+x,cy-.008,cz+z),(cx+xx,cy-.008,cz+zz),.025,.025,edge,'Forearm.L',12)
    for t in [.18,.65]: ell('Shield rivet',(cx+x+(xx-x)*t,cy-.03,cz+z+(zz-z)*t),(.013,.012,.013),trim,'Forearm.L')
for s in [-1,1]:
    rod('Shield emblem',(cx+s*.12,cy-.091,cz-.16),(cx-s*.12,cy-.091,cz+.12),.020,.020,edge,'Forearm.L',4)
    box('Emblem hammer',(cx-s*.095,cy-.10,cz+.10),(.13,.018,.04),edge,'Forearm.L',.003,rot=(0,s*.70,0))
    rod('Cape emblem',(s*.09,.26,1.20),(-s*.09,.26,1.39),.014,.014,edge,'Spine',4)

# Full-length oak spear with four-sided leaf blade and socket bindings.
rod('Spear shaft',(-.52,-.075,.035),(-.52,-.075,2.30),.022,.017,wood,'Hand.R',16)
rod('Spear socket',(-.52,-.075,2.22),(-.52,-.075,2.37),.029,.024,steel,'Hand.R',16)
for z in [.13,.19,2.19,2.25]: ring('Spear binding',(-.52,-.075,z),.024,.024,.006,edge,'Hand.R')
surface('Spear leaf',[(-.52,-.075,2.76),(-.615,-.075,2.41),(-.52,-.11,2.40),(-.425,-.075,2.41),(-.52,-.041,2.40),(-.52,-.075,2.31)],[(0,1,2),(0,2,3),(0,3,4),(0,4,1),(5,2,1),(5,3,2),(5,4,3),(5,1,4)],edge,'Hand.R',False)

# Shared vertex-paint materials retain colour while avoiding dozens of draw calls.
exec(compile(base[base.index('# Join the character'):base.index('def pose(')].replace('for prefix,group in prop_groups.items():', 'for prefix,group in prop_groups.items():\n    if not group: continue'),str(Path(__file__)),'exec'))
body.name='SpearmanBody'
metalpaint.node_tree.nodes['Principled BSDF'].inputs['Roughness'].default_value=.58
# Smooth the organic forms and forged surfaces; preserve blade/cloth hard edges.
for p in body.data.polygons: p.use_smooth=True

def pose(name,xyz): rig.pose.bones[name].rotation_euler=tuple(math.radians(v) for v in xyz)
def animate(name,kind,duration):
    rig.animation_data_create();rig.animation_data.action=None;frames=int(duration*24)
    for f in range(0,frames+1,3):
        t=f/frames;w=math.sin(t*math.tau)
        for b in rig.pose.bones: b.rotation_mode='XYZ';b.rotation_euler=(0,0,0);b.location=(0,0,0)
        pose('Spine',(0,0,w));pose('Head',(w,0,0))
        if kind in ['walk','run']:
            amp=26 if kind=='walk' else 42
            for side,s in [('L',1),('R',-1)]:
                pose('Thigh.'+side,(s*amp*w,0,0));pose('Shin.'+side,(max(0,-s*w)*34,0,0))
            pose('UpperArm.R',(-10*w,0,0));pose('UpperArm.L',(5*w,0,0))
            rig.pose.bones['Root'].location.z=.02*abs(w)
        if kind in ['thrust','sweep']:
            hit=math.sin(min(1,t/.42)*math.pi/2) if t<.42 else max(0,1-(t-.42)/.58)
            pose('Hand.R',(85*hit,0,0));pose('UpperArm.R',(-64*hit,0,0));pose('Forearm.R',(-25*hit,0,0))
            # Compensate the arm rotations so the spear points toward -Y on impact.
            pose('Hand.R',(174*hit,0,0));pose('Spine',(0,0,(-32+64*t)*hit if kind=='sweep' else -7*hit))
            pose('UpperArm.L',(-16*hit,0,0));pose('Thigh.L',(-10*hit,0,0))
        if kind=='hit': pose('Spine',(-18*math.sin(t*math.pi),0,10*math.sin(t*math.pi)))
        if kind=='guard': pose('Forearm.L',(-18,0,0))
        if kind=='death':
            fall=min(1,max(0,(t-.1)/.65));pose('Root',(-88*fall,0,12*fall));rig.pose.bones['Root'].location.z=.12*fall
            pose('Thigh.L',(-20*fall,0,10*fall));pose('Shin.L',(45*fall,0,0));pose('UpperArm.R',(0,0,-30*fall))
        for b in rig.pose.bones: b.keyframe_insert('rotation_euler',frame=f+1);b.keyframe_insert('location',frame=f+1)
    action=rig.animation_data.action;action.name=name;action.use_fake_user=True
    track=rig.animation_data.nla_tracks.new();track.name=name;strip=track.strips.new(name,1,action);strip.action_slot=rig.animation_data.action_slot;track.mute=True
    rig.animation_data.action=None
for name,kind,duration in [('Idle','idle',2),('Walk','walk',1),('Run','run',.75),('Attack','thrust',.75),('AttackSweep','sweep',1),('Hit','hit',.5),('Guard','guard',2),('Death','death',1.5)]: animate(name,kind,duration)
bpy.context.scene.render.fps=24
bpy.ops.object.select_all(action='DESELECT');rig.select_set(True);body.select_set(True);bpy.context.view_layer.objects.active=rig
bpy.ops.export_scene.gltf(filepath=str(OUT/'spearman.glb'),export_format='GLB',use_selection=True,export_animations=True,export_animation_mode='NLA_TRACKS',export_force_sampling=True,export_yup=True)
rig.animation_data.action=bpy.data.actions['Idle'];rig.animation_data.action_slot=bpy.data.actions['Idle'].slots[0]
bpy.context.scene.frame_set(1);bpy.context.view_layer.update()
tail=base[base.index('# Editable source opens'):]
tail=tail.replace("2.55","3.6").replace('aim(camera,(0,0,1.0))','aim(camera,(0,0,1.30))').replace("worker.blend","spearman.blend").replace("worker_preview.png","spearman_preview.png").replace("WORKER_EXPORT_COMPLETE","SPEARMAN_EXPORT_COMPLETE")
exec(compile(tail,str(Path(__file__)),'exec'))
