@tool
extends EditorScenePostImport

## Preserve vertex paint consistently across shared glTF primitive materials.
func _post_import(scene: Node) -> Object:
	for node: Node in scene.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = (node as MeshInstance3D).mesh
		for index: int in mesh.get_surface_count():
			var material: StandardMaterial3D = mesh.surface_get_material(index) as StandardMaterial3D
			if material == null:
				continue
			if material.resource_name in ["WorkerVertexPaint", "WorkerMetalPaint"]:
				material.vertex_color_use_as_albedo = true
			elif material.resource_name == "TeamCloth":
				material.vertex_color_use_as_albedo = false
	return scene
