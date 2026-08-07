extends NavigationRegion3D

## Bakes a walkable navigation mesh for the ground plane with building/resource carve-outs.


const GROUND_HALF_EXTENT := 50.0


func _ready() -> void:
	call_deferred("_deferred_bake_navigation_mesh")


func _deferred_bake_navigation_mesh() -> void:
	await get_tree().process_frame

	var nav_mesh := _create_navigation_mesh_settings()
	var source_data := NavigationMeshSourceGeometryData3D.new()
	_add_ground_plane(source_data)
	NavigationServer3D.parse_source_geometry_data(nav_mesh, source_data, get_parent())
	NavigationServer3D.bake_from_source_geometry_data(nav_mesh, source_data)
	navigation_mesh = nav_mesh


func _create_navigation_mesh_settings() -> NavigationMesh:
	var nav_mesh := NavigationMesh.new()
	nav_mesh.agent_radius = 0.55
	nav_mesh.agent_height = 2.0
	nav_mesh.cell_size = 0.25
	nav_mesh.cell_height = 0.25
	return nav_mesh


func _add_ground_plane(source_data: NavigationMeshSourceGeometryData3D) -> void:
	var plane_mesh := PlaneMesh.new()
	plane_mesh.size = Vector2(GROUND_HALF_EXTENT * 2.0, GROUND_HALF_EXTENT * 2.0)
	source_data.add_mesh(plane_mesh, Transform3D.IDENTITY)
