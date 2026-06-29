class_name GroupMoveSpacing

## Computes simple offset targets around a move command point for grouped units.

const DEFAULT_SPACING: float = 1.5


static func compute_targets(center: Vector3, unit_count: int, spacing: float = DEFAULT_SPACING) -> Array[Vector3]:
	if unit_count <= 1:
		return [center]

	var targets: Array[Vector3] = []
	var columns: int = int(ceil(sqrt(float(unit_count))))
	var rows: int = int(ceil(float(unit_count) / float(columns)))

	var index: int = 0
	for row: int in range(rows):
		for column: int in range(columns):
			if index >= unit_count:
				break

			var offset_x: float = (float(column) - (float(columns) - 1.0) * 0.5) * spacing
			var offset_z: float = (float(row) - (float(rows) - 1.0) * 0.5) * spacing
			targets.append(Vector3(center.x + offset_x, center.y, center.z + offset_z))
			index += 1

	return targets
