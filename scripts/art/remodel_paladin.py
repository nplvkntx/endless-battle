"""Remodel Paladin surfaces; preserve the shipped armature and eight actions."""
import bpy, math
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[2]; OUT=ROOT/'assets/art/endless_paladin'; SOURCE=OUT/'source'
bpy.ops.wm.open_mainfile(filepath=str(SOURCE/'paladin.blend'))
rig=bpy.data.objects['PaladinRig']
for o in list(bpy.data.objects):
    if o!=rig:bpy.data.objects.remove(o,do_unlink=True)
rig.animation_data.action=None
for b in rig.pose.bones:b.rotation_euler=(0,0,0);b.location=(0,0,0)
parts=[]
def mat(name,color,metal=0,rough=.6):
    m=bpy.data.materials.new(name);m.diffuse_color=(*color,1);m.use_nodes=True
    bs=m.node_tree.nodes.get('Principled BSDF');bs.inputs['Base Color'].default_value=(*color,1);bs.inputs['Metallic'].default_value=metal;bs.inputs['Roughness'].default_value=rough
    if metal:
        noise=m.node_tree.nodes.new('ShaderNodeTexNoise');noise.inputs['Scale'].default_value=165;noise.inputs['Detail'].default_value=2
        bump=m.node_tree.nodes.new('ShaderNodeBump');bump.inputs['Strength'].default_value=.12;bump.inputs['Distance'].default_value=.012
        m.node_tree.links.new(noise.outputs['Fac'],bump.inputs['Height']);m.node_tree.links.new(bump.outputs['Normal'],bs.inputs['Normal'])
    return m
steel=mat('ForgedSteel',(.32,.37,.43),.72,.43); light=mat('SilverChest',(.64,.66,.64),.5,.45);gold=mat('AntiqueGold',(.48,.29,.085),.67,.44)
dark=mat('LeatherAndRecess',(.023,.028,.034),0,.78);blue=mat('TeamCloth',(.008,.037,.16),0,.91);skin=mat('WarmSkin',(.48,.27,.18),0,.68)
eye=mat('Eye',(.46,.47,.43),0,.45)
def mesh(name,v,f,material,bone,bevel=0,sub=0):
    me=bpy.data.meshes.new(name);me.from_pydata(v,[],f);me.update();o=bpy.data.objects.new(name,me);bpy.context.collection.objects.link(o);o.data.materials.append(material)
    bpy.context.view_layer.objects.active=o;o.select_set(True)
    if sub:
        md=o.modifiers.new('Surface refinement','SUBSURF');md.levels=sub;bpy.ops.object.modifier_apply(modifier=md.name)
    if bevel:
        md=o.modifiers.new('Forged edge bevel','BEVEL');md.width=bevel;md.segments=3;bpy.ops.object.modifier_apply(modifier=md.name)
    for p in o.data.polygons:p.use_smooth=True
    if bevel:
        md=o.modifiers.new('Plate normals','WEIGHTED_NORMAL');md.keep_sharp=True;md.weight=30;bpy.ops.object.modifier_apply(modifier=md.name)
    if bone:
        vg=o.vertex_groups.new(name=bone);vg.add(list(range(len(o.data.vertices))),1,'REPLACE');md=o.modifiers.new('PaladinSkin','ARMATURE');md.object=rig;o.parent=rig
    o.select_set(False);parts.append(o);return o
# Cross-section lofts define shaped anatomical and armor forms, rather than scaled primitives.
def loft(name,rings,material,bone,n=16,sub=0):
    v=[]
    for x,y,z,rx,ry in rings:
        for i in range(n):
            a=math.tau*i/n;v.append((x+rx*math.cos(a),y+ry*math.sin(a),z))
    f=[]
    for r in range(len(rings)-1):
        for i in range(n):a=r*n+i;b=r*n+(i+1)%n;f.append((a,b,b+n,a+n))
    f.extend([tuple(range(n-1,-1,-1)),tuple((len(rings)-1)*n+i for i in range(n))])
    return mesh(name,v,f,material,bone,sub=sub)
