"""Fit the user's untextured Meshy figure to the existing Paladin rig."""
import bpy,bmesh,math
from pathlib import Path
from mathutils import Vector
from mathutils.kdtree import KDTree
ROOT=Path(__file__).resolve().parents[2];OUT=ROOT/'assets/art/endless_paladin'
bpy.ops.wm.open_mainfile(filepath=str(OUT/'source/paladin.blend'))
rig=bpy.data.objects['PaladinRig'];old=bpy.data.objects['PaladinBody'];rig.animation_data.action=None
for b in rig.pose.bones:b.rotation_euler=(0,0,0);b.location=(0,0,0)
bpy.context.scene.frame_set(1);bpy.context.view_layer.update()
# Retain rig weights as a nearest-surface reference, without rebuilding the skeleton.
kdt=KDTree(len(old.data.vertices))
for v in old.data.vertices:kdt.insert(old.matrix_world@v.co,v.index)
kdt.balance();groups={g.index:g.name for g in old.vertex_groups};weights={v.index:[(groups[g.group],g.weight) for g in v.groups] for v in old.data.vertices}
for o in list(bpy.data.objects):
 if o!=rig:bpy.data.objects.remove(o,do_unlink=True)
bpy.ops.import_scene.gltf(filepath=r'C:\Users\Vartotojas\Downloads\Meshy_AI_Azure_Paladin_of_the__0912145903_generate.glb')
body=next(o for o in bpy.context.scene.objects if o.type=='MESH');bpy.context.view_layer.objects.active=body
bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
# The supplied mesh reconstructs both reference views side-by-side; retain the left/front figure.
bm=bmesh.new();bm.from_mesh(body.data);bmesh.ops.delete(bm,geom=[v for v in bm.verts if v.co.x>-.025],context='VERTS');bm.to_mesh(body.data);bm.free()
vs=body.data.vertices;zmin=min(v.co.z for v in vs);zmax=max(v.co.z for v in vs)
head=[v.co.x for v in vs if v.co.z>zmax-.10];cx=sum(head)/len(head);scale=1.965/(zmax-zmin)
for v in vs:v.co=Vector(((v.co.x-cx)*scale,v.co.y*scale,(v.co.z-zmin)*scale))
# Center the torso in depth while keeping supplied front orientation.
chest=[v.co.y for v in vs if 1.2<v.co.z<1.45 and abs(v.co.x)<.20];cy=(min(chest)+max(chest))/2
for v in vs:v.co.y-=cy
md=body.modifiers.new('RTS budget','DECIMATE');md.ratio=min(1,34000/(len(body.data.polygons)));md.use_collapse_triangulate=True;bpy.ops.object.modifier_apply(modifier=md.name)
body.name='PaladinBody'
# Coarse material regions intentionally do not pretend to reproduce missing texture maps.
def mat(name,c,metal=0,rough=.65):
 m=bpy.data.materials.get(name) or bpy.data.materials.new(name);m.diffuse_color=(*c,1);m.use_nodes=True;b=m.node_tree.nodes['Principled BSDF'];b.inputs['Base Color'].default_value=(*c,1);b.inputs['Metallic'].default_value=metal;b.inputs['Roughness'].default_value=rough;return m
materials=[mat('ForgedSteel',(.32,.36,.40),.65,.47),mat('AntiqueGold',(.48,.29,.085),.65,.46),mat('TeamCloth',(.008,.037,.16),0,.9),mat('Skin',(.48,.27,.18)),mat('DarkLeather',(.022,.024,.027))]
body.data.materials.clear()
for m in materials:body.data.materials.append(m)
for p in body.data.polygons:
 c=sum((body.data.vertices[i].co for i in p.vertices),Vector())/len(p.vertices);x,y,z=c;p.use_smooth=True
 idx=0
 if z>1.755 and abs(x)<.145:idx=4 if z>1.92 else 3
 elif (y>.075 and z<1.58 and abs(x)<.46) or (abs(x)<.145 and .25<z<.97 and y<-.06) or (1.65<z<1.71 and abs(x)<.23):idx=2
 elif 1.095<z<1.17 and abs(x)<.29:idx=1 if abs(x)<.075 else 4
 elif x<-.43 and 1.32<z<1.54:idx=4
 elif x<-.43 and (1.15<z<1.26 or 1.55<z<1.61):idx=1
 elif False:idx=1
 elif False:idx=1
 p.material_index=idx
for bone in rig.data.bones:body.vertex_groups.new(name=bone.name)
for v in body.data.vertices:
 x,y,z=v.co
 if x<-.43 and z<1.38:assign=[('Hand.R',1)]
 elif y>.12 and z<1.5 and abs(x)<.46:assign=[('Spine',.7),('Hips',.3)]
 elif abs(x)<.16 and z<.98 and y<-.06:assign=[('Hips',1)]
 elif z>1.61 and abs(x)<.20:assign=[('Head',1)]
 else:
  _,idx,_=kdt.find(v.co);assign=weights[idx]
 for name,w in assign:
  if name in body.vertex_groups:body.vertex_groups[name].add([v.index],w,'REPLACE')
md=body.modifiers.new('PaladinSkin','ARMATURE');md.object=rig;body.parent=rig
body.data.calc_loop_triangles();print('MESHY_PALADIN',len(body.data.loop_triangles),'triangles',len(rig.data.bones),'bones',len(bpy.data.actions),'clips')
assert len(rig.data.bones)==16 and len(bpy.data.actions)==8
bpy.ops.object.select_all(action='DESELECT');body.select_set(True);rig.select_set(True);bpy.context.view_layer.objects.active=rig
bpy.ops.export_scene.gltf(filepath=str(ROOT/'.tmp/paladin_meshy.glb'),export_format='GLB',use_selection=True,export_animation_mode='NLA_TRACKS',export_force_sampling=True)
rig.animation_data.action=bpy.data.actions['Idle'];rig.animation_data.action_slot=bpy.data.actions['Idle'].slots[0];scene=bpy.context.scene;scene.frame_set(1)
def aim(o,p):o.rotation_euler=(Vector(p)-o.location).to_track_quat('-Z','Y').to_euler()
bpy.ops.object.camera_add(location=(3,-5,3.7));cam=bpy.context.object;aim(cam,(0,0,1));cam.data.type='ORTHO';cam.data.ortho_scale=2.55;scene.camera=cam
for loc,power in [((1,-3,5),550),((-3,-1,2),280),((1,3,4),650)]:
 bpy.ops.object.light_add(type='AREA',location=loc);o=bpy.context.object;o.data.energy=power;o.data.size=3;aim(o,(0,0,1))
scene.render.engine='CYCLES';scene.cycles.samples=32;scene.render.resolution_x=950;scene.render.resolution_y=1050;scene.render.resolution_percentage=100
bpy.context.preferences.filepaths.save_version=0;bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'source/paladin_meshy.blend'))
scene.render.filepath=str(OUT/'paladin_meshy_preview.png')
if '--no-render' not in __import__('sys').argv:bpy.ops.render.render(write_still=True)
