extends Node

## Shared player/AI formation manager: create, move, dissolve, preview, and role slots.

signal formation_applied(formation_id: int, unit_count: int)
signal formation_cleared()
signal player_formation_prefs_changed(shape: int, size_preset: int)
signal formations_changed()

const PREVIEW_SLOT_Y := 0.08
const PREVIEW_DURATION := 1.15
const ROTATION_RECOMPUTE_DOT := 0.92 ## ~23 degrees
const LARGE_FORMATION_STAGGER := 8
const ORDER_SKIP_DISTANCE := 0.85
const AI_REFORM_MEMBER_DELTA := 3

var player_shape: FormationLayout.Shape = FormationLayout.Shape.SQUARE
var player_size_preset: int = 15

## formation_id -> FormationGroup
var _formations: Dictionary = {}
## unit_instance_id -> formation_id
var _unit_to_formation: Dictionary = {}
var _next_formation_id: int = 1

## Preview nodes
var _preview_root: Node3D = null
var _preview_timer: float = 0.0
var _process_accum: float = 0.0

## AI state to avoid reissuing identical formation orders
var _ai_last_signature: String = ""
var _ai_last_shape: int = -1
var _ai_last_size: int = -1
var _ai_formation_ids: Array[int] = []


func _ready() -> void:
	MatchSession.register_match_reset(&"FormationManager", clear_all)
	set_process(true)


func _process(delta: float) -> void:
	_process_accum += delta
	if _preview_timer > 0.0:
		_preview_timer -= delta
		if _preview_timer <= 0.0:
			hide_preview()

	# Staggered housekeeping ~4 Hz
	if _process_accum < 0.25:
		return
	_process_accum = 0.0
	_purge_all_dead()


func clear_all() -> void:
	_formations.clear()
	_unit_to_formation.clear()
	_next_formation_id = 1
	_ai_last_signature = ""
	_ai_last_shape = -1
	_ai_last_size = -1
	_ai_formation_ids.clear()
	FormationLayout.clear_cache()
	hide_preview()
	formation_cleared.emit()
	formations_changed.emit()


func set_player_shape(shape: FormationLayout.Shape) -> void:
	player_shape = shape
	player_formation_prefs_changed.emit(int(player_shape), player_size_preset)


func set_player_size(size_preset: int) -> void:
	if not size_preset in FormationLayout.SIZE_PRESETS:
		return
	player_size_preset = size_preset
	player_formation_prefs_changed.emit(int(player_shape), player_size_preset)


func get_player_shape() -> FormationLayout.Shape:
	return player_shape


func get_player_size() -> int:
	return player_size_preset


func get_formation(formation_id: int) -> FormationGroup:
	return _formations.get(formation_id) as FormationGroup


func get_unit_formation_id(unit: Node) -> int:
	if unit == null or not is_instance_valid(unit):
		return -1
	return int(_unit_to_formation.get(unit.get_instance_id(), -1))


func get_unit_formation(unit: Node) -> FormationGroup:
	var fid: int = get_unit_formation_id(unit)
	if fid < 0:
		return null
	return get_formation(fid)


func is_unit_in_formation(unit: Node) -> bool:
	return get_unit_formation_id(unit) >= 0


func collect_eligible_units(units: Array, allow_siege: bool = true) -> Array:
	var eligible: Array = []
	for unit: Variant in units:
		if UnitFormationRole.is_formation_eligible(unit as Node, allow_siege):
			eligible.append(unit)
	return eligible


func collect_heroes(units: Array) -> Array:
	var heroes: Array = []
	for unit: Variant in units:
		if NodeSafety.is_alive_node(unit) and unit is Hero:
			heroes.append(unit)
	return heroes