def tube(name,points,radius,material,bone,n=8):
    v=[]
    for i,p in enumerate(points):
        tangent=Vector(points[min(i+1,len(points)-1)])-Vector(points[max(0,i-1)])
        q=tangent.to_track_quat('Z','Y')
        for j in range(n):v.append(Vector(p)+q@Vector((radius*math.cos(j*math.tau/n),radius*math.sin(j*math.tau/n),0)))
    f=[]
    for i in range(len(points)-1):
        for j in range(n):a=i*n+j;b=i*n+(j+1)%n;f.append((a,b,b+n,a+n))
    f.extend([tuple(range(n-1,-1,-1)),tuple((len(points)-1)*n+j for j in range(n))]);return mesh(name,v,f,material,bone)
def plate(name,outline,material,bone,depth=.045,ridge=.025,trim=True):
    # Front perimeter, inset raised center, back perimeter. Edge bevel retains planar faces.
    c=sum((Vector(p) for p in outline),Vector())/len(outline);n=len(outline)
    v=list(outline)+[tuple(Vector(p)*.70+c*.30+Vector((0,-ridge,0))) for p in outline]+[(x,y+depth,z) for x,y,z in outline]
    f=[tuple(range(n,2*n))]
    for i in range(n):j=(i+1)%n;f.extend([(i,j,n+j,n+i),(i,2*n+i,2*n+j,j)])
    f.append(tuple(range(3*n-1,2*n-1,-1)));o=mesh(name,v,f,material,bone,bevel=.007)
    if trim:tube(name+' gold edging',outline+[outline[0]],.009,gold,bone)
    return o
def emblem(x,y,z,size,bone):
    # Original split sunburst, not an existing game's heraldry.
    for a in range(8):
        t=a*math.tau/8;u=(math.sin(t),math.cos(t));p=(x+u[0]*size*.45,y,z+u[1]*size*.45);q=(x+u[0]*size,y,z+u[1]*size)
        tube('Sun rays',[p,q],.006,gold,bone,6)
    plate('Sun jewel',[(x,y-.009,z+size*.52),(x+size*.32,y-.014,z),(x,y-.009,z-size*.52),(x-size*.32,y-.014,z)],gold,bone,.016,.006,False)
loft('Arming doublet',[(0,0,.86,.215,.13),(0,0,1.02,.215,.15),(0,0,1.23,.27,.16),(0,0,1.43,.30,.16),(0,0,1.51,.24,.14)],dark,'Spine',24)
# Breastplate consists of separate breast, rib and overlapping abdominal plates.
plate('Sculpted breastplate',[(-.28,-.12,1.48),(-.12,-.20,1.53),(.12,-.20,1.53),(.28,-.12,1.48),(.27,-.20,1.29),(.13,-.235,1.21),(0,-.25,1.18),(-.13,-.235,1.21),(-.27,-.20,1.29)],light,'Spine',.12,.038)
for i in range(3):
    z=1.21-i*.075;w=.235-i*.009
    plate('Overlapping fauld '+str(i),[(-w,-.17,z+.045),(0,-.22,z+.025),(w,-.17,z+.045),(w,-.18,z-.023),(0,-.235,z-.052),(-w,-.18,z-.023)],steel,'Hips',.05,.013)
