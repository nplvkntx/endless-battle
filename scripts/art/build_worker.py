"""Rebuild the original Endless Battle worker with Blender 5.2.
Run: blender --background --factory-startup --python scripts/art/build_worker.py
Model faces -Y in Blender / +Z in glTF. Units are metres. No external assets.
"""
import bpy, math, os, random
from mathutils import Vector
from pathlib import Path
random.seed(12)
ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'assets/art/endless_worker'
OUT.mkdir(parents=True, exist_ok=True)
SOURCE=OUT/'source'
SOURCE.mkdir(exist_ok=True)
(SOURCE/'.gdignore').write_text('')
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)

def mat(name, color, metal=0, rough=.75):
    if not metal: color=tuple(c**2.2 for c in color)
    m=bpy.data.materials.new(name); m.diffuse_color=(*color,1); m.use_nodes=True
    bs=m.node_tree.nodes.get('Principled BSDF'); bs.inputs['Base Color'].default_value=(*color,1)
    bs.inputs['Metallic'].default_value=metal; bs.inputs['Roughness'].default_value=rough
    return m
skin=mat('Skin',(.48,.265,.14)); skinlight=mat('SkinLight',(.62,.37,.21))
shirt=mat('Linen',(.64,.57,.42)); seam=mat('LinenShadow',(.39,.33,.23))
blue=mat('TeamCloth',(.035,.13,.44)); trim=mat('ClothTrim',(.49,.36,.16))
leather=mat('Leather',(.115,.068,.035)); leatherlight=mat('LeatherEdge',(.235,.145,.073))
pants=mat('Trousers',(.075,.085,.09)); hair=mat('Hair',(.085,.042,.018)); hairlight=mat('HairHighlights',(.18,.10,.039))
steel=mat('Iron',(.30,.33,.34),.72,.38); edge=mat('IronEdge',(.56,.57,.52),.7,.33)
eye=mat('EyeWhite',(.71,.68,.53)); iris=mat('EyeIris',(.075,.105,.085)); black=mat('Dark',(.019,.013,.009))
wood=mat('Oak',(.31,.16,.06)); cutwood=mat('CutWood',(.58,.36,.16)); gold=mat('Gold',(.69,.39,.045),.55,.3)

bones={
 'Root':((0,0,0),(0,0,.25),None),
 'Hips':((0,0,.88),(0,0,1.08),'Root'),
 'Spine':((0,0,1.08),(0,0,1.49),'Hips'),
 'Head':((0,0,1.49),(0,0,1.93),'Spine'),
}
for side,s in [('L',1),('R',-1)]:
    bones.update({f'UpperArm.{side}':((s*.34,0,1.45),(s*.49,0,1.13),'Spine'),
      f'Forearm.{side}':((s*.49,0,1.13),(s*.52,-.065,.86),f'UpperArm.{side}'),
      f'Hand.{side}':((s*.52,-.065,.86),(s*.52,-.07,.72),f'Forearm.{side}'),
      f'Thigh.{side}':((s*.17,0,.9),(s*.20,0,.51),'Hips'),
      f'Shin.{side}':((s*.20,0,.51),(s*.20,0,.16),f'Thigh.{side}'),
      f'Foot.{side}':((s*.20,0,.16),(s*.20,-.19,.10),f'Shin.{side}')})
bpy.ops.object.armature_add(enter_editmode=True)
rig=bpy.context.object; rig.name='WorkerRig'
rig.data.edit_bones.remove(rig.data.edit_bones[0])
for name,(a,b,parent) in bones.items():
    bone=rig.data.edit_bones.new(name); bone.head=a; bone.tail=b
    if parent: bone.parent=rig.data.edit_bones[parent]
bpy.ops.object.mode_set(mode='OBJECT'); rig.show_in_front=True
parts=[]; props=[]

