class_name ConstructionStageCatalog
extends RefCounted

## Default construction stage models keyed by building type.
## Artists can override per-instance via Building.construction_stages.

const _FARM_DIRT := "res://assets/art/quaternius/buildings/farm_candidates/Farm_Dirt_Level1.gltf"
const _FARM_L1 := "res://assets/art/quaternius/buildings/farm_candidates/Farm_SecondAge_Level1_Wheat.gltf"
const _FARM_L2 := "res://assets/art/quaternius/buildings/farm_candidates/Farm_SecondAge_Level2_Wheat.gltf"
const _FARM_L3 := "res://assets/art/quaternius/buildings/farm_candidates/Farm_SecondAge_Level3_Wheat.gltf"

const _BARRACKS_L1 := "res://assets/art/quaternius/buildings/barracks_candidates/Barracks_SecondAge_Level1.gltf"
const _BARRACKS_L2 := "res://assets/art/quaternius/buildings/barracks_candidates/Barracks_SecondAge_Level2.gltf"
const _BARRACKS_L3 := "res://assets/art/quaternius/buildings/barracks_candidates/Barracks_SecondAge_Level3.gltf"

const _ARCHERY_L1 := "res://assets/art/quaternius/buildings/blacksmith_archery_candidates/Archery_SecondAge_Level1.gltf"
const _ARCHERY_L2 := "res://assets/art/quaternius/buildings/blacksmith_archery_candidates/Archery_SecondAge_Level2.gltf"
const _ARCHERY_L3 := "res://assets/art/quaternius/buildings/blacksmith_archery_candidates/Archery_SecondAge_Level3.gltf"

const _MARKET_L1 := "res://assets/art/quaternius/buildings/shop_market_candidates/Market_SecondAge_Level1.gltf"
const _MARKET_L2 := "res://assets/art/quaternius/buildings/shop_market_candidates/Market_SecondAge_Level2.gltf"
const _MARKET_L3 := "res://assets/art/quaternius/buildings/shop_market_candidates/Market_SecondAge_Level3.gltf"

const _TOWER_L1 := "res://assets/art/quaternius/buildings/tower_candidates/WatchTower_SecondAge_Level1.gltf"
const _TOWER_L2 := "res://assets/art/quaternius/buildings/tower_candidates/WatchTower_SecondAge_Level2.gltf"
const _TOWER_L3 := "res://assets/art/quaternius/buildings/tower_candidates/WatchTower_SecondAge_Level3.gltf"

const _TEMPLE_L1 := "res://assets/art/quaternius/buildings/hero_altar_temple_candidates/Temple_SecondAge_Level1.gltf"
const _TEMPLE_L2 := "res://assets/art/quaternius/buildings/hero_altar_temple_candidates/Temple_SecondAge_Level2.gltf"
const _TEMPLE_L3 := "res://assets/art/quaternius/buildings/hero_altar_temple_candidates/Temple_SecondAge_Level3.gltf"

const _TOWN_L1 := "res://assets/art/quaternius/buildings/town_center_candidates/TownCenter_SecondAge_Level1.gltf"
const _TOWN_L2 := "res://assets/art/quaternius/buildings/town_center_candidates/TownCenter_SecondAge_Level2.gltf"
const _TOWN_L3 := "res://assets/art/quaternius/buildings/town_center_candidates/TownCenter_SecondAge_Level3.gltf"

const _STABLE_L1 := "res://assets/art/quaternius/buildings/farm_candidates/Farm_FirstAge_Level1.gltf"
const _STABLE_L2 := "res://assets/art/quaternius/buildings/farm_candidates/Farm_FirstAge_Level2.gltf"
const _STABLE_L3 := "res://assets/art/quaternius/buildings/farm_candidates/Farm_FirstAge_Level3.gltf"


static func resolve_for_building(building: Node) -> ConstructionStageSet:
	if building == null:
		return ConstructionStageSet.new()

	var building_type: StringName = _resolve_building_type(building)
	return create_default_for_type(building_type)


