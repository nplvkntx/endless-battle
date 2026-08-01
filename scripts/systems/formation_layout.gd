class_name FormationLayout
extends RefCounted

## Cached local-space slot layouts keyed by shape, size, and spacing class.
## Layout space: +Z = forward (front), +X = right, Y unused.

enum Shape {
	SQUARE = 0,
	LINE = 1,
	ARROW = 2,
	HOLLOW_SQUARE = 3,
}

enum SpacingClass {
	TIGHT = 0,
	STANDARD = 1,
	WIDE = 2,
}

const SIZE_PRESETS: Array[int] = [5, 15, 30, 50]

const SHAPE_NAMES: Dictionary = {
	Shape.SQUARE: "Square",
	Shape.LINE: "Line",
	Shape.ARROW: "Arrow",
	Shape.HOLLOW_SQUARE: "Hollow Square",
}

const SHAPE_BEHAVIORS: Dictionary = {
	Shape.SQUARE: "Compact block. Melee on front/edges, ranged interior/rear, siege at rear.",
	Shape.LINE: "Wide front for volleys and defense. Melee front, archers behind.",
	Shape.ARROW: "Wedge for advancing and breaking lines. Tough tip, ranged rear-center.",
	Shape.HOLLOW_SQUARE: "Border ring with clear center. Melee on rim; protected inner-rear for ranged/siege.",
}

## Slot rank: 0 = front/outer priority, higher = rear/protected.
enum SlotBand {
	FRONT = 0,
	FLANK = 1,
	MIDDLE = 2,
	BACK = 3,
	REAR_SIEGE = 4,
	INNER_PROTECTED = 5,
}

static var _layout_cache: Dictionary = {}


static func clear_cache() -> void:
	_layout_cache.clear()


static func get_spacing_for_size(size_preset: int, spacing_class: SpacingClass = SpacingClass.STANDARD) -> float:
	var base: float = 1.55
	match size_preset:
		5:
			base = 1.35
		15:
			base = 1.55
		30:
			base = 1.7
		50:
			base = 1.85
		_:
			base = 1.55
	match spacing_class:
		SpacingClass.TIGHT:
			return base * 0.85
		SpacingClass.WIDE:
			return base * 1.2
		_:
			return base


static func get_or_build_slots(
	shape: Shape,
	size_preset: int,
	spacing_class: SpacingClass = SpacingClass.STANDARD
) -> Array[Dictionary]:
	var key: String = "%d_%d_%d" % [int(shape), size_preset, int(spacing_class)]
	if _layout_cache.has(key):
		return (_layout_cache[key] as Array).duplicate(true)

	var spacing: float = get_spacing_for_size(size_preset, spacing_class)
	var slots: Array[Dictionary] = []
	match shape:
		Shape.SQUARE:
			slots = _build_square(size_preset, spacing)
		Shape.LINE:
			slots = _build_line(size_preset, spacing)
		Shape.ARROW:
			slots = _build_arrow(size_preset, spacing)
		Shape.HOLLOW_SQUARE:
			slots = _build_hollow_square(size_preset, spacing)
		_:
			slots = _build_square(size_preset, spacing)

	_layout_cache[key] = slots
	return slots.duplicate(true)


static func supports_siege_slots(shape: Shape) -> bool:
	# All shapes expose rear/siege bands; hollow square also has inner-protected.
	return shape in [Shape.SQUARE, Shape.LINE, Shape.ARROW, Shape.HOLLOW_SQUARE]


static func world_from_local(
	local_offset: Vector3,
	anchor: Vector3,
	forward: Vector3
) -> Vector3:
	var fwd: Vector3 = forward
	fwd.y = 0.0
	if fwd.length_squared() < 0.0001:
		fwd = Vector3(0.0, 0.0, 1.0)
	else:
		fwd = fwd.normalized()
	var right: Vector3 = fwd.cross(Vector3.UP)
	if right.length_squared() < 0.0001:
		right = Vector3.RIGHT
	else:
		right = right.normalized()
	# Local: +Z forward, +X right
	var world: Vector3 = anchor + right * local_offset.x + fwd * local_offset.z
	world.y = anchor.y
	return world


static func _make_slot(local: Vector3, band: SlotBand, flank_bias: float = 0.0) -> Dictionary:
	return {
		"local": local,
		"band": band,
		"flank_bias": flank_bias, # -1 left, +1 right, 0 center
		"assigned": false,
	}