emblem(0,-.298,1.37,.09,'Spine')
tube('Chest spine',[(0,-.295,1.45),(0,-.30,1.28),(0,-.271,1.20)],.009,gold,'Spine')
for side,s in [('L',1),('R',-1)]:
    up='UpperArm.'+side;fo='Forearm.'+side;ha='Hand.'+side;th='Thigh.'+side;sh='Shin.'+side;ft='Foot.'+side
    def mirror(points):return [(s*x,y,z) for x,y,z in points]
    # Angular domed shoulders loft across a custom arched profile.
    v=[];f=[]
    for x,zbase,w,h in [(.245,1.48,.16,.09),(.27,1.48,.19,.14),(.39,1.47,.205,.15),(.51,1.44,.18,.13),(.55,1.42,.15,.06)]:
        for j in range(9):
            a=math.pi*j/8;v.append((s*x,-w*math.cos(a),zbase+h*math.sin(a)))
    for r in range(4):
        for j in range(8):i=r*9+j;f.append((i,i+1,i+10,i+9))
    o=mesh('Arched pauldron',v,f,steel,up)
    bpy.context.view_layer.objects.active=o;md=o.modifiers.new('Plate thickness','SOLIDIFY');md.thickness=.025;bpy.ops.object.modifier_apply(modifier=md.name)
    for row in [0,4]:tube('Pauldron arch rim',v[row*9:row*9+9],.014,gold,up)
    for edgeid in [0,8]:tube('Pauldron rolled border',[v[r*9+edgeid] for r in range(5)],.014,gold,up)
    plate('Shoulder face',mirror([(.27,-.195,1.51),(.39,-.215,1.55),(.51,-.183,1.47),(.49,-.18,1.37),(.35,-.19,1.38)]),steel,up,.035,.025)
    emblem(s*.39,-.242,1.465,.058,up)
    for i in range(2):
        x=.435+i*.032;z=1.36-i*.085
        plate('Shoulder articulated lame',mirror([(x-.09,-.13,z+.055),(x+.09,-.11,z+.045),(x+.09,-.11,z-.03),(x,-.17,z-.065),(x-.07,-.15,z-.03)]),steel,up,.22,.014)
    loft('Upper arm articulation',[(s*.39,0,1.36,.09,.10),(s*.46,0,1.20,.085,.085),(s*.485,0,1.13,.075,.08)],dark,up,16)
    plate('Elbow couter',mirror([(.42,-.10,1.18),(.52,-.115,1.19),(.57,-.10,1.12),(.50,-.14,1.06),(.43,-.12,1.10)]),steel,fo,.13,.02)
    loft('Forearm leather',[(s*.49,0,1.12,.078,.08),(s*.52,-.045,.86,.067,.07)],dark,fo)
    plate('Tapered vambrace',mirror([(.41,-.10,1.10),(.55,-.10,1.11),(.60,-.12,.91),(.54,-.16,.855),(.45,-.15,.88)]),steel,fo,.13,.018)
    tube('Bracer raised ridge',mirror([(.48,-.143,1.06),(.52,-.178,.9)]),.008,gold,fo)
    loft('Palm',[(s*.52,-.07,.735,.073,.063),(s*.52,-.07,.81,.077,.075),(s*.52,-.07,.875,.066,.065)],dark,ha,16)
    for i in range(3):
        z=.85-i*.039
        plate('Gauntlet finger plates',mirror([(.45,-.135,z+.02),(.575,-.135,z+.02),(.577,-.15,z-.012),(.455,-.15,z-.014)]),steel,ha,.045,.004,False)
    for i in range(4):
        x=.466+i*.03;tube('Finger articulation',mirror([(x,-.145,.77),(x,-.143,.735),(x,-.10,.727)]),.014,steel,ha,8)
    loft('Leg underlayer',[(s*.175,0,.9,.103,.11),(s*.19,0,.68,.097,.11),(s*.20,0,.51,.08,.083),(s*.20,0,.17,.069,.078)],dark,th,20)
    plate('Sculpted cuisse',mirror([(.085,-.085,.89),(.25,-.08,.90),(.285,-.09,.71),(.24,-.13,.60),(.135,-.135,.61),(.09,-.12,.72)]),steel,th,.15,.025)
    tube('Thigh plate ridge',mirror([(.18,-.145,.86),(.20,-.178,.65)]),.007,gold,th)
    plate('Pointed knee armor',mirror([(.12,-.10,.59),(.20,-.14,.635),(.285,-.09,.55),(.265,-.13,.48),(.20,-.17,.455),(.125,-.13,.49)]),steel,sh,.15,.025)
    plate('Anatomical greave',mirror([(.12,-.085,.47),(.20,-.13,.50),(.28,-.085,.46),(.258,-.10,.17),(.20,-.14,.12),(.13,-.10,.16)]),steel,sh,.155,.023)
    tube('Shin ridge',mirror([(.20,-.18,.46),(.20,-.183,.18)]),.008,gold,sh)
    loft('Boot foundation',[(s*.20,-.06,.055,.117,.19),(s*.20,-.06,.10,.12,.195),(s*.20,-.03,.17,.105,.14)],dark,ft,20)
    for i in range(4):
        y=.02-i*.063;z=.20-i*.025
        plate('Overlapping sabaton',mirror([(.09,y,z-.018),(.14,y-.04,z+.025),(.25,y-.04,z+.025),(.31,y,z-.018),(.30,y-.074,z-.043),(.10,y-.074,z-.043)]),steel,ft,.025,.005,False)
    tube('Boot toe edge',mirror([(.10,-.23,.074),(.20,-.27,.067),(.30,-.23,.074)]),.01,gold,ft)
    plate('Suspended hip tasset',mirror([(.13,-.17,1.0),(.27,-.105,.98),(.32,-.12,.78),(.24,-.17,.72),(.15,-.20,.78)]),steel,'Hips',.035,.016)
