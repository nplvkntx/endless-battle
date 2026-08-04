extends Node

## Reproduces Hero Altar UI refresh after hero death without freed-instance assignment.
## Godot_v4.7-stable_win64.exe --headless --path <project> res://scenes/debug/verify_hero_altar_freed_instance.tscn

const REPORT_PATH := "user://hero_altar_freed_instance_verify_result.txt"
const HERO_ALTAR_SCENE: PackedScene = preload("res://scenes/buildings/hero_altar.tscn")
const HERO_SCENE: PackedScene = preload("res://scenes/units/hero.tscn")
const ASSASSIN_SCENE: PackedScene = preload("res://scenes/units/shadow_assassin.tscn")
const RANGER_SCENE: PackedScene = preload("res://scenes/units/ranger.tscn")
const SELECTION_MANAGER_SCRIPT: Script = preload("res://scripts/systems/selection_manager.gd")


func _ready() -> void:
	var failures: PackedStringArray = []
	HeroProgressionStore.clear()
	MatchSession._register_static_match_resets()

	await _verify_altar_select_after_hero_death(failures)
	await _verify_registry_clears_on_death(failures)
	await _verify_typed_assign_guard(failures)
	await _verify_retrain_same_kit_only(failures)
	_verify_match_reset_clears_living(failures)

	var report: String
	if failures.is_empty():
		report = "PASS hero_altar_freed_instance\n"
	else:
		report = "FAIL hero_altar_freed_instance\n" + "\n".join(failures) + "\n"

	var file := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(report)
		file.close()

	print(report)
	await get_tree().process_frame
	get_tree().quit(0 if failures.is_empty() else 1)


func _expect(failures: PackedStringArray, label: String, ok: bool) -> void:
	if not ok:
		failures.append("- " + label)


func _fund_player() -> void:
	ResourceManager.gold = 9999
	ResourceManager.food_current = 0
	ResourceManager.food_max = 99


func _make_altar(parent: Node) -> HeroAltar:
	var altar: HeroAltar = HERO_ALTAR_SCENE.instantiate() as HeroAltar
	parent.add_child(altar)
	altar.set_completed()
	return altar


func _spawn_kit(parent: Node, scene: PackedScene) -> Hero:
	var hero: Hero = scene.instantiate() as Hero
	parent.add_child(hero)
	HeroProgressionStore.register_living_hero(hero)
	return hero


func _kill_hero(hero: Hero) -> void:
	if hero == null or not is_instance_valid(hero):
		return
	hero._on_health_depleted()


func _verify_altar_select_after_hero_death(failures: PackedStringArray) -> void:
	HeroProgressionStore.clear()
	_fund_player()
	var root := Node3D.new()
	add_child(root)

	var altar: HeroAltar = _make_altar(root)
	var hero: Hero = _spawn_kit(root, HERO_SCENE)
	HeroProgressionStore.lock_kit(false, HeroCatalog.KIT_PALADIN)

	var selection: Node = SELECTION_MANAGER_SCRIPT.new()
	add_child(selection)
	selection.call("_set_selected_units", [hero] as Array[Unit])
	await get_tree().process_frame

	_kill_hero(hero)
	await get_tree().process_frame
	await get_tree().process_frame

	_expect(failures, "living hero cleared after death", not HeroProgressionStore.has_living_hero(false))
	_expect(failures, "kit lock survives death", HeroProgressionStore.get_locked_kit_id(false) == HeroCatalog.KIT_PALADIN)

	## Selecting the altar must not assign the freed hero into typed Hero fields.
	selection.call("_set_selected_building", altar)
	await get_tree().process_frame

	_expect(failures, "altar selectable after death", selection.get("selected_building") == altar)
	_expect(failures, "no living hero after altar select", not HeroProgressionStore.has_living_hero(false))
	_expect(
		failures,
		"can retrain after death",
		altar.can_train_hero()
	)
	_expect(
		failures,
		"only locked kit offered",
		altar.can_offer_kit(HeroCatalog.KIT_PALADIN)
		and not altar.can_offer_kit(HeroCatalog.KIT_SHADOW_ASSASSIN)
		and not altar.can_offer_kit(HeroCatalog.KIT_RANGER)
	)

	## Simulate command-panel refresh path used when altar is selected.
	var primary: Hero = HeroProgressionStore.as_living_hero(selection.call("get_primary_ui_hero"))
	_expect(failures, "primary ui hero null after death", primary == null)
	var living: Hero = HeroProgressionStore.get_living_hero(false)
	_expect(failures, "registry living null", living == null)

	selection.queue_free()
	root.queue_free()
	await get_tree().process_frame