static func _build_square(count: int, spacing: float) -> Array[Dictionary]:
	var slots: Array[Dictionary] = []
	var columns: int = int(ceil(sqrt(float(count))))
	var rows: int = int(ceil(float(count) / float(columns)))
	var index: int = 0
	for row: int in range(rows):
		# row 0 = front (+Z)
		var depth_from_front: float = float(row)
		var z: float = (float(rows - 1) * 0.5 - depth_from_front) * spacing
		var band: SlotBand = SlotBand.FRONT
		if row == 0:
			band = SlotBand.FRONT
		elif row >= rows - 1:
			band = SlotBand.REAR_SIEGE if rows >= 3 else SlotBand.BACK
		elif row >= rows - 2 and rows >= 4:
			band = SlotBand.BACK
		else:
			band = SlotBand.MIDDLE

		var row_count: int = mini(columns, count - index)
		for col: int in range(row_count):
			var x: float = (float(col) - (float(row_count) - 1.0) * 0.5) * spacing
			var flank: float = 0.0
			if row_count > 1:
				flank = (float(col) / float(row_count - 1)) * 2.0 - 1.0
			# Outer columns prefer flank assignment for cavalry
			if col == 0 or col == row_count - 1:
				if band == SlotBand.MIDDLE or band == SlotBand.FRONT:
					band = SlotBand.FLANK if band != SlotBand.FRONT else SlotBand.FRONT
			slots.append(_make_slot(Vector3(x, 0.0, z), band, flank))
			index += 1
			if index >= count:
				break
		if index >= count:
			break
	return slots


static func _build_line(count: int, spacing: float) -> Array[Dictionary]:
	var slots: Array[Dictionary] = []
	# Prefer wide front with a protected rear row whenever practical.
	var rows: int = 1
	if count >= 4:
		rows = 2
	if count >= 28:
		rows = 3
	var columns: int = int(ceil(float(count) / float(rows)))
	var index: int = 0
	for row: int in range(rows):
		var z: float = (float(rows - 1) * 0.5 - float(row)) * spacing
		var band: SlotBand = SlotBand.FRONT
		if row == 0:
			band = SlotBand.FRONT
		elif row == rows - 1 and rows >= 3:
			band = SlotBand.REAR_SIEGE
		else:
			band = SlotBand.BACK

		var row_count: int = mini(columns, count - index)
		for col: int in range(row_count):
			var x: float = (float(col) - (float(row_count) - 1.0) * 0.5) * spacing
			var flank: float = 0.0
			if row_count > 1:
				flank = (float(col) / float(row_count - 1)) * 2.0 - 1.0
			var slot_band: SlotBand = band
			if band == SlotBand.FRONT and (col == 0 or col == row_count - 1):
				slot_band = SlotBand.FLANK
			# With only two rows, reserve center-back for siege.
			if band == SlotBand.BACK and rows == 2 and absf(flank) < 0.35:
				slot_band = SlotBand.REAR_SIEGE
			slots.append(_make_slot(Vector3(x, 0.0, z), slot_band, flank))
			index += 1
			if index >= count:
				break
		if index >= count:
			break
	return slots


static func _build_arrow(count: int, spacing: float) -> Array[Dictionary]:
	var slots: Array[Dictionary] = []
	# Build rows from tip (front) backward, widening each row.
	var remaining: int = count
	var row: int = 0
	while remaining > 0:
		var row_width: int = mini(remaining, 1 + row * 2)
		# Cap width growth for large armies
		if count >= 30:
			row_width = mini(remaining, 1 + row)
		var z: float = float(count) * 0.08 * spacing - float(row) * spacing
		# Recenter depth so tip is forward of centroid-ish
		z = -float(row) * spacing + spacing * 0.5
		var band: SlotBand = SlotBand.FRONT
		if row == 0:
			band = SlotBand.FRONT
		elif remaining - row_width <= maxi(1, count / 5):
			band = SlotBand.REAR_SIEGE if remaining - row_width <= maxi(1, count / 10) else SlotBand.BACK
		elif row <= 1:
			band = SlotBand.FLANK
		else:
			band = SlotBand.MIDDLE

		for col: int in range(row_width):
			var x: float = (float(col) - (float(row_width) - 1.0) * 0.5) * spacing
			var flank: float = 0.0
			if row_width > 1:
				flank = (float(col) / float(row_width - 1)) * 2.0 - 1.0
			var slot_band: SlotBand = band
			if row > 0 and (col == 0 or col == row_width - 1):
				slot_band = SlotBand.FLANK
			if row == 0:
				slot_band = SlotBand.FRONT
			slots.append(_make_slot(Vector3(x, 0.0, z), slot_band, flank))
		remaining -= row_width
		row += 1
		if row > 40:
			break

	# Shift so front tip is at +Z relative to formation center of slots
	if not slots.is_empty():
		var center := Vector3.ZERO
		for slot: Dictionary in slots:
			center += slot["local"] as Vector3
		center /= float(slots.size())
		for slot: Dictionary in slots:
			slot["local"] = (slot["local"] as Vector3) - center
	return slots


