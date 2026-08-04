extends Node

## Headless verification for Ranger close-range attacks, Hunter's Precision feedback,
## and universal idle auto-acquisition.
## Godot_v4.7-stable_win64.exe --headless --path <project> res://scenes/debug/verify_ranger_combat_auto_acquire.tscn

const RANGER_SCENE: PackedScene = preload("res://scenes/units/ranger.tscn")
const SWORDSMAN_SCENE: PackedScene = preload("res://scenes/units/swordsman.tscn")
const ENEMY_DUMMY_SCENE: PackedScene = preload("res://scenes/units/enemy_dummy.tscn")


func _ready() -> void:
	var failures: PackedStringArray = PackedStringArray()
	await _verify_ranger_attacks_all_ranges(failures)
	await _verify_ranger_no_preferred_kite(failures)
	await _verify_passive_stack_and_timeout(failures)
	await _verify_idle_auto_acquire(failures)
	await _verify_hold_position_no_chase(failures)
	await _verify_point_blank_arrow(failures)

	if failures.is_empty():
		print("VERIFY_RANGER_COMBAT_AUTO_ACQUIRE_PASSED")
	else:
		print("VERIFY_RANGER_COMBAT_AUTO_ACQUIRE_FAILED")
		for failure: String in failures:
			print("  - ", failure)
	await get_tree().process_frame
	get_tree().quit(0 if failures.is_empty() else 1)


func _expect(failures: PackedStringArray, label: String, ok: bool) -> void:
	if not ok:
		failures.append(label)


func _verify_ranger_attacks_all_ranges(failures: PackedStringArray) -> void:
	var ranges: Array[float] = [0.05, 1.0, 4.0, 7.5]
	for dist: float in ranges:
		var ranger: MeleeHero = RANGER_SCENE.instantiate() as MeleeHero
		var enemy: Node3D = ENEMY_DUMMY_SCENE.instantiate() as Node3D
		add_child(ranger)
		add_child(enemy)
		await get_tree().process_frame
		ranger.global_position = Vector3.ZERO
		enemy.global_position = Vector3(dist, 0.0, 0.0)
		CombatTargetValidation.reset_match_state()

		ranger.command_attack(enemy)
		await get_tree().physics_frame
		await get_tree().physics_frame

		_expect(
			failures,
			"ranger in attack range at dist %.2f" % dist,
			ranger._is_in_attack_range(enemy)
		)
		_expect(
			failures,
			"ranger never prefers kite at dist %.2f" % dist,
			not ranger._should_reposition_for_preferred_range()
		)
		_expect(
			failures,
			"ranger keeps attack target at dist %.2f" % dist,
			ranger.get_attack_target() == enemy
		)

		for _i in range(20):
			await get_tree().physics_frame

		_expect(
			failures,
			"ranger stays stopped in range at dist %.2f" % dist,
			not ranger.has_move_target
		)

		ranger.queue_free()
		enemy.queue_free()
		await get_tree().process_frame


func _verify_ranger_no_preferred_kite(failures: PackedStringArray) -> void:
	var ranger: MeleeHero = RANGER_SCENE.instantiate() as MeleeHero
	var enemy: Node3D = ENEMY_DUMMY_SCENE.instantiate() as Node3D
	add_child(ranger)
	add_child(enemy)
	await get_tree().process_frame
	ranger.global_position = Vector3.ZERO
	enemy.global_position = Vector3(1.0, 0.0, 0.0)
	ranger.command_attack(enemy)
	for _i in range(15):
		await get_tree().physics_frame
	_expect(failures, "ranger preferred-range always false", not ranger._should_reposition_for_preferred_range())
	_expect(failures, "ranger not backing off", not ranger._is_backing_off_for_range)
	_expect(failures, "ranger not chasing while in range", not ranger._has_chase_target)
	ranger.queue_free()
	enemy.queue_free()
	await get_tree().process_frame


