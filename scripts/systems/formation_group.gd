class_name FormationGroup
extends RefCounted

## One formation instance with stable membership and cached slot assignments.

var formation_id: int = 0
var shape: FormationLayout.Shape = FormationLayout.Shape.SQUARE
var size_preset: int = 15
var spacing_class: FormationLayout.SpacingClass = FormationLayout.SpacingClass.STANDARD
var owner_team_id: int = 0
var is_ai: bool = false

var anchor: Vector3 = Vector3.ZERO
var forward: Vector3 = Vector3(0.0, 0.0, 1.0)
var members: Array = [] ## Unit nodes (weak via validity checks)
## unit_instance_id -> slot_index
var slot_by_unit_id: Dictionary = {}
## Parallel slot local offsets after assignment (same order as members after reorder)
var assigned_locals: Array[Vector3] = []
var layout_version: int = 0
var needs_reassign: bool = true
var last_order_signature: String = ""
var combat_reform_pending: bool = false
var stagger_cursor: int = 0


func get_alive_members() -> Array:
	var alive: Array = []
	for unit: Variant in members:
		if NodeSafety.is_alive_node(unit) and unit is Unit:
			alive.append(unit)
	return alive


func purge_dead() -> bool:
	var before: int = members.size()
	var alive: Array = get_alive_members()
	if alive.size() == before:
		return false
	members = alive
	# Drop stale slot mappings
	var valid_ids: Dictionary = {}
	for unit: Variant in members:
		valid_ids[(unit as Node).get_instance_id()] = true
	var stale_keys: Array = []
	for unit_id: Variant in slot_by_unit_id.keys():
		if not valid_ids.has(unit_id):
			stale_keys.append(unit_id)
	for key: Variant in stale_keys:
		slot_by_unit_id.erase(key)
	needs_reassign = true
	return true


func member_count() -> int:
	return get_alive_members().size()


func contains_unit(unit: Node) -> bool:
	if unit == null or not is_instance_valid(unit):
		return false
	return slot_by_unit_id.has(unit.get_instance_id())


func recompute_anchor_from_members() -> void:
	var alive: Array = get_alive_members()
	if alive.is_empty():
		return
	var sum := Vector3.ZERO
	for unit: Variant in alive:
		sum += (unit as Node3D).global_position
	anchor = sum / float(alive.size())


func set_facing_toward(world_point: Vector3) -> void:
	var dir: Vector3 = world_point - anchor
	dir.y = 0.0
	if dir.length_squared() < 0.01:
		return
	forward = dir.normalized()


func ensure_slots_assigned() -> void:
	if not needs_reassign and assigned_locals.size() == get_alive_members().size():
		return
	assign_roles_to_slots()