def finish(obj,name,material,bone,prop=False):
    obj.name=name; obj.data.materials.append(material)
    bpy.context.view_layer.objects.active=obj
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    if bone:
        vg=obj.vertex_groups.new(name=bone); vg.add(list(range(len(obj.data.vertices))),1,'REPLACE')
        mod=obj.modifiers.new('WorkerSkin','ARMATURE'); mod.object=rig
        obj.parent=rig
    (props if prop else parts).append(obj)
    return obj

def ell(name,loc,scale,material,bone,sub=2,prop=False):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=sub,radius=1,location=loc)
    o=bpy.context.object; o.scale=scale
    return finish(o,name,material,bone,prop)

def box(name,loc,scale,material,bone,bevel=.03,rot=(0,0,0),prop=False):
    bpy.ops.mesh.primitive_cube_add(size=1,location=loc,rotation=rot)
    o=bpy.context.object; o.scale=scale
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    if bevel:
        mod=o.modifiers.new('Soft handmade edges','BEVEL'); mod.width=bevel; mod.segments=1
        bpy.context.view_layer.objects.active=o; bpy.ops.object.modifier_apply(modifier=mod.name)
    return finish(o,name,material,bone,prop)

def rod(name,a,b,r1,r2,material,bone,vertices=10,prop=False):
    a,b=Vector(a),Vector(b); d=b-a
    bpy.ops.mesh.primitive_cone_add(vertices=vertices,radius1=r1,radius2=r2,depth=d.length,location=(a+b)/2)
    o=bpy.context.object; o.rotation_euler=d.to_track_quat('Z','Y').to_euler()
    return finish(o,name,material,bone,prop)

def panel(name,coords,material,bone):
    mesh=bpy.data.meshes.new(name); mesh.from_pydata(coords,[],[tuple(range(len(coords)))])
    mesh.update(); obj=bpy.data.objects.new(name,mesh); bpy.context.collection.objects.link(obj)
    mod=obj.modifiers.new('Cloth thickness','SOLIDIFY'); mod.thickness=.018
    bpy.context.view_layer.objects.active=obj; obj.select_set(True)
    bpy.ops.object.modifier_apply(modifier=mod.name)
    return finish(obj,name,material,bone)

# Broad shoulders, rolled linen sleeves, articulated limbs and sturdy boots.
ell('Shirt torso',(0,0,1.28),(.33,.205,.33),shirt,'Spine')
ell('Waist',(0,0,1.02),(.255,.17,.20),shirt,'Hips')
ell('Trouser seat',(0,.015,.86),(.26,.17,.18),pants,'Hips')
for side,s in [('L',1),('R',-1)]:
    upper=f'UpperArm.{side}'; fore=f'Forearm.{side}'; hand=f'Hand.{side}'
    ell('Sleeve shoulder',(s*.33,0,1.40),(.18,.18,.20),shirt,upper)
    rod('Loose sleeve',(s*.35,0,1.4),(s*.46,0,1.18),.16,.125,shirt,upper)
    rod('Rolled cuff',(s*.45,0,1.21),(s*.48,0,1.15),.153,.153,seam,upper)
    rod('Cuff linen edge',(s*.45,0,1.22),(s*.47,0,1.19),.16,.16,shirt,upper)
    ell('Forearm muscle',(s*.49,-.018,1.035),(.113,.105,.18),skinlight,fore)
    rod('Bracer',(s*.515,-.045,.94),(s*.52,-.06,.86),.108,.097,leather,fore)
    rod('Bracer rim',(s*.515,-.045,.95),(s*.516,-.048,.925),.112,.11,leatherlight,fore)
    ell('Fist',(s*.52,-.07,.785),(.10,.085,.11),skinlight,hand)
    for finger in range(4):
        ell('Knuckle',(s*.52+(finger-1.5)*.035,-.143,.79),(.025,.025,.035),skin,hand,1)
    ell('Thumb',(s*.44,-.09,.8),(.04,.045,.065),skinlight,hand)
    ell('Trouser thigh',(s*.18,0,.71),(.145,.155,.235),pants,f'Thigh.{side}')
    ell('Knee',(s*.20,-.018,.50),(.12,.125,.11),pants,f'Shin.{side}')
    rod('Boot shaft',(s*.20,0,.15),(s*.20,0,.43),.108,.139,leather,f'Shin.{side}')
    rod('Turned boot cuff',(s*.20,0,.405),(s*.20,0,.47),.16,.15,leatherlight,f'Shin.{side}')
    box('Boot sole',(s*.20,-.085,.065),(.27,.43,.09),leather,f'Foot.{side}',.025)
    ell('Boot toe',(s*.20,-.10,.135),(.14,.235,.11),leatherlight,f'Foot.{side}')
    for z in [.20,.25,.30]:
        rod('Boot stitch',(s*.20-.045,-.11,z),(s*.20+.045,-.11,z+.025),.009,.009,trim,f'Shin.{side}',6)