static func _build_hollow_square(count: int, spacing: float) -> Array[Dictionary]:
	var slots: Array[Dictionary] = []
	# Perimeter ring; leave center open. Optionally place a few inner-rear protected slots.
	var side: int = maxi(3, int(ceil(float(count + 4) / 4.0)) + 1)
	# Collect border positions clockwise starting front-left
	var border: Array[Vector3] = []
	# Front edge (+Z), left to right
	for i: int in range(side):
		var x: float = (float(i) - float(side - 1) * 0.5) * spacing
		var z: float = float(side - 1) * 0.5 * spacing
		border.append(Vector3(x, 0.0, z))
	# Right edge, front to back (skip front corner)
	for i: int in range(1, side):
		var x: float = float(side - 1) * 0.5 * spacing
		var z: float = (float(side - 1) * 0.5 - float(i)) * spacing
		border.append(Vector3(x, 0.0, z))
	# Back edge, right to left (skip right corner)
	for i: int in range(1, side):
		var x: float = (float(side - 1) * 0.5 - float(i)) * spacing
		var z: float = -float(side - 1) * 0.5 * spacing
		border.append(Vector3(x, 0.0, z))
	# Left edge, back to front (skip both corners)
	for i: int in range(1, side - 1):
		var x: float = -float(side - 1) * 0.5 * spacing
		var z: float = (-float(side - 1) * 0.5 + float(i)) * spacing
		border.append(Vector3(x, 0.0, z))

	var siege_budget: int = mini(maxi(1, count / 10), 4)
	var protected_budget: int = mini(maxi(0, count / 8), 3)
	var rim_count: int = count - siege_budget - protected_budget
	rim_count = maxi(rim_count, count - siege_budget)
	rim_count = mini(rim_count, border.size())

	# Sample evenly around border for rim slots
	for i: int in range(rim_count):
		var border_index: int = int(round(float(i) * float(border.size() - 1) / float(maxi(rim_count - 1, 1))))
		border_index = clampi(border_index, 0, border.size() - 1)
		var local: Vector3 = border[border_index]
		var band: SlotBand = SlotBand.FLANK
		var half: float = float(side - 1) * 0.5 * spacing
		if local.z >= half * 0.55:
			band = SlotBand.FRONT
		elif local.z <= -half * 0.55:
			band = SlotBand.BACK
		else:
			band = SlotBand.FLANK
		var flank: float = 0.0
		if half > 0.01:
			flank = clampf(local.x / half, -1.0, 1.0)
		slots.append(_make_slot(local, band, flank))

	# Inner-rear protected (slightly inside back edge, center clear)
	var placed_extra: int = slots.size()
	var extras_needed: int = count - placed_extra
	for i: int in range(extras_needed):
		var t: float = 0.0
		if extras_needed > 1:
			t = (float(i) / float(extras_needed - 1)) * 2.0 - 1.0
		var inner_z: float = -float(side - 1) * 0.5 * spacing + spacing * 0.85
		var local := Vector3(t * spacing * 1.1, 0.0, inner_z)
		var band: SlotBand = SlotBand.INNER_PROTECTED if i < protected_budget else SlotBand.REAR_SIEGE
		slots.append(_make_slot(local, band, t))

	return slots


static func choose_ai_shape(army_mode_name: StringName, has_siege: bool, defending: bool) -> Shape:
	if defending:
		if has_siege:
			return Shape.HOLLOW_SQUARE
		return Shape.LINE
	match String(army_mode_name):
		"ATTACKING", "ASSEMBLING":
			return Shape.ARROW
		"DEFENDING", "INTERCEPTING":
			return Shape.LINE if not has_siege else Shape.HOLLOW_SQUARE
		"RETREATING", "REGROUPING":
			return Shape.SQUARE
		_:
			return Shape.SQUARE


static func choose_ai_size(eligible_count: int) -> int:
	if eligible_count <= 0:
		return 5
	if eligible_count <= 8:
		return 5
	if eligible_count <= 22:
		return 15
	if eligible_count <= 40:
		return 30
	return 50