func assign_roles_to_slots() -> void:
	members = get_alive_members()
	slot_by_unit_id.clear()
	assigned_locals.clear()
	if members.is_empty():
		needs_reassign = false
		return

	var slot_count: int = maxi(size_preset, members.size())
	var slots: Array[Dictionary] = FormationLayout.get_or_build_slots(
		shape,
		size_preset,
		spacing_class
	)
	# If partial formation, take first N slots from layout (layout is size_preset based)
	# but rebuild for actual count when smaller than preset for tighter geometry.
	if members.size() < size_preset:
		slots = FormationLayout.get_or_build_slots(shape, _nearest_layout_size(members.size()), spacing_class)
		# Trim or pad to exact member count using nearest layout then slice
		if slots.size() > members.size():
			slots = slots.slice(0, members.size())
		elif slots.size() < members.size():
			# Fallback: expand with square extras
			var extra: Array[Dictionary] = FormationLayout.get_or_build_slots(
				FormationLayout.Shape.SQUARE,
				members.size(),
				spacing_class
			)
			while slots.size() < members.size() and slots.size() < extra.size():
				slots.append(extra[slots.size()])

	while slots.size() < members.size():
		var i: int = slots.size()
		slots.append({
			"local": Vector3(float(i % 5) * 1.5, 0.0, -float(i / 5) * 1.5),
			"band": FormationLayout.SlotBand.MIDDLE,
			"flank_bias": 0.0,
			"assigned": false,
		})

	var remaining: Array = members.duplicate()
	var assigned_units: Array = []
	assigned_units.resize(slots.size())
	for i: int in slots.size():
		assigned_units[i] = null

	# Pass order: siege -> ranged protected -> front -> flank cavalry -> fill
	_assign_band(
		slots,
		assigned_units,
		remaining,
		[FormationLayout.SlotBand.REAR_SIEGE],
		[UnitFormationRole.Role.SIEGE],
		true
	)
	_assign_band(
		slots,
		assigned_units,
		remaining,
		[FormationLayout.SlotBand.INNER_PROTECTED, FormationLayout.SlotBand.BACK],
		[UnitFormationRole.Role.ARCHER, UnitFormationRole.Role.CAVALRY_ARCHER],
		false
	)
	_assign_band(
		slots,
		assigned_units,
		remaining,
		[FormationLayout.SlotBand.FRONT],
		[UnitFormationRole.Role.PIKE, UnitFormationRole.Role.HEAVY_MELEE, UnitFormationRole.Role.HEAVY_CAVALRY, UnitFormationRole.Role.SWORDS],
		false
	)
	_assign_flank_cavalry(slots, assigned_units, remaining)
	_assign_band(
		slots,
		assigned_units,
		remaining,
		[FormationLayout.SlotBand.FLANK, FormationLayout.SlotBand.MIDDLE],
		[UnitFormationRole.Role.SWORDS, UnitFormationRole.Role.LIGHT_CAVALRY, UnitFormationRole.Role.HEAVY_MELEE],
		false
	)
	# Fill leftovers into any empty slot (never put siege/ranged into front if avoidable)
	_fill_remaining(slots, assigned_units, remaining)

	members.clear()
	assigned_locals.clear()
	for slot_index: int in assigned_units.size():
		var unit: Variant = assigned_units[slot_index]
		if unit == null:
			continue
		members.append(unit)
		slot_by_unit_id[(unit as Node).get_instance_id()] = slot_index
		assigned_locals.append(slots[slot_index]["local"] as Vector3)

	layout_version += 1
	needs_reassign = false


func get_world_slot_for_unit(unit: Node) -> Vector3:
	ensure_slots_assigned()
	if unit == null or not is_instance_valid(unit):
		return anchor
	var unit_id: int = unit.get_instance_id()
	if not slot_by_unit_id.has(unit_id):
		return anchor
	var slot_index: int = int(slot_by_unit_id[unit_id])
	# Find local by scanning members order
	var local_index: int = members.find(unit)
	if local_index < 0 or local_index >= assigned_locals.size():
		# Rebuild mapping from slot_index via layout
		var slots: Array[Dictionary] = FormationLayout.get_or_build_slots(shape, size_preset, spacing_class)
		if slot_index >= 0 and slot_index < slots.size():
			return FormationLayout.world_from_local(slots[slot_index]["local"] as Vector3, anchor, forward)
		return anchor
	return FormationLayout.world_from_local(assigned_locals[local_index], anchor, forward)


func get_all_world_slots() -> Array[Vector3]:
	ensure_slots_assigned()
	var result: Array[Vector3] = []
	for local: Vector3 in assigned_locals:
		result.append(FormationLayout.world_from_local(local, anchor, forward))
	return result


func _nearest_layout_size(count: int) -> int:
	# Use exact count for partial layouts — FormationLayout builders accept any count.
	return maxi(count, 1)


func _assign_band(
	slots: Array[Dictionary],
	assigned_units: Array,
	remaining: Array,
	bands: Array,
	preferred_roles: Array,
	siege_only: bool
) -> void:
	for slot_index: int in slots.size():
		if assigned_units[slot_index] != null:
			continue
		var band: int = int(slots[slot_index]["band"])
		if not bands.has(band):
			continue
		var pick_index: int = _find_best_unit(remaining, preferred_roles, siege_only, false)
		if pick_index < 0:
			continue
		assigned_units[slot_index] = remaining[pick_index]
		remaining.remove_at(pick_index)


