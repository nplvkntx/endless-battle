extends Node

## Headless verification: one hero kit per faction for the whole match.
## Godot_v4.7-stable_win64.exe --headless --path <project> res://scenes/debug/verify_hero_choice_lock.tscn

const REPORT_PATH := "user://hero_choice_lock_verify_result.txt"
const HERO_ALTAR_SCENE: PackedScene = preload("res://scenes/buildings/hero_altar.tscn")
const HERO_SCENE: PackedScene = preload("res://scenes/units/hero.tscn")
const ENEMY_TEAM_ID: int = 1


func _ready() -> void:
	var failures: PackedStringArray = []
	HeroProgressionStore.clear()
	MatchSession._register_static_match_resets()

	_verify_unlocked_offers_all_kits(failures)
	_verify_lock_on_train_start_and_cancel(failures)
	_verify_duplicate_altar_shares_lock(failures)
	await _verify_rebuild_keeps_lock(failures)
	await _verify_retrain_uses_saved_progression(failures)
	await _verify_each_kit_can_lock(failures)
	await _verify_enemy_lock_independent(failures)
	_verify_match_reset_clears_lock(failures)

	var report: String
	if failures.is_empty():
		report = "PASS hero_choice_lock\n"
	else:
		report = "FAIL hero_choice_lock\n" + "\n".join(failures) + "\n"

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


func _fund_enemy() -> void:
	EnemyResourceManager.gold = 9999
	EnemyResourceManager.food_current = 0
	EnemyResourceManager.food_max = 99


func _make_player_altar(parent: Node, position: Vector3 = Vector3.ZERO) -> HeroAltar:
	var altar: HeroAltar = HERO_ALTAR_SCENE.instantiate() as HeroAltar
	parent.add_child(altar)
	altar.global_position = position
	altar.set_completed()
	return altar


func _make_enemy_altar(parent: Node, position: Vector3 = Vector3(20, 0, 0)) -> HeroAltar:
	var altar: HeroAltar = HERO_ALTAR_SCENE.instantiate() as HeroAltar
	altar.team_id = ENEMY_TEAM_ID
	altar.add_to_group(&"enemy_command_center")
	parent.add_child(altar)
	altar.global_position = position
	altar.set_completed()
	return altar


func _verify_unlocked_offers_all_kits(failures: PackedStringArray) -> void:
	HeroProgressionStore.clear()
	_expect(failures, "unlocked: no player lock", not HeroProgressionStore.has_locked_kit(false))
	_expect(
		failures,
		"unlocked: can select paladin",
		HeroProgressionStore.can_select_kit(false, HeroCatalog.KIT_PALADIN)
	)
	_expect(
		failures,
		"unlocked: can select assassin",
		HeroProgressionStore.can_select_kit(false, HeroCatalog.KIT_SHADOW_ASSASSIN)
	)
	_expect(
		failures,
		"unlocked: can select ranger",
		HeroProgressionStore.can_select_kit(false, HeroCatalog.KIT_RANGER)
	)


func _verify_lock_on_train_start_and_cancel(failures: PackedStringArray) -> void:
	HeroProgressionStore.clear()
	_fund_player()
	var root := Node3D.new()
	add_child(root)

	var altar: HeroAltar = _make_player_altar(root)
	altar.set_selected_kit(HeroCatalog.KIT_PALADIN)
	altar.try_train_hero()

	_expect(failures, "train start: is training", altar.is_training_hero())
	_expect(
		failures,
		"train start: locked to paladin",
		HeroProgressionStore.get_locked_kit_id(false) == HeroCatalog.KIT_PALADIN
	)
	_expect(
		failures,
		"train start: cannot select assassin",
		not HeroProgressionStore.can_select_kit(false, HeroCatalog.KIT_SHADOW_ASSASSIN)
	)
	_expect(
		failures,
		"train start: altar offers only paladin",
		altar.can_offer_kit(HeroCatalog.KIT_PALADIN) and not altar.can_offer_kit(HeroCatalog.KIT_RANGER)
	)

	var cancelled: bool = altar.cancel_hero_training()
	_expect(failures, "cancel: succeeded", cancelled)
	_expect(failures, "cancel: not training", not altar.is_training_hero())
	_expect(
		failures,
		"cancel: lock remains paladin",
		HeroProgressionStore.get_locked_kit_id(false) == HeroCatalog.KIT_PALADIN
	)

	altar.set_selected_kit(HeroCatalog.KIT_SHADOW_ASSASSIN)
	_expect(
		failures,
		"cancel: set_selected_kit cannot swap",
		altar.get_selected_kit() == HeroCatalog.KIT_PALADIN
	)
	_expect(
		failures,
		"cancel: pending kit stays paladin",
		altar.get_pending_training_kit_id(false) == HeroCatalog.KIT_PALADIN
	)

	root.queue_free()