func _verify_registry_clears_on_death(failures: PackedStringArray) -> void:
	HeroProgressionStore.clear()
	var root := Node3D.new()
	add_child(root)

	for kit_scene: PackedScene in [HERO_SCENE, ASSASSIN_SCENE, RANGER_SCENE]:
		HeroProgressionStore.clear()
		var hero: Hero = _spawn_kit(root, kit_scene)
		_expect(failures, "registered living", HeroProgressionStore.has_living_hero(false))
		_kill_hero(hero)
		await get_tree().process_frame
		await get_tree().process_frame
		_expect(failures, "cleared after kill", not HeroProgressionStore.has_living_hero(false))

	root.queue_free()
	await get_tree().process_frame


func _verify_typed_assign_guard(failures: PackedStringArray) -> void:
	HeroProgressionStore.clear()
	var root := Node3D.new()
	add_child(root)
	var hero: Hero = _spawn_kit(root, HERO_SCENE)
	var dangling: Variant = hero
	_kill_hero(hero)
	await get_tree().process_frame
	await get_tree().process_frame

	var safe: Hero = HeroProgressionStore.as_living_hero(dangling)
	_expect(failures, "as_living_hero rejects freed", safe == null)

	## Mimic the old crash: assigning freed into typed Hero must be avoided.
	var assigned: Hero = null
	if NodeSafety.is_alive_node(dangling) and dangling is Hero:
		assigned = dangling as Hero
	_expect(failures, "guarded assign stays null", assigned == null)

	root.queue_free()
	await get_tree().process_frame


func _verify_retrain_same_kit_only(failures: PackedStringArray) -> void:
	HeroProgressionStore.clear()
	_fund_player()
	var root := Node3D.new()
	add_child(root)
	var altar: HeroAltar = _make_altar(root)
	var hero: Hero = _spawn_kit(root, ASSASSIN_SCENE)
	HeroProgressionStore.lock_kit(false, HeroCatalog.KIT_SHADOW_ASSASSIN)
	_kill_hero(hero)
	await get_tree().process_frame
	await get_tree().process_frame

	altar.set_selected_kit(HeroCatalog.KIT_PALADIN)
	_expect(
		failures,
		"cannot switch kit after death",
		altar.get_selected_kit() == HeroCatalog.KIT_SHADOW_ASSASSIN
	)
	_expect(failures, "retrain allowed", altar.can_train_hero())
	altar.try_train_hero()
	_expect(failures, "retrain started", altar.is_training_hero())
	_expect(
		failures,
		"pending kit stays assassin",
		altar.get_pending_training_kit_id(false) == HeroCatalog.KIT_SHADOW_ASSASSIN
	)

	root.queue_free()
	await get_tree().process_frame


func _verify_match_reset_clears_living(failures: PackedStringArray) -> void:
	HeroProgressionStore.clear()
	HeroProgressionStore.lock_kit(false, HeroCatalog.KIT_RANGER)
	HeroProgressionStore._player_living_hero_handle = EntityHandle.from_instance_id(
		12345,
		EntityHandle.Category.HERO
	)
	HeroProgressionStore.clear()
	_expect(failures, "reset clears lock", not HeroProgressionStore.has_locked_kit(false))
	_expect(failures, "reset clears living id", not HeroProgressionStore.has_living_hero(false))
	_expect(
		failures,
		"reset clears living handle",
		HeroProgressionStore.get_living_hero_handle(false).is_empty()
	)