func _verify_passive_stack_and_timeout(failures: PackedStringArray) -> void:
	var ranger: MeleeHero = RANGER_SCENE.instantiate() as MeleeHero
	add_child(ranger)
	await get_tree().process_frame

	var component: HeroPassiveComponent = HeroPassiveComponent.find_on(ranger)
	_expect(failures, "ranger has passive component", component != null and component.passive != null)
	if component == null or not component.passive is RangerPassive:
		ranger.queue_free()
		await get_tree().process_frame
		return

	var passive: RangerPassive = component.passive as RangerPassive
	var dummy_a: Node3D = ENEMY_DUMMY_SCENE.instantiate() as Node3D
	var dummy_b: Node3D = ENEMY_DUMMY_SCENE.instantiate() as Node3D
	add_child(dummy_a)
	add_child(dummy_b)
	await get_tree().process_frame
	dummy_a.global_position = Vector3(2, 0, 0)
	dummy_b.global_position = Vector3(3, 0, 0)

	var applied := {DamageService.RESULT_APPLIED: true}
	passive.on_basic_attack_hit(dummy_a, applied, 1)
	_expect(failures, "passive stack 1", passive.get_consecutive_hits() == 1)
	_expect(failures, "mark effect after hit 1", passive._mark_effect != null and is_instance_valid(passive._mark_effect))
	passive.on_basic_attack_hit(dummy_a, applied, 2)
	_expect(failures, "passive stack 2", passive.get_consecutive_hits() == 2)
	_expect(failures, "next hit is proc", passive.is_next_hit_precision_proc())
	passive.on_basic_attack_hit(dummy_b, applied, 3)
	_expect(failures, "target switch resets to 1", passive.get_consecutive_hits() == 1)

	passive.on_basic_attack_hit(dummy_a, applied, 4)
	passive.on_basic_attack_hit(dummy_a, applied, 5)
	_expect(failures, "stacks before timeout", passive.get_consecutive_hits() == 2)
	passive.tick(RangerStats.HUNTERS_PRECISION_STACK_TIMEOUT + 0.1)
	_expect(failures, "timeout clears stacks", passive.get_consecutive_hits() == 0)

	passive.on_basic_attack_hit(dummy_a, applied, 6)
	_expect(failures, "stack before building check", passive.get_consecutive_hits() == 1)
	var building: Building = Building.new()
	passive.on_basic_attack_hit(building, applied, 7)
	_expect(failures, "building resets stacks", passive.get_consecutive_hits() == 0)
	building.free()

	ranger.queue_free()
	dummy_a.queue_free()
	dummy_b.queue_free()
	await get_tree().process_frame


func _verify_idle_auto_acquire(failures: PackedStringArray) -> void:
	var unit: Swordsman = SWORDSMAN_SCENE.instantiate() as Swordsman
	var enemy: EnemyDummy = ENEMY_DUMMY_SCENE.instantiate() as EnemyDummy
	add_child(unit)
	add_child(enemy)
	await get_tree().process_frame
	unit.global_position = Vector3.ZERO
	var acquire_dist: float = unit.attack_range + 2.0
	enemy.global_position = Vector3(acquire_dist, 0.0, 0.0)
	CombatTargetValidation.reset_match_state()
	await get_tree().physics_frame

	_expect(failures, "acquisition range bonus applied", unit.get_acquisition_range() >= unit.attack_range + 3.4)
	var found: Node3D = unit._find_auto_acquire_target()
	_expect(failures, "auto-acquire search finds nearby enemy", found == enemy)

	unit._try_auto_attack()
	_expect(failures, "idle swordsman auto-acquires in acquisition range", unit._attack_target == enemy)

	unit.queue_free()
	enemy.queue_free()
	await get_tree().process_frame


func _verify_hold_position_no_chase(failures: PackedStringArray) -> void:
	var unit: Swordsman = SWORDSMAN_SCENE.instantiate() as Swordsman
	var enemy: EnemyDummy = ENEMY_DUMMY_SCENE.instantiate() as EnemyDummy
	add_child(unit)
	add_child(enemy)
	await get_tree().process_frame
	unit.global_position = Vector3.ZERO
	enemy.global_position = Vector3(unit.attack_range + 2.5, 0.0, 0.0)
	CombatTargetValidation.reset_match_state()
	unit.command_hold_position()

	for _i in range(30):
		await get_tree().physics_frame

	_expect(failures, "hold position does not chase out of range", unit._attack_target == null)
	unit.queue_free()
	enemy.queue_free()
	await get_tree().process_frame


func _verify_point_blank_arrow(failures: PackedStringArray) -> void:
	var ranger: MeleeHero = RANGER_SCENE.instantiate() as MeleeHero
	var enemy: Node3D = ENEMY_DUMMY_SCENE.instantiate() as Node3D
	add_child(ranger)
	add_child(enemy)
	await get_tree().process_frame
	ranger.global_position = Vector3.ZERO
	enemy.global_position = Vector3(0.02, 0.0, 0.0)

	var health_before: int = 0
	var hc: HealthComponent = enemy.get_node_or_null("HealthComponent") as HealthComponent
	if hc != null:
		health_before = hc.current_health

	ranger.call(&"_fire_basic_arrow", enemy)
	for _i in range(10):
		await get_tree().physics_frame

	if hc != null and is_instance_valid(hc):
		_expect(failures, "point-blank arrow deals damage", hc.current_health < health_before)
	else:
		failures.append("point-blank arrow target health missing")

	ranger.queue_free()
	if is_instance_valid(enemy):
		enemy.queue_free()
	await get_tree().process_frame