static func create_default_for_type(building_type: StringName) -> ConstructionStageSet:
	var stage_set := ConstructionStageSet.new()
	match building_type:
		&"farm":
			_fill(stage_set, [_FARM_DIRT, _FARM_L1, _FARM_L2, _FARM_L3], _farm_transform())
		&"barracks":
			_fill(stage_set, [_BARRACKS_L1, _BARRACKS_L1, _BARRACKS_L2, _BARRACKS_L3], _barracks_transform())
		&"blacksmith":
			_fill(stage_set, [_ARCHERY_L1, _ARCHERY_L1, _ARCHERY_L2, _ARCHERY_L3], _blacksmith_transform())
		&"shop":
			_fill(stage_set, [_MARKET_L1, _MARKET_L1, _MARKET_L2, _MARKET_L3], _shop_transform())
		&"tower":
			_fill(stage_set, [_TOWER_L1, _TOWER_L1, _TOWER_L2, _TOWER_L3], _tower_transform())
		&"command_center":
			_fill(stage_set, [_TEMPLE_L1, _TEMPLE_L1, _TEMPLE_L2, _TEMPLE_L3], _command_center_transform())
		&"hero_altar":
			_fill(stage_set, [_TOWN_L1, _TOWN_L1, _TOWN_L2, _TOWN_L3], _hero_altar_transform())
		&"stable":
			_fill(stage_set, [_STABLE_L1, _STABLE_L1, _STABLE_L2, _STABLE_L3], _stable_transform())
		_:
			# academy, artillery_depot, wall_segment, unknown → reveal/placeholder mode
			pass
	return stage_set


static func _resolve_building_type(building: Node) -> StringName:
	if building is Farm:
		return &"farm"
	if building is Barracks:
		return &"barracks"
	if building is Blacksmith:
		return &"blacksmith"
	if building is Shop:
		return &"shop"
	if building is Tower:
		return &"tower"
	if building is CommandCenter:
		return &"command_center"
	if building is HeroAltar:
		return &"hero_altar"
	if building is Stable:
		return &"stable"
	if building is Academy:
		return &"academy"
	if building is ArtilleryDepot:
		return &"artillery_depot"
	if building is WallSegment:
		return &"wall_segment"

	var script: Script = building.get_script() as Script
	if script != null:
		var path: String = script.resource_path.get_file().get_basename()
		if not path.is_empty():
			return StringName(path)

	return StringName(String(building.name).to_snake_case())


static func _fill(
	stage_set: ConstructionStageSet,
	paths: Array,
	model_transform: Transform3D
) -> void:
	stage_set.stage_model_transform = model_transform
	for stage_index: int in mini(paths.size(), 4):
		var path: String = str(paths[stage_index])
		if path.is_empty() or not ResourceLoader.exists(path):
			continue
		var packed: PackedScene = load(path) as PackedScene
		if packed != null:
			stage_set.set_stage_scene(stage_index, packed)


static func _farm_transform() -> Transform3D:
	return Transform3D(
		Vector3(-1.35, 0.0, 0.0),
		Vector3(0.0, 1.35, 0.0),
		Vector3(0.0, 0.0, -1.35),
		Vector3(0.0, -0.5, 0.0)
	)


static func _barracks_transform() -> Transform3D:
	return Transform3D(
		Vector3(-2.0, 0.0, 0.0),
		Vector3(0.0, 2.0, 0.0),
		Vector3(0.0, 0.0, -2.0),
		Vector3(0.0, -0.75, 0.0)
	)


static func _blacksmith_transform() -> Transform3D:
	return Transform3D(
		Vector3(-2.0, 0.0, 0.0),
		Vector3(0.0, 2.0, 0.0),
		Vector3(0.0, 0.0, -2.0),
		Vector3(0.0, -0.8, 0.0)
	)


static func _shop_transform() -> Transform3D:
	return Transform3D(
		Vector3(-2.0, 0.0, 0.0),
		Vector3(0.0, 2.0, 0.0),
		Vector3(0.0, 0.0, -2.0),
		Vector3(0.0, -0.7, 0.0)
	)


static func _tower_transform() -> Transform3D:
	return Transform3D(
		Vector3(-2.5, 0.0, 0.0),
		Vector3(0.0, 2.5, 0.0),
		Vector3(0.0, 0.0, -2.5),
		Vector3(0.0, -1.5, 0.0)
	)


static func _command_center_transform() -> Transform3D:
	return Transform3D(
		Vector3(-2.0, 0.0, 0.0),
		Vector3(0.0, 2.0, 0.0),
		Vector3(0.0, 0.0, -2.0),
		Vector3(0.0, -1.0, 0.0)
	)


static func _hero_altar_transform() -> Transform3D:
	return Transform3D(
		Vector3(-2.5, 0.0, 0.0),
		Vector3(0.0, 2.5, 0.0),
		Vector3(0.0, 0.0, -2.5),
		Vector3(0.0, -0.98, 0.0)
	)


static func _stable_transform() -> Transform3D:
	return Transform3D(
		Vector3(-2.0, 0.0, 0.0),
		Vector3(0.0, 2.0, 0.0),
		Vector3(0.0, 0.0, -2.0),
		Vector3(0.0, -0.7, 0.0)
	)