# Folded cloth surfaces with closed thickness; skin to existing bones.
def cloth(name,rows,cols,point,bone,sub=1):
    v=[point(r/(rows-1),c/(cols-1)) for r in range(rows) for c in range(cols)];f=[]
    for r in range(rows-1):
        for c in range(cols-1):i=r*cols+c;f.append((i,i+1,i+1+cols,i+cols))
    o=mesh(name,v,f,blue,bone,sub=sub);bpy.context.view_layer.objects.active=o
    md=o.modifiers.new('Woven thickness','SOLIDIFY');md.thickness=.012;bpy.ops.object.modifier_apply(modifier=md.name)
    # modifier after binding creates vertices: ensure all newly created vertices have same bone group.
    o.vertex_groups[bone].add(list(range(len(o.data.vertices))),1,'REPLACE');return o
cloth('Flowing royal cape',13,17,lambda t,u:((u-.5)*(.47+.27*t),.17+.17*t+.045*math.sin(u*math.pi*8)*(.3+.7*t),1.51-1.03*t+.025*math.cos(u*math.pi*4)*t),'Spine',2)
# Lower cape follows the hip joint, preserving the original skeleton.
o=parts[-1];vg=o.vertex_groups.new(name='Hips')
for v in o.data.vertices:
    w=max(0,min(.65,(1.1-v.co.z)));vg.add([v.index],w,'REPLACE');o.vertex_groups['Spine'].add([v.index],1-w,'REPLACE')
for u in [0,1]:tube('Cape side piping',[( (u-.5)*(.47+.27*t),.17+.17*t+.045*math.sin(u*math.pi*8)*(.3+.7*t),1.51-1.03*t+.025*math.cos(u*math.pi*4)*t) for t in [i/16 for i in range(17)]],.009,gold,'Spine')
cloth('Waist tabard',9,13,lambda t,u:((u-.5)*(.27+.03*t),-.224-.032*math.cos(u*math.pi*6)-.016*t,1.0-.46*t-.045*math.sin(u*math.pi)*t),'Hips',2)
for u in [0,1]:tube('Tabard border',[((u-.5)*(.27+.03*t),-.227-.032*math.cos(u*math.pi*6)-.016*t,1-.46*t) for t in [i/10 for i in range(11)]],.009,gold,'Hips')
emblem(0,-.275,.76,.058,'Hips')
# Scarf is an irregular draped annulus with several natural folds.
v=[];f=[]
for r in range(7):
    t=r/6
    for c in range(40):
        a=c*math.tau/40;rad=.105+.12*t
        v.append((rad*math.cos(a),rad*.79*math.sin(a)-.015,1.61-.115*t-.07*max(0,-math.sin(a))*t+.009*math.sin(t*math.pi*6+a*2)))
for r in range(6):
    for c in range(40):i=r*40+c;j=r*40+(c+1)%40;f.append((i,j,j+40,i+40))
o=mesh('Folded blue mantle',v,f,blue,'Spine',sub=1)
loft('Wide leather belt',[(0,0,.985,.242,.17),(0,0,1.045,.242,.17)],dark,'Hips',32)
plate('Ornamental belt clasp',[(-.064,-.218,1.065),(.064,-.218,1.065),(.082,-.218,1.017),(.05,-.218,.96),(-.05,-.218,.96),(-.082,-.218,1.017)],gold,'Hips',.026,.008)
emblem(0,-.252,1.016,.043,'Hips')
# Human head: continuous ring mesh with shaped jaw, cheeks, eye sockets and brow ridge.
loft('Neck',[(0,.008,1.49,.084,.081),(0,.008,1.66,.085,.083)],skin,'Head',24,1)
rings=[(1.60,.064,.070,-.015),(1.625,.091,.088,-.012),(1.66,.112,.103,0),(1.71,.122,.11,.006),(1.765,.13,.114,.008),(1.805,.126,.113,.012),(1.845,.125,.111,.018),(1.90,.116,.100,.024),(1.94,.085,.080,.025),(1.965,.03,.03,.025)]
v=[];f=[];n=48
for z,rx,ry,cy in rings:
    for i in range(n):
        a=math.tau*i/n;x=rx*math.cos(a);y=cy+ry*math.sin(a)
        front=max(0,-math.sin(a))**10
        if abs(z-1.805)<.001:y+=.012*front # eye socket recess
        if abs(z-1.845)<.001:y-=.010*front # brow ridge
        if abs(z-1.71)<.001:y-=.01*front # mouth/chin plane
        v.append((x,y,z))