func _verify_duplicate_altar_shares_lock(failures: PackedStringArray) -> void:
	HeroProgressionStore.clear()
	_fund_player()
	var root := Node3D.new()
	add_child(root)

	var altar_a: HeroAltar = _make_player_altar(root, Vector3(0, 0, 0))
	var altar_b: HeroAltar = _make_player_altar(root, Vector3(8, 0, 0))
	altar_a.set_selected_kit(HeroCatalog.KIT_RANGER)
	altar_a.try_train_hero()

	_expect(
		failures,
		"dual altar: faction locked ranger",
		HeroProgressionStore.get_locked_kit_id(false) == HeroCatalog.KIT_RANGER
	)
	_expect(
		failures,
		"dual altar: B pending is ranger",
		altar_b.get_pending_training_kit_id(false) == HeroCatalog.KIT_RANGER
	)
	_expect(
		failures,
		"dual altar: B cannot offer assassin",
		not altar_b.can_offer_kit(HeroCatalog.KIT_SHADOW_ASSASSIN)
	)

	altar_b.set_selected_kit(HeroCatalog.KIT_PALADIN)
	_expect(
		failures,
		"dual altar: B selection forced to ranger",
		altar_b.get_selected_kit() == HeroCatalog.KIT_RANGER
	)

	## Second altar must not start a different kit while first is training / hero living.
	altar_a.cancel_hero_training()
	altar_b.set_selected_kit(HeroCatalog.KIT_PALADIN)
	altar_b.try_train_hero()
	_expect(
		failures,
		"dual altar: B trains locked ranger kit",
		altar_b.is_training_hero()
		and altar_b.get_active_unit_training_name() == HeroCatalog.get_display_name(HeroCatalog.KIT_RANGER)
	)

	root.queue_free()


func _verify_rebuild_keeps_lock(failures: PackedStringArray) -> void:
	HeroProgressionStore.clear()
	_fund_player()
	var root := Node3D.new()
	add_child(root)

	var altar: HeroAltar = _make_player_altar(root)
	altar.set_selected_kit(HeroCatalog.KIT_SHADOW_ASSASSIN)
	altar.try_train_hero()
	altar.cancel_hero_training()
	altar.queue_free()
	await get_tree().process_frame

	var rebuilt: HeroAltar = _make_player_altar(root, Vector3(4, 0, 0))
	_expect(
		failures,
		"rebuild: lock still assassin",
		HeroProgressionStore.get_locked_kit_id(false) == HeroCatalog.KIT_SHADOW_ASSASSIN
	)
	_expect(
		failures,
		"rebuild: pending is assassin",
		rebuilt.get_pending_training_kit_id(false) == HeroCatalog.KIT_SHADOW_ASSASSIN
	)
	_expect(
		failures,
		"rebuild: cannot offer paladin",
		not rebuilt.can_offer_kit(HeroCatalog.KIT_PALADIN)
	)

	root.queue_free()


func _verify_retrain_uses_saved_progression(failures: PackedStringArray) -> void:
	HeroProgressionStore.clear()
	_fund_player()
	var root := Node3D.new()
	add_child(root)

	var hero: Hero = HERO_SCENE.instantiate() as Hero
	root.add_child(hero)
	hero.level = 7
	HeroProgressionStore.save_from_hero(hero)
	hero.queue_free()
	await get_tree().process_frame

	_expect(
		failures,
		"death save: locked paladin",
		HeroProgressionStore.get_locked_kit_id(false) == HeroCatalog.KIT_PALADIN
	)
	_expect(failures, "death save: has progression", HeroProgressionStore.has_saved_progression())
	_expect(failures, "death save: level 7", HeroProgressionStore.get_saved_level(false) == 7)

	var altar: HeroAltar = _make_player_altar(root)
	_expect(
		failures,
		"retrain: pending paladin",
		altar.get_pending_training_kit_id(false) == HeroCatalog.KIT_PALADIN
	)

	root.queue_free()
	await get_tree().process_frame