## Create one or more formations from selected units using current player prefs.
func form_selected_units(units: Array, shape: int = -1, size_preset: int = -1) -> Array[int]:
	var resolved_shape: FormationLayout.Shape = player_shape if shape < 0 else (shape as FormationLayout.Shape)
	var resolved_size: int = player_size_preset if size_preset < 0 else size_preset
	var allow_siege: bool = FormationLayout.supports_siege_slots(resolved_shape)
	var eligible: Array = collect_eligible_units(units, allow_siege)
	# If siege excluded by shape but cannons selected, still allow on shapes that support rear slots
	if eligible.is_empty():
		eligible = collect_eligible_units(units, true)

	# Remove from previous formations
	for unit: Variant in eligible:
		_remove_unit_from_any_formation(unit as Node)

	var created_ids: Array[int] = []
	if eligible.is_empty():
		return created_ids

	eligible.sort_custom(UnitFormationRole.compare_units_front_first)
	var chunks: Array = _split_into_chunks(eligible, resolved_size)
	for chunk: Variant in chunks:
		var group_units: Array = chunk as Array
		var fid: int = _create_formation(group_units, resolved_shape, resolved_size, false, 0)
		created_ids.append(fid)
		formation_applied.emit(fid, group_units.size())

	formations_changed.emit()
	return created_ids


func dissolve_units(units: Array) -> void:
	var touched: Dictionary = {}
	for unit: Variant in units:
		if not NodeSafety.is_alive_node(unit):
			continue
		var fid: int = get_unit_formation_id(unit as Node)
		if fid < 0:
			continue
		touched[fid] = true
		_unbind_unit(unit as Node)

	for fid: Variant in touched.keys():
		var group: FormationGroup = get_formation(int(fid))
		if group == null:
			continue
		group.purge_dead()
		if group.member_count() <= 0:
			_formations.erase(int(fid))
		else:
			group.needs_reassign = true

	formations_changed.emit()
	if _formations.is_empty():
		formation_cleared.emit()


func dissolve_formation(formation_id: int) -> void:
	var group: FormationGroup = get_formation(formation_id)
	if group == null:
		return
	for unit: Variant in group.get_alive_members():
		_unbind_unit(unit as Node)
	_formations.erase(formation_id)
	formations_changed.emit()
	if _formations.is_empty():
		formation_cleared.emit()


func dissolve_selected_formations(units: Array) -> void:
	var ids: Dictionary = {}
	for unit: Variant in units:
		var fid: int = get_unit_formation_id(unit as Node)
		if fid >= 0:
			ids[fid] = true
	for fid: Variant in ids.keys():
		dissolve_formation(int(fid))


