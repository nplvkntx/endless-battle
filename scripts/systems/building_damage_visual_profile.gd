class_name BuildingDamageVisualProfile
extends Resource

## Tunable building damage FX thresholds and intensities.
## Assign on a Building via damage_visual_profile for per-building overrides.

@export_group("HP Thresholds")
## HP ratio at or below which minor smoke appears.
@export_range(0.01, 1.0, 0.01) var minor_smoke_ratio: float = 0.75
## HP ratio at or below which smoke becomes denser.
@export_range(0.01, 1.0, 0.01) var noticeable_smoke_ratio: float = 0.5
## HP ratio at or below which fire is added.
@export_range(0.01, 1.0, 0.01) var smoke_and_fire_ratio: float = 0.25
## HP ratio at or below which fire intensifies.
@export_range(0.01, 1.0, 0.01) var heavy_fire_ratio: float = 0.1

@export_group("Placement")
## Extra local Y on top of estimated mesh roof height.
@export var height_padding: float = 0.15
## Multiplies footprint-based emitter spread (1 = default).
@export_range(0.25, 3.0, 0.05) var footprint_spread_scale: float = 1.0
## Optional local offset from building origin (after height estimate).
@export var local_offset: Vector3 = Vector3.ZERO

@export_group("Intensity")
@export_range(0.1, 3.0, 0.05) var smoke_intensity_scale: float = 1.0
@export_range(0.1, 3.0, 0.05) var fire_intensity_scale: float = 1.0
## Seconds to fade emitters when repairing upward through states.
@export_range(0.05, 3.0, 0.05) var repair_fade_seconds: float = 0.65


static func default_profile() -> BuildingDamageVisualProfile:
	return BuildingDamageVisualProfile.new()