func _verify_each_kit_can_lock(failures: PackedStringArray) -> void:
	for kit_id: StringName in HeroCatalog.KIT_ORDER:
		HeroProgressionStore.clear()
		_fund_player()
		## Clear any leftover living heroes from prior cases.
		for node: Node in get_tree().get_nodes_in_group(&"heroes"):
			if is_instance_valid(node):
				node.queue_free()
		await get_tree().process_frame

		var root := Node3D.new()
		add_child(root)
		var altar: HeroAltar = _make_player_altar(root)
		altar.set_selected_kit(kit_id)
		altar.try_train_hero()
		_expect(
			failures,
			"kit lock: %s (locked=%s training=%s)" % [
				String(kit_id),
				String(HeroProgressionStore.get_locked_kit_id(false)),
				str(altar.is_training_hero()),
			],
			HeroProgressionStore.get_locked_kit_id(false) == kit_id and altar.is_training_hero()
		)
		altar.cancel_hero_training()
		root.queue_free()
		await get_tree().process_frame


func _verify_enemy_lock_independent(failures: PackedStringArray) -> void:
	HeroProgressionStore.clear()
	_fund_player()
	_fund_enemy()
	for node: Node in get_tree().get_nodes_in_group(&"heroes"):
		if is_instance_valid(node):
			node.queue_free()
	await get_tree().process_frame

	var root := Node3D.new()
	add_child(root)

	var player_altar: HeroAltar = _make_player_altar(root, Vector3(0, 0, 0))
	var enemy_altar: HeroAltar = _make_enemy_altar(root, Vector3(20, 0, 0))

	player_altar.set_selected_kit(HeroCatalog.KIT_RANGER)
	player_altar.try_train_hero()
	_expect(
		failures,
		"enemy: player locked ranger (locked=%s training=%s)" % [
			String(HeroProgressionStore.get_locked_kit_id(false)),
			str(player_altar.is_training_hero()),
		],
		HeroProgressionStore.get_locked_kit_id(false) == HeroCatalog.KIT_RANGER
	)
	_expect(
		failures,
		"enemy: enemy unlocked before train",
		not HeroProgressionStore.has_locked_kit(true)
	)

	var trained: bool = enemy_altar.try_train_enemy_hero()
	_expect(failures, "enemy: train started", trained)
	_expect(
		failures,
		"enemy: locked to default assassin",
		HeroProgressionStore.get_locked_kit_id(true) == HeroCatalog.KIT_SHADOW_ASSASSIN
	)
	_expect(
		failures,
		"enemy: player lock unchanged",
		HeroProgressionStore.get_locked_kit_id(false) == HeroCatalog.KIT_RANGER
	)
	_expect(
		failures,
		"enemy: pending kit assassin",
		enemy_altar.get_pending_training_kit_id(true) == HeroCatalog.KIT_SHADOW_ASSASSIN
	)

	root.queue_free()
	await get_tree().process_frame


func _verify_match_reset_clears_lock(failures: PackedStringArray) -> void:
	HeroProgressionStore.lock_kit(false, HeroCatalog.KIT_PALADIN)
	HeroProgressionStore.lock_kit(true, HeroCatalog.KIT_RANGER)
	HeroProgressionStore._player_snapshot = {"level": 3, "hero_kit_id": "paladin"}
	MatchSession.prepare_new_match()

	_expect(failures, "reset: player lock cleared", not HeroProgressionStore.has_locked_kit(false))
	_expect(failures, "reset: enemy lock cleared", not HeroProgressionStore.has_locked_kit(true))
	_expect(failures, "reset: player snapshot cleared", not HeroProgressionStore.has_saved_progression())
	_expect(failures, "reset: living heroes cleared", not HeroProgressionStore.has_living_hero(false) and not HeroProgressionStore.has_living_hero(true))
	_expect(
		failures,
		"reset: all kits selectable again",
		HeroProgressionStore.can_select_kit(false, HeroCatalog.KIT_PALADIN)
		and HeroProgressionStore.can_select_kit(false, HeroCatalog.KIT_SHADOW_ASSASSIN)
		and HeroProgressionStore.can_select_kit(false, HeroCatalog.KIT_RANGER)
	)