## Issue move / attack-move / patrol-style destinations for units that share formations.
## Returns true if at least one formation-aware order was issued.
func issue_formation_ground_order(
	units: Array,
	destination: Vector3,
	order_kind: StringName,
	queued: bool = false
) -> bool:
	## Player Move / Attack-Move permanently owned by PlayerRouteNavigation.
	## Formation layout no longer steers player march orders.
	if PlayerRouteNavigation.are_player_formations_disabled():
		var routed: Dictionary = PlayerRouteNavigation.issue_command(
			units, destination, order_kind, queued
		)
		return bool(routed.get("handled", false))

	var by_formation: Dictionary = {}
	var unformed: Array = []
	var heroes: Array = []

	for unit: Variant in units:
		if not NodeSafety.is_alive_node(unit):
			continue
		if unit is Hero:
			heroes.append(unit)
			continue
		var fid: int = get_unit_formation_id(unit as Node)
		if fid < 0:
			unformed.append(unit)
			continue
		if not by_formation.has(fid):
			by_formation[fid] = []
		(by_formation[fid] as Array).append(unit)

	if by_formation.is_empty():
		return false

	var issued := false
	var preview_shown := false
	for fid: Variant in by_formation.keys():
		var group: FormationGroup = get_formation(int(fid))
		if group == null:
			continue
		var members: Array = by_formation[fid] as Array
		group.recompute_anchor_from_members()
		var from_center: Vector3 = group.anchor
		group.anchor = destination
		var face_dir: Vector3 = destination - from_center
		face_dir.y = 0.0
		if face_dir.length_squared() >= 0.01:
			group.forward = face_dir.normalized()
		group.ensure_slots_assigned()

		if SharedSquadNavigation.is_shared_navigation_enabled():
			var squad_result: Dictionary = SharedSquadNavigation.issue_formation_command(
				int(fid),
				members,
				destination,
				order_kind,
				group
			)
			if squad_result.get("handled", false):
				if not preview_shown:
					show_preview(group)
					preview_shown = true
				for hero: Variant in heroes:
					var follow: Vector3 = _hero_follow_world(hero as Hero, group)
					_issue_unit_order(hero as Unit, follow, order_kind, queued, 0)
					issued = true
				heroes.clear()
				issued = true
				continue

		if not preview_shown:
			show_preview(group)
			preview_shown = true

		var signature: String = "%d:%s:%.1f:%.1f:%s" % [
			int(fid),
			String(order_kind),
			destination.x,
			destination.z,
			queued,
		]
		if signature == group.last_order_signature and not queued:
			# Still issue if units drifted far
			pass
		group.last_order_signature = signature

		var member_list: Array = group.get_alive_members()
		var stagger: int = LARGE_FORMATION_STAGGER if member_list.size() >= 40 else member_list.size()
		var start: int = group.stagger_cursor % maxi(member_list.size(), 1)
		group.stagger_cursor = (start + stagger) % maxi(member_list.size(), 1)

		for index: int in member_list.size():
			var unit: Variant = member_list[index]
			if not members.has(unit):
				# Selected subset: only order selected formation members
				continue
			var target: Vector3 = group.get_world_slot_for_unit(unit as Node)
			target = GroupMoveSpacing.resolve_formation_position(target, destination)
			if unit is Node3D:
				var dist: float = _horizontal_distance((unit as Node3D).global_position, target)
				if dist <= ORDER_SKIP_DISTANCE and order_kind != &"retreat":
					continue
			_issue_unit_order(unit as Unit, target, order_kind, queued, index)
			issued = true

		# Heroes follow nearby first formation
		for hero: Variant in heroes:
			var follow: Vector3 = _hero_follow_world(hero as Hero, group)
			_issue_unit_order(hero as Unit, follow, order_kind, queued, 0)
			issued = true
		heroes.clear()

	# Unformed military in the same selection keep simple spacing around destination
	if not unformed.is_empty():
		if (
			SharedSquadNavigation.is_shared_navigation_enabled()
			and unformed.size() > 1
		):
			var player_result: Dictionary = SharedSquadNavigation.issue_player_group_command(
				unformed,
				destination,
				order_kind,
				queued
			)
			if player_result.get("handled", false):
				issued = true
			else:
				var targets: Array[Vector3] = GroupMoveSpacing.compute_targets(
					destination, unformed.size()
				)
				for i: int in unformed.size():
					_issue_unit_order(unformed[i] as Unit, targets[i], order_kind, queued, i)
					issued = true
		else:
			var targets: Array[Vector3] = GroupMoveSpacing.compute_targets(
				destination, unformed.size()
			)
			for i: int in unformed.size():
				_issue_unit_order(unformed[i] as Unit, targets[i], order_kind, queued, i)
				issued = true

	return issued


func compute_attack_approach_slots(units: Array, target: Node3D) -> Dictionary:
	## Returns unit_instance_id -> approach position for direct attacks.
	var result: Dictionary = {}
	if target == null or not is_instance_valid(target):
		return result

	var by_formation: Dictionary = {}
	for unit: Variant in units:
		if not NodeSafety.is_alive_node(unit) or unit is Hero:
			continue
		var fid: int = get_unit_formation_id(unit as Node)
		if fid < 0:
			continue
		if not by_formation.has(fid):
			by_formation[fid] = []
		(by_formation[fid] as Array).append(unit)

	for fid: Variant in by_formation.keys():
		var group: FormationGroup = get_formation(int(fid))
		if group == null:
			continue
		group.recompute_anchor_from_members()
		var to_target: Vector3 = target.global_position - group.anchor
		to_target.y = 0.0
		if to_target.length_squared() < 0.01:
			to_target = group.forward
		else:
			to_target = to_target.normalized()
		group.forward = to_target
		# Approach anchor short of the target
		var approach_anchor: Vector3 = target.global_position - to_target * 4.0
		group.anchor = approach_anchor
		group.ensure_slots_assigned()
		for unit: Variant in by_formation[fid] as Array:
			result[(unit as Node).get_instance_id()] = group.get_world_slot_for_unit(unit as Node)

	return result


func notify_combat_ended_for_units(units: Array) -> void:
	var ids: Dictionary = {}
	for unit: Variant in units:
		var fid: int = get_unit_formation_id(unit as Node)
		if fid >= 0:
			ids[fid] = true
	for fid: Variant in ids.keys():
		var group: FormationGroup = get_formation(int(fid))
		if group != null:
			group.combat_reform_pending = true