for r in range(len(rings)-1):
    for i in range(n):a=r*n+i;b=r*n+(i+1)%n;f.append((a,b,b+n,a+n))
f.extend([tuple(range(n-1,-1,-1)),tuple((len(rings)-1)*n+i for i in range(n))]);mesh('Defined human face',v,f,skin,'Head',sub=2)
# Integrated-looking nasal bridge and nostril contours from deliberate section profiles.
loft('Nasal bridge',[(0,-.116,1.735,.025,.015),(0,-.139,1.747,.032,.022),(0,-.148,1.76,.022,.025),(0,-.121,1.80,.014,.022),(0,-.103,1.84,.018,.012)],skin,'Head',16,2)
for s in [-1,1]:
    # almond eye surfaces, inset iris, and soft eyelids avoid block eyebrows.
    x=s*.055;z=1.801;y=-.101
    plate('Inset eye',[(x-.026,y,z),(x-.012,y-.008,z+.01),(x+.014,y-.008,z+.009),(x+.026,y,z),(x+.012,y-.008,z-.007),(x-.012,y-.008,z-.006)],eye,'Head',.008,.001,False)
    tube('Upper eyelid',[(x-.027,y-.003,z+.001),(x-.012,y-.012,z+.011),(x+.014,y-.012,z+.010),(x+.027,y-.003,z)],.004,skin,'Head')
    tube('Dark iris',[(x,-.114,z-.005),(x,-.114,z+.006)],.006,dark,'Head',10)
    tube('Tapered brow',[(s*.028,-.12,1.833),(s*.053,-.118,1.839),(s*.081,-.108,1.835),(s*.097,-.091,1.831)],.0045,dark,'Head')
    loft('Sculpted ear',[(s*.126,.014,1.70,.012,.016),(s*.14,.01,1.735,.018,.025),(s*.145,.008,1.78,.020,.029),(s*.137,.01,1.815,.015,.018)],skin,'Head',16,2)
    tube('Ear antihelix',[(s*.145,-.014,1.72),(s*.156,-.016,1.75),(s*.156,-.014,1.79),(s*.143,-.013,1.80)],.005,skin,'Head')
tube('Mouth crease',[(-.038,-.110,1.697),(-.016,-.117,1.695),(0,-.118,1.697),(.019,-.116,1.695),(.036,-.110,1.698)],.0025,dark,'Head')
tube('Lower lip',[(-.025,-.114,1.690),(0,-.12,1.687),(.025,-.114,1.690)],.004,skin,'Head')
# Close cropped hair follows skull, tapered at temples.
v=[];f=[]
for r in range(9):
    t=r/8
    for i in range(48):
        a=math.tau*i/48;phi=(.13+t*1.38);v.append((.126*math.sin(phi)*math.cos(a),.022+.11*math.sin(phi)*math.sin(a),1.845+.126*math.cos(phi)-.025*t*max(0,math.sin(a))))
for r in range(8):
    for i in range(48):a=r*48+i;b=r*48+(i+1)%48;f.append((a,b,b+48,a+48))
mesh('Short dark crop',v,f,dark,'Head',sub=1)
# Greatsword: longer grip, broad fuller blade, sweeping gold quillons, inset blue gem.
x=-.52;y=-.08
loft('Long sword grip',[(x,y,.70,.033,.03),(x,y,.98,.032,.03)],dark,'Hand.R',16)
for i in range(10):
    z=.715+i*.025;tube('Grip wrap',[(x+.034*math.cos(a),y+.031*math.sin(a),z+.012*a/math.tau) for a in [j*math.tau/16 for j in range(17)]],.004,gold,'Hand.R',6)
plate('Crowned pommel',[(x-.045,y-.01,.98),(x-.05,y-.01,1.02),(x,y-.01,1.073),(x+.05,y-.01,1.02),(x+.045,y-.01,.98)],gold,'Hand.R',.045,.01)
for s in [-1,1]:
    plate('Swept sword quillon',[(x+s*.02,y-.035,.725),(x+s*.10,y-.035,.75),(x+s*.19,y-.035,.805),(x+s*.23,y-.035,.76),(x+s*.14,y-.035,.69),(x+s*.025,y-.035,.67)],gold,'Hand.R',.065,.012,False)