func _assign_flank_cavalry(slots: Array[Dictionary], assigned_units: Array, remaining: Array) -> void:
	var flank_indices: Array[int] = []
	for slot_index: int in slots.size():
		if assigned_units[slot_index] != null:
			continue
		var band: int = int(slots[slot_index]["band"])
		if band == FormationLayout.SlotBand.FLANK or absf(float(slots[slot_index]["flank_bias"])) >= 0.85:
			flank_indices.append(slot_index)
	# Prefer extreme flanks first
	flank_indices.sort_custom(
		func(a: int, b: int) -> bool:
			return absf(float(slots[a]["flank_bias"])) > absf(float(slots[b]["flank_bias"]))
	)
	for slot_index: int in flank_indices:
		var pick_index: int = _find_best_unit(
			remaining,
			[UnitFormationRole.Role.LIGHT_CAVALRY, UnitFormationRole.Role.HEAVY_CAVALRY, UnitFormationRole.Role.CAVALRY_ARCHER],
			false,
			true
		)
		if pick_index < 0:
			break
		assigned_units[slot_index] = remaining[pick_index]
		remaining.remove_at(pick_index)


func _fill_remaining(slots: Array[Dictionary], assigned_units: Array, remaining: Array) -> void:
	# Sort remaining: melee first so they take front empties before ranged
	remaining.sort_custom(UnitFormationRole.compare_units_front_first)
	for slot_index: int in slots.size():
		if remaining.is_empty():
			return
		if assigned_units[slot_index] != null:
			continue
		var band: int = int(slots[slot_index]["band"])
		var pick_index: int = 0
		# Avoid placing ranged/siege on front if alternatives exist
		if band == FormationLayout.SlotBand.FRONT:
			for i: int in remaining.size():
				var role: UnitFormationRole.Role = UnitFormationRole.get_role(remaining[i] as Node)
				if UnitFormationRole.is_melee_role(role):
					pick_index = i
					break
		elif (
			band == FormationLayout.SlotBand.REAR_SIEGE
			or band == FormationLayout.SlotBand.BACK
			or band == FormationLayout.SlotBand.INNER_PROTECTED
		):
			for i: int in remaining.size():
				var role: UnitFormationRole.Role = UnitFormationRole.get_role(remaining[i] as Node)
				if UnitFormationRole.is_siege_role(role) or UnitFormationRole.is_ranged_role(role):
					pick_index = i
					break
		assigned_units[slot_index] = remaining[pick_index]
		remaining.remove_at(pick_index)

	# If slots were over-assigned nulls trimmed earlier, dump leftovers into rear-most locals
	while not remaining.is_empty():
		var unit: Variant = remaining.pop_front()
		var role: UnitFormationRole.Role = UnitFormationRole.get_role(unit as Node)
		var local := Vector3.ZERO
		if UnitFormationRole.is_siege_role(role) or UnitFormationRole.is_ranged_role(role):
			local = Vector3(0.0, 0.0, -1.6)
		else:
			local = Vector3(0.0, 0.0, 1.2)
		slots.append({
			"local": local,
			"band": FormationLayout.SlotBand.BACK,
			"flank_bias": 0.0,
			"assigned": false,
		})
		assigned_units.append(unit)


func _find_best_unit(
	remaining: Array,
	preferred_roles: Array,
	siege_only: bool,
	cavalry_preferred: bool
) -> int:
	var best_index: int = -1
	var best_score: int = 9999
	for i: int in remaining.size():
		var role: UnitFormationRole.Role = UnitFormationRole.get_role(remaining[i] as Node)
		if siege_only and not UnitFormationRole.is_siege_role(role):
			continue
		if cavalry_preferred and not UnitFormationRole.is_cavalry_role(role):
			# Allow non-cavalry only as last resort (handled by caller looping)
			pass
		var score: int = 100
		var role_index: int = preferred_roles.find(role)
		if role_index >= 0:
			score = role_index
		elif UnitFormationRole.is_melee_role(role) and not siege_only:
			score = 50 + UnitFormationRole.front_priority(role)
		else:
			score = 80 + UnitFormationRole.front_priority(role)
		if cavalry_preferred and UnitFormationRole.is_cavalry_role(role):
			score -= 20
		if score < best_score:
			best_score = score
			best_index = i
	if cavalry_preferred and best_index >= 0:
		var best_role: UnitFormationRole.Role = UnitFormationRole.get_role(remaining[best_index] as Node)
		if not UnitFormationRole.is_cavalry_role(best_role):
			return -1
	return best_index