# Apron panels, belt, bronze stitching, pouches and cross straps.
for s in [-1,1]:
    panel('Split blue apron',[(s*.015,-.18,1.03),(s*.23,-.18,1.03),(s*.25,-.17,.69),(s*.03,-.19,.73)],blue,'Hips')
    rod('Apron hem',(s*.03,-.207,.73),(s*.245,-.19,.69),.013,.013,trim,'Hips',6)
    box('Belt side',(s*.23,0,1.015),(.065,.35,.09),leather,'Hips',.015)
box('Belt front',(0,-.183,1.015),(.49,.055,.10),leather,'Hips',.01)
box('Buckle',(0,-.221,1.015),(.15,.035,.115),edge,'Hips',.012)
box('Buckle inset',(0,-.244,1.015),(.105,.012,.074),leather,'Hips',.004)
box('Buckle tongue',(0,-.256,1.015),(.014,.014,.086),steel,'Hips',.003)
for s in [-1,1]:
    box('Pouch',(s*.29,-.03,.92),(.115,.15,.18),leatherlight,'Hips',.025)
    box('Pouch flap',(s*.29,-.111,.955),(.125,.025,.085),leather,'Hips',.012)
    ell('Pouch rivet',(s*.29,-.13,.937),(.016,.008,.016),edge,'Hips',1)
    rod('Chest harness',(s*.24,-.16,1.45),(-s*.17,-.19,1.08),.032,.032,leatherlight,'Spine',4)

# Neck, face planes, ears, eye sockets, nose, swept hair and layered beard.
rod('Neck',(0,0,1.42),(0,0,1.63),.115,.12,skin,'Head')
ell('Head',(0,-.015,1.75),(.175,.152,.235),skinlight,'Head',3)
ell('Jaw',(0,-.055,1.61),(.153,.127,.13),skin,'Head')
for s in [-1,1]:
    ell('Ear',(s*.171,-.001,1.75),(.05,.036,.074),skinlight,'Head')
    ell('Ear inset',(s*.183,-.03,1.748),(.021,.01,.040),skin,'Head')
    ell('Cheek',(s*.10,-.13,1.708),(.070,.038,.055),skinlight,'Head')
    ell('Socket',(s*.072,-.145,1.786),(.063,.019,.035),skin,'Head')
    ell('Eye',(s*.071,-.162,1.785),(.042,.009,.015),eye,'Head')
    ell('Iris',(s*.067,-.172,1.785),(.013,.006,.014),iris,'Head')
    rod('Heavy brow',(s*.021,-.17,1.811),(s*.12,-.14,1.827),.019,.028,hair,'Head',6)
ell('Nose bridge',(0,-.17,1.755),(.032,.043,.070),skinlight,'Head')
ell('Nose tip',(0,-.202,1.72),(.049,.034,.032),skinlight,'Head')
ell('Mouth shadow',(0,-.165,1.647),(.071,.018,.012),black,'Head')
ell('Beard mass',(0,-.055,1.60),(.157,.125,.14),hair,'Head')
for i in range(13):
    x=(i-6)*.022; z=1.61+.13*abs(x)/.15
    rod('Sculpted beard lock',(x,-.15,z+.045),(x*.72,-.13,1.465+.12*abs(x)/.15),.024,.006,hairlight if i%3==0 else hair,'Head',7)
