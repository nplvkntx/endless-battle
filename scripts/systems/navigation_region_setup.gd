extends NavigationRegion3D

## Bakes a walkable navigation mesh for the ground plane with building/resource carve-outs.


const GROUND_HALF_EXTENT := 50.0


func _ready() -> void:
	call_deferred("_deferred_bake_navigation_mesh")


func _deferred_bake_navigation_mesh() -> void:
	await get_tree().process_frame

	var nav_mesh := _create_navigation_mesh_settings()
	var source_data := NavigationMeshSourceGeometryData3D.new()
	## Parse static colliders first. parse_source_geometry_data may reset the
	## source buffer — ground faces must be added afterward.
	nav_mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	if get_parent() != null:
		NavigationServer3D.parse_source_geometry_data(nav_mesh, source_data, get_parent())
	_add_ground_plane(source_data)
	NavigationServer3D.bake_from_source_geometry_data(nav_mesh, source_data)
	navigation_mesh = nav_mesh
	var world: World3D = get_world_3d()
	if world != null and world.navigation_map.is_valid():
		NavigationServer3D.map_force_update(world.navigation_map)


func _create_navigation_mesh_settings() -> NavigationMesh:
	var nav_mesh := NavigationMesh.new()
	nav_mesh.agent_radius = 0.55
	nav_mesh.agent_height = 2.0
	nav_mesh.cell_size = 0.25
	nav_mesh.cell_height = 0.25
	nav_mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	return nav_mesh


func _add_ground_plane(source_data: NavigationMeshSourceGeometryData3D) -> void:
	## Procedural faces — never add_mesh(PlaneMesh) at runtime. GPU mesh parse can
	## yield an empty navmesh, which makes map_get_closest_point return the origin
	## and permanently soft-locks V2 CREEP camp selection/execution.
	var half: float = GROUND_HALF_EXTENT
	## Clockwise winding when viewed from +Y.
	var faces := PackedVector3Array([
		Vector3(-half, 0.0, -half),
		Vector3(half, 0.0, -half),
		Vector3(half, 0.0, half),
		Vector3(-half, 0.0, -half),
		Vector3(half, 0.0, half),
		Vector3(-half, 0.0, half),
	])
	source_data.add_faces(faces, Transform3D.IDENTITY)