func reform_pending_groups() -> void:
	for fid: Variant in _formations.keys():
		var group: FormationGroup = _formations[fid] as FormationGroup
		if group == null or not group.combat_reform_pending:
			continue
		group.combat_reform_pending = false
		group.purge_dead()
		group.recompute_anchor_from_members()
		group.needs_reassign = true
		group.ensure_slots_assigned()
		for unit: Variant in group.get_alive_members():
			var target: Vector3 = group.get_world_slot_for_unit(unit as Node)
			if unit is Unit and (unit as Unit).has_method("issue_order"):
				(unit as Unit).issue_order(UnitOrder.move(target), false)


## AI: ensure army is formed with logical shape/size; returns formation ids.
func ai_ensure_formations(
	units: Array,
	army_mode_name: StringName,
	defending: bool = false
) -> Array[int]:
	var eligible: Array = collect_eligible_units(units, true)
	if eligible.is_empty():
		_ai_dissolve_tracked()
		return []

	var has_siege := false
	for unit: Variant in eligible:
		if UnitFormationRole.get_role(unit as Node) == UnitFormationRole.Role.SIEGE:
			has_siege = true
			break

	var shape: FormationLayout.Shape = FormationLayout.choose_ai_shape(army_mode_name, has_siege, defending)
	var size_preset: int = FormationLayout.choose_ai_size(eligible.size())
	var signature: String = _ai_membership_signature(eligible, shape, size_preset)

	if (
		signature == _ai_last_signature
		and shape == (_ai_last_shape as FormationLayout.Shape)
		and size_preset == _ai_last_size
		and not _ai_formation_ids.is_empty()
	):
		# Membership stable — keep existing formations
		return _ai_formation_ids.duplicate()

	_ai_dissolve_tracked()
	eligible.sort_custom(UnitFormationRole.compare_units_front_first)
	var chunks: Array = _split_into_chunks(eligible, size_preset)
	var created: Array[int] = []
	for chunk: Variant in chunks:
		var fid: int = _create_formation(chunk as Array, shape, size_preset, true, -1)
		created.append(fid)
		_ai_formation_ids.append(fid)

	_ai_last_signature = signature
	_ai_last_shape = int(shape)
	_ai_last_size = size_preset
	formations_changed.emit()
	return created


func ai_issue_move(
	units: Array,
	destination: Vector3,
	use_attack_move: bool,
	army_mode_name: StringName,
	defending: bool = false
) -> Array[Vector3]:
	## Returns per-unit targets aligned with the input units array order.
	ai_ensure_formations(units, army_mode_name, defending)

	var targets: Array[Vector3] = []
	targets.resize(units.size())

	var handled: Dictionary = {}
	for fid: int in _ai_formation_ids:
		var group: FormationGroup = get_formation(fid)
		if group == null:
			continue
		group.recompute_anchor_from_members()
		var from_center: Vector3 = group.anchor
		group.anchor = destination
		var face: Vector3 = destination - from_center
		face.y = 0.0
		if face.length_squared() >= 0.01:
			group.forward = face.normalized()
		elif use_attack_move:
			group.forward = Vector3(0.0, 0.0, 1.0)
		group.ensure_slots_assigned()

		for unit: Variant in group.get_alive_members():
			var unit_id: int = (unit as Node).get_instance_id()
			handled[unit_id] = group.get_world_slot_for_unit(unit as Node)

	var follow_group: FormationGroup = null
	if not _ai_formation_ids.is_empty():
		follow_group = get_formation(_ai_formation_ids[0])

	for i: int in units.size():
		var unit: Variant = units[i]
		if not NodeSafety.is_alive_node(unit):
			targets[i] = destination
			continue
		var unit_id: int = (unit as Node).get_instance_id()
		if unit is Hero:
			if follow_group != null:
				targets[i] = GroupMoveSpacing.resolve_formation_position(
					_hero_follow_world(unit as Hero, follow_group),
					destination
				)
			else:
				targets[i] = destination
			continue
		if handled.has(unit_id):
			targets[i] = GroupMoveSpacing.resolve_formation_position(
				handled[unit_id] as Vector3,
				destination
			)
		else:
			targets[i] = destination

	return targets