for s in [-1,1]:
    rod('Moustache',(s*.006,-.197,1.68),(s*.087,-.167,1.656),.027,.014,hairlight,'Head',7)
    ell('Sideburn',(s*.14,-.048,1.72),(.033,.086,.112),hair,'Head')
ell('Hair cap',(0,.018,1.899),(.177,.151,.104),hair,'Head')
for i in range(12):
    x=(i-5.5)*.026
    rod('Swept hair',(x-.035,-.095,1.91),(x+.03,.095,1.94-abs(x)*.3),.037,.019,hairlight if i%3==0 else hair,'Head',7)
box('Headband',(0,-.138,1.878),(.31,.025,.036),leatherlight,'Head',.008)

# Thick blue cowl, hanging cloth and crossed tools on the back.
for i in range(16):
    a=i*math.tau/16
    p=(.24*math.cos(a),.18*math.sin(a),1.48+.025*math.sin(a))
    ell('Scarf fold',p,(.075,.063,.062),blue,'Spine',1)
panel('Back mantle',[(-.24,.14,1.48),(.24,.14,1.48),(.20,.208,1.16),(0,.215,1.10),(-.20,.208,1.16)],blue,'Spine')
panel('Front scarf tail',[(-.15,-.195,1.43),(.06,-.22,1.44),(.045,-.231,1.16),(-.075,-.23,1.20)],blue,'Spine')
for s in [-1,1]:
    rod('Back emblem handle',(s*.09,.222,1.21),(-s*.09,.222,1.39),.014,.014,edge,'Spine',4)
    box('Back emblem head',(-s*.08,.226,1.38),(.105,.022,.035),edge,'Spine',.003,rot=(0,s*.65,0))

# Props share the skin but remain separate meshes so the game can switch cargo.
rod('Tool_HammerHandle',(-.52,-.085,.78),(-.52,-.085,.28),.027,.022,wood,'Hand.R',10,True)
box('Tool_HammerHead',(-.52,-.085,.32),(.27,.11,.14),steel,'Hand.R',.021,prop=True)
for x in [-.66,-.38]:
    box('Tool_HammerFace',(x,-.085,.32),(.028,.12,.15),edge,'Hand.R',.008,prop=True)
rod('CargoWood_Log',(-.40,.05,1.62),(.42,.05,1.62),.13,.105,wood,'Spine',10,True)
for x in [-.40,.42]:
    rod('CargoWood_End',(x-.003,.05,1.62),(x+.003,.05,1.62),.113,.113,cutwood,'Spine',10,True)