plate('Guard sapphire',[(x,y-.075,.76),(x+.04,y-.075,.714),(x,y-.075,.66),(x-.04,y-.075,.714)],blue,'Hand.R',.028,.009)
# Blade length extended diagonally so it remains within the existing ground clearance.
v=[]
for z,w in [(.66,.105),(.61,.118),(.19,.086),(.07,.0)]:
    for dx,dy in [(-w,0),(-w*.67,-.018),(0,-.03),(w*.67,-.018),(w,0),(w*.67,.018),(0,.03),(-w*.67,.018)]:v.append((x+dx,y+dy,z))
f=[]
for r in range(3):
    for i in range(8):a=r*8+i;b=r*8+(i+1)%8;f.append((a,b,b+8,a+8))
f.append(tuple(range(7,-1,-1)));mesh('Broad forged greatsword',v,f,light,'Hand.R',bevel=.002)
for s in [-1,1]:tube('Blade fuller',[(x+s*.025,y-.029,.59),(x+s*.019,y-.029,.22),(x,y-.023,.14)],.004,steel,'Hand.R',6)
# Join one skinned body with seven shared material surfaces.
bpy.ops.object.select_all(action='DESELECT')
for o in parts:o.select_set(True)
bpy.context.view_layer.objects.active=parts[0];bpy.ops.object.join();body=bpy.context.object;body.name='PaladinBody'
# Consolidate duplicate material slots after joining.
slots=list(body.data.materials);unique=[];mapping=[]
for m in slots:
    if m not in unique:unique.append(m)
    mapping.append(unique.index(m))
ids=[mapping[p.material_index] for p in body.data.polygons];body.data.materials.clear()
for m in unique:body.data.materials.append(m)
for p,i in zip(body.data.polygons,ids):p.material_index=i
bpy.context.view_layer.objects.active=body
md=body.modifiers.new('RTS triangle budget','DECIMATE');md.ratio=.49;md.use_collapse_triangulate=True;bpy.ops.object.modifier_apply(modifier=md.name)
body.data.calc_loop_triangles();print('PALADIN_REMODEL triangles',len(body.data.loop_triangles),'bones',len(rig.data.bones),'actions',len(bpy.data.actions),'materials',len(unique))
assert len(rig.data.bones)==16 and len(bpy.data.actions)==8
scene=bpy.context.scene;scene.frame_set(1)
bpy.ops.object.select_all(action='DESELECT');body.select_set(True);rig.select_set(True);bpy.context.view_layer.objects.active=rig
bpy.ops.export_scene.gltf(filepath=str(ROOT/'.tmp/paladin_remodeled.glb'),export_format='GLB',use_selection=True,export_animation_mode='NLA_TRACKS',export_force_sampling=True)
rig.animation_data.action=bpy.data.actions['Idle'];rig.animation_data.action_slot=bpy.data.actions['Idle'].slots[0];scene.frame_set(1)
def aim(o,p):o.rotation_euler=(Vector(p)-o.location).to_track_quat('-Z','Y').to_euler()
bpy.ops.object.camera_add(location=(3,-5,3.8));cam=bpy.context.object;aim(cam,(0,0,1.0));cam.data.type='ORTHO';cam.data.ortho_scale=2.45;scene.camera=cam
for loc,power,size in [((1,-3,5),500,4),((-3,-1,2),230,3),((1,3,4),650,3)]:
    bpy.ops.object.light_add(type='AREA',location=loc);o=bpy.context.object;o.data.energy=power;o.data.size=size;aim(o,(0,0,1))
scene.world.use_nodes=True;scene.world.node_tree.nodes['Background'].inputs[0].default_value=(.025,.033,.045,1)
scene.render.engine='CYCLES';scene.cycles.samples=48;scene.render.resolution_x=1100;scene.render.resolution_y=1200;scene.render.resolution_percentage=100
scene.view_settings.view_transform='AgX';bpy.context.preferences.filepaths.save_version=0
bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE/'paladin.blend'))
scene.render.filepath=str(OUT/'paladin_preview.png');bpy.ops.render.render(write_still=True)