func get_selection_formation_summary(units: Array) -> Dictionary:
	var eligible: Array = collect_eligible_units(units, true)
	var formation_ids: Dictionary = {}
	var in_formation: int = 0
	for unit: Variant in eligible:
		var fid: int = get_unit_formation_id(unit as Node)
		if fid >= 0:
			in_formation += 1
			formation_ids[fid] = true

	var shape_name: String = String(FormationLayout.SHAPE_NAMES.get(player_shape, "Square"))
	var primary_shape: FormationLayout.Shape = player_shape
	var primary_size: int = player_size_preset
	if formation_ids.size() == 1:
		var only_id: int = int(formation_ids.keys()[0])
		var group: FormationGroup = get_formation(only_id)
		if group != null:
			primary_shape = group.shape
			primary_size = group.size_preset
			shape_name = String(FormationLayout.SHAPE_NAMES.get(group.shape, shape_name))

	return {
		"eligible_count": eligible.size(),
		"in_formation_count": in_formation,
		"formation_count": formation_ids.size(),
		"shape": primary_shape,
		"size_preset": primary_size,
		"shape_name": shape_name,
		"has_eligible": not eligible.is_empty(),
	}


func show_preview(group: FormationGroup) -> void:
	hide_preview()
	if group == null:
		return
	group.ensure_slots_assigned()
	_preview_root = Node3D.new()
	_preview_root.name = "FormationPreview"
	var tree := get_tree()
	if tree == null or tree.current_scene == null:
		_preview_root.free()
		_preview_root = null
		return
	tree.current_scene.add_child(_preview_root)

	var slots: Array[Vector3] = group.get_all_world_slots()
	for slot: Vector3 in slots:
		_preview_root.add_child(_make_slot_marker(slot, Color(0.85, 0.8, 0.45, 0.75)))

	# Footprint ring at anchor
	_preview_root.add_child(_make_ring_marker(group.anchor, 1.1, Color(0.7, 0.65, 0.35, 0.55)))
	# Front direction arrow
	var tip: Vector3 = group.anchor + group.forward * 2.4
	_preview_root.add_child(_make_arrow_marker(group.anchor, tip, Color(0.95, 0.75, 0.25, 0.9)))
	_preview_timer = PREVIEW_DURATION


func hide_preview() -> void:
	_preview_timer = 0.0
	if _preview_root != null and is_instance_valid(_preview_root):
		_preview_root.queue_free()
	_preview_root = null


func _create_formation(
	units: Array,
	shape: FormationLayout.Shape,
	size_preset: int,
	is_ai: bool,
	team_id: int
) -> int:
	var group := FormationGroup.new()
	group.formation_id = _next_formation_id
	_next_formation_id += 1
	group.shape = shape
	group.size_preset = size_preset
	group.is_ai = is_ai
	group.owner_team_id = team_id
	group.members = units.duplicate()
	group.needs_reassign = true
	group.recompute_anchor_from_members()
	# Default facing +Z world
	group.forward = Vector3(0.0, 0.0, 1.0)
	group.assign_roles_to_slots()

	_formations[group.formation_id] = group
	for unit: Variant in group.get_alive_members():
		_unit_to_formation[(unit as Node).get_instance_id()] = group.formation_id
		_watch_unit(unit as Node)

	return group.formation_id


func _split_into_chunks(units: Array, size_preset: int) -> Array:
	var chunks: Array = []
	if size_preset <= 0:
		chunks.append(units)
		return chunks
	var index: int = 0
	while index < units.size():
		var end: int = mini(index + size_preset, units.size())
		chunks.append(units.slice(index, end))
		index = end
	return chunks


func _remove_unit_from_any_formation(unit: Node) -> void:
	var fid: int = get_unit_formation_id(unit)
	if fid < 0:
		return
	_unbind_unit(unit)
	var group: FormationGroup = get_formation(fid)
	if group == null:
		return
	group.members.erase(unit)
	group.needs_reassign = true
	if group.member_count() <= 0:
		_formations.erase(fid)


func _unbind_unit(unit: Node) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	_unit_to_formation.erase(unit.get_instance_id())


func _watch_unit(unit: Node) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	if not unit.tree_exiting.is_connected(_on_unit_tree_exiting):
		unit.tree_exiting.connect(_on_unit_tree_exiting.bind(unit.get_instance_id()))