ell('CargoGold_Sack',(0,-.30,1.2),(.21,.16,.22),leatherlight,'Spine',2,True)
for i in range(9):
    ell('CargoGold_Nugget',((i%3-1)*.06,-.30+(i//3-1)*.05,1.40),(.045,.04,.035),gold,'Spine',1,True)

# Join the character into one skinned mesh; cargo/tool meshes stay addressable.
bpy.ops.object.select_all(action='DESELECT')
for o in parts: o.select_set(True)
bpy.context.view_layer.objects.active=parts[0]; bpy.ops.object.join()
body=bpy.context.object; body.name='WorkerBody'
for p in body.data.polygons: p.use_smooth=False

# Batch rigid prop pieces and use vertex paint to keep material/draw-call count low.
grouped=[]
prop_groups={prefix:[o for o in props if o.name.startswith(prefix)] for prefix in ['Tool_', 'CargoWood', 'CargoGold']}
for prefix,group in prop_groups.items():
    bpy.ops.object.select_all(action='DESELECT')
    for o in group: o.select_set(True)
    bpy.context.view_layer.objects.active=group[0]; bpy.ops.object.join()
    obj=bpy.context.object; obj.name=prefix+'Mesh'; grouped.append(obj)
props=grouped
paint=mat('WorkerVertexPaint',(1,1,1))
metalpaint=mat('WorkerMetalPaint',(1,1,1),.7,.4)
for material in [paint,metalpaint]:
    node=material.node_tree.nodes.new('ShaderNodeVertexColor'); node.layer_name='Color'
    material.node_tree.links.new(node.outputs['Color'],material.node_tree.nodes['Principled BSDF'].inputs['Base Color'])
for obj in [body]+props:
    mesh=obj.data
    colors=mesh.color_attributes.new(name='Color',type='FLOAT_COLOR',domain='CORNER')
    ids=[]
    for polygon in mesh.polygons:
        material=mesh.materials[polygon.material_index]
        for loop in polygon.loop_indices: colors.data[loop].color=material.diffuse_color
        ids.append(2 if material==blue else (1 if material.node_tree.nodes['Principled BSDF'].inputs['Metallic'].default_value>.5 else 0))
    mesh.materials.clear()
    for material in [paint,metalpaint,blue]: mesh.materials.append(material)
    for polygon,index in zip(mesh.polygons,ids): polygon.material_index=index

def pose(name,xyz): rig.pose.bones[name].rotation_euler=tuple(math.radians(v) for v in xyz)
def animate(name,duration,kind):
    rig.animation_data_create(); rig.animation_data.action=None
    frames=int(duration*24)
    for f in range(0,frames+1,3):
        t=f/frames; wave=math.sin(t*math.tau); c=math.cos(t*math.tau)
        for b in rig.pose.bones: b.rotation_mode='XYZ'; b.rotation_euler=(0,0,0); b.location=(0,0,0)
        pose('Spine',(0,0,1.4*wave)); pose('Head',(1*wave,0,-1*wave))
        if kind in ('walk','run','carrywood','carrygold','carrywoodidle','carrygoldidle'):
            if kind.endswith('idle'): wave=0; c=1
            amp=29 if kind!='run' else 43
            for side,s in [('L',1),('R',-1)]:
                pose('Thigh.'+side,(s*amp*wave,0,0)); pose('Shin.'+side,(max(0,-s*wave)*32,0,0))
                pose('UpperArm.'+side,(-s*amp*.7*wave,0,s*3))
                pose('Forearm.'+side,(-10-max(0,s*wave)*15,0,0))
            rig.pose.bones['Root'].location.z=.025*(1-c*c)
            pose('Spine',(-5 if kind=='run' else 0,0,3*wave))
            if kind.startswith('carrywood'):
                pose('UpperArm.R',(-155,0,-12)); pose('Forearm.R',(-35,0,0))
                pose('UpperArm.L',(-65,0,10)); pose('Forearm.L',(-70,0,0))
            if kind.startswith('carrygold'):
                for side,s in [('L',1),('R',-1)]:
                    pose('UpperArm.'+side,(-48,0,-s*17)); pose('Forearm.'+side,(-77,0,0))
        elif kind in ('chop','mine','build','repair','attack'):
            # Raise on the long backswing, strike sharply, recover.
            lift=max(0,math.sin(t*math.pi))**2
            if t>.64: lift=max(0,1-(t-.64)/.18)*.82
            pose('UpperArm.R',(-25-125*lift,12,8)); pose('Forearm.R',(-15-45*lift,0,0))
            pose('UpperArm.L',(-24-40*lift,0,-15)); pose('Forearm.L',(-50,0,0))
            pose('Spine',(8-20*lift,0,-10+20*lift))
            pose('Head',(-8+8*lift,0,0))
            if kind in ('mine','repair'): pose('Spine',(24-10*lift,0,-8+16*lift))
        elif kind=='death':
            fall=min(1,max(0,(t-.1)/.6))
            pose('Root',(-86*fall,0,12*fall)); rig.pose.bones['Root'].location=(0,.18*fall,.12*fall)
            pose('Thigh.L',(-20*fall,0,15*fall)); pose('Shin.L',(45*fall,0,0))
            pose('UpperArm.R',(-35*fall,0,-38*fall)); pose('Head',(14*fall,0,15*fall))
        for b in rig.pose.bones:
            b.keyframe_insert('rotation_euler',frame=f+1); b.keyframe_insert('location',frame=f+1)
    action=rig.animation_data.action; action.name=name; action.use_fake_user=True
    track=rig.animation_data.nla_tracks.new(); track.name=name
    strip=track.strips.new(name,1,action); strip.action_slot=rig.animation_data.action_slot
    track.mute=True
    rig.animation_data.action=None

for name,duration,kind in [('Idle',2,'idle'),('Walk',1,'walk'),('Run',.75,'run'),('Attack',1,'attack'),('Chop',1.25,'chop'),('Mine',1.25,'mine'),('CarryWood',1,'carrywood'),('CarryGold',1,'carrygold'),('CarryWoodIdle',2,'carrywoodidle'),('CarryGoldIdle',2,'carrygoldidle'),('Build',1.25,'build'),('Repair',1.25,'repair'),('Death',1.5,'death')]:
    animate(name,duration,kind)
for b in rig.pose.bones: b.rotation_euler=(0,0,0); b.location=(0,0,0)
bpy.context.scene.render.fps=24
bpy.context.scene.frame_set(1)
bpy.ops.object.select_all(action='DESELECT'); rig.select_set(True); body.select_set(True)
for o in props: o.select_set(True)
bpy.context.view_layer.objects.active=rig
bpy.ops.export_scene.gltf(filepath=str(OUT/'worker.glb'),export_format='GLB',use_selection=True,
    export_animations=True,export_animation_mode='NLA_TRACKS',export_force_sampling=True,export_yup=True)

# The exporter evaluates every action; restore a real idle before saving/previewing.
rig.animation_data.action=bpy.data.actions['Idle']
rig.animation_data.action_slot=bpy.data.actions['Idle'].slots[0]
bpy.context.scene.frame_set(1)
bpy.context.view_layer.update()

# Editable source opens in a clean presentation view, with cargo hidden at rest.
for o in props:
    if o.name.startswith('Cargo'): o.hide_render=True; o.hide_set(True)
scene=bpy.context.scene
scene.world.color=(.15,.15,.15)
def aim(o,p): o.rotation_euler=(Vector(p)-o.location).to_track_quat('-Z','Y').to_euler()
bpy.ops.object.camera_add(location=(3.1,-5.5,3.0)); camera=bpy.context.object; camera.name='WorkerPresentationCamera'; aim(camera,(0,0,1.0))
camera.data.type='ORTHO'; camera.data.ortho_scale=2.55; scene.camera=camera
for loc,power,size in [((1,-3,5),550,4),((-3,-1,2),350,3),((1,3,4),700,3)]:
    bpy.ops.object.light_add(type='AREA',location=loc); o=bpy.context.object; o.data.energy=power; o.data.shape='DISK'; o.data.size=size; aim(o,(0,0,1))
scene.render.engine='CYCLES'; scene.cycles.samples=32
scene.render.resolution_x=850; scene.render.resolution_y=1000; scene.render.resolution_percentage=100
scene.render.image_settings.file_format='PNG'; scene.render.film_transparent=False
scene.world.use_nodes=True; scene.world.node_tree.nodes['Background'].inputs[0].default_value=(.035,.045,.065,1)
scene.view_settings.view_transform='AgX'
for area in bpy.context.screen.areas:
    if area.type=='VIEW_3D':
        area.spaces.active.region_3d.view_perspective='CAMERA'
        area.spaces.active.shading.type='MATERIAL'
bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE/'worker.blend'))
scene.render.filepath=str(OUT/'worker_preview.png'); bpy.ops.render.render(write_still=True)
print('WORKER_EXPORT_COMPLETE',len(body.data.vertices),'vertices',len(bpy.data.actions),'animations')