func _on_unit_tree_exiting(unit_id: int) -> void:
	var fid: int = int(_unit_to_formation.get(unit_id, -1))
	_unit_to_formation.erase(unit_id)
	if fid < 0:
		return
	var group: FormationGroup = get_formation(fid)
	if group == null:
		return
	group.purge_dead()
	if group.member_count() <= 0:
		_formations.erase(fid)
		formations_changed.emit()


func _purge_all_dead() -> void:
	var removed_any := false
	var empty_ids: Array[int] = []
	for fid: Variant in _formations.keys():
		var group: FormationGroup = _formations[fid] as FormationGroup
		if group == null:
			empty_ids.append(int(fid))
			continue
		if group.purge_dead():
			removed_any = true
		# Clean unit map for living
		for unit: Variant in group.get_alive_members():
			_unit_to_formation[(unit as Node).get_instance_id()] = int(fid)
		if group.member_count() <= 0:
			empty_ids.append(int(fid))
	for fid: int in empty_ids:
		_formations.erase(fid)
		removed_any = true
	if removed_any:
		formations_changed.emit()


func _ai_dissolve_tracked() -> void:
	for fid: int in _ai_formation_ids:
		dissolve_formation(fid)
	_ai_formation_ids.clear()


func _ai_membership_signature(units: Array, shape: FormationLayout.Shape, size_preset: int) -> String:
	var ids: Array[int] = []
	for unit: Variant in units:
		if NodeSafety.is_alive_node(unit):
			ids.append((unit as Node).get_instance_id())
	ids.sort()
	var parts: PackedStringArray = PackedStringArray()
	for id: int in ids:
		parts.append(str(id))
	return "%d:%d:%s" % [int(shape), size_preset, ",".join(parts)]


func _hero_follow_world(hero: Hero, group: FormationGroup) -> Vector3:
	var role: UnitFormationRole.Role = UnitFormationRole.get_role(hero)
	var spacing: float = FormationLayout.get_spacing_for_size(group.size_preset)
	var local: Vector3 = UnitFormationRole.hero_follow_offset(role, spacing)
	return FormationLayout.world_from_local(local, group.anchor, group.forward)


func _issue_unit_order(
	unit: Unit,
	target: Vector3,
	order_kind: StringName,
	queued: bool,
	slot_index: int
) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	match order_kind:
		&"attack_move":
			if unit.supports_combat_orders():
				unit.issue_order(UnitOrder.attack_move(target), queued)
			else:
				unit.issue_order(UnitOrder.move(target), queued)
		&"patrol":
			if unit.supports_patrol():
				unit.issue_order(UnitOrder.patrol([unit.global_position, target]), queued)
			else:
				unit.issue_order(UnitOrder.move(target), queued)
		&"retreat":
			unit.issue_order(UnitOrder.move(target), queued)
		_:
			unit.issue_order(UnitOrder.move(target), queued)


func _horizontal_distance(a: Vector3, b: Vector3) -> float:
	var dx: float = a.x - b.x
	var dz: float = a.z - b.z
	return sqrt(dx * dx + dz * dz)


func _make_slot_marker(pos: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.12
	mesh.height = 0.24
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = mat
	mi.position = Vector3(pos.x, PREVIEW_SLOT_Y, pos.z)
	return mi


func _make_ring_marker(pos: Vector3, radius: float, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := TorusMesh.new()
	mesh.inner_radius = radius * 0.85
	mesh.outer_radius = radius
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = mat
	mi.position = Vector3(pos.x, PREVIEW_SLOT_Y, pos.z)
	return mi


func _make_arrow_marker(from: Vector3, to: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	var length: float = _horizontal_distance(from, to)
	mesh.size = Vector3(0.15, 0.08, maxf(length, 0.5))
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = mat
	var mid: Vector3 = (from + to) * 0.5
	mi.position = Vector3(mid.x, PREVIEW_SLOT_Y, mid.z)
	var dir: Vector3 = to - from
	dir.y = 0.0
	if dir.length_squared() > 0.001:
		# Node is not in the tree yet — build basis without look_at().
		var forward_basis: Vector3 = dir.normalized()
		var right_basis: Vector3 = Vector3.UP.cross(forward_basis)
		if right_basis.length_squared() < 0.0001:
			right_basis = Vector3.RIGHT
		else:
			right_basis = right_basis.normalized()
		var up_basis: Vector3 = forward_basis.cross(right_basis).normalized()
		mi.basis = Basis(right_basis, up_basis, forward_basis)
	return mi
