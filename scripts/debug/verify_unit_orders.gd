extends Node

## Headless verification for RTS command queue, Stop, Hold, Patrol, Attack-Move.
## Godot_v4.7-stable_win64.exe --headless --path <project> res://scenes/debug/verify_unit_orders.tscn

const REPORT_PATH := "user://unit_orders_verify_result.txt"
const SWORDSMAN_SCENE: PackedScene = preload("res://scenes/units/swordsman.tscn")
const SPEARMAN_SCENE: PackedScene = preload("res://scenes/units/spearman.tscn")
const WORKER_SCENE: PackedScene = preload("res://scenes/units/worker.tscn")
const HERO_SCENE: PackedScene = preload("res://scenes/units/hero.tscn")
const CC_SCENE: PackedScene = preload("res://scenes/buildings/command_center.tscn")


func _ready() -> void:
	var failures: PackedStringArray = []
	CombatTargetValidation.reset_match_state()

	_verify_stop_during_movement(failures)
	await _verify_stop_during_combat(failures)
	_verify_hold_position(failures)
	_verify_patrol_points(failures)
	await _verify_attack_move_resume(failures)
	await _verify_enemy_pike_combat_targets(failures)
	await _verify_enemy_attack_move_objective_continuation(failures)
	_verify_queued_moves(failures)
	await _verify_queued_move_then_attack(failures)
	_verify_invalid_queued_target(failures)
	_verify_non_shift_replaces_queue(failures)
	_verify_worker_accepts_move_queue(failures)

	var report: String
	if failures.is_empty():
		report = "PASS unit_orders\n"
	else:
		report = "FAIL unit_orders\n" + "\n".join(failures) + "\n"

	var file := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(report)
		file.close()

	print(report)
	await get_tree().process_frame
	get_tree().quit(0 if failures.is_empty() else 1)


func _verify_stop_during_movement(failures: PackedStringArray) -> void:
	var unit: Swordsman = SWORDSMAN_SCENE.instantiate() as Swordsman
	add_child(unit)
	unit.global_position = Vector3.ZERO
	unit.issue_order(UnitOrder.move(Vector3(20, 0, 0)), false)
	_expect(failures, "stop/move: has move target", unit.has_move_target)
	_expect(failures, "stop/move: active move order", unit.get_active_order() != null)

	unit.issue_stop()
	_expect(failures, "stop during move: cleared move", not unit.has_move_target)
	_expect(failures, "stop during move: cleared active order", unit.get_active_order() == null)
	_expect(failures, "stop during move: cleared queue", not unit.has_queued_orders())
	_expect(failures, "stop during move: no attack-move", not unit._has_attack_move_destination)
	unit.queue_free()


func _verify_stop_during_combat(failures: PackedStringArray) -> void:
	var unit: Swordsman = SWORDSMAN_SCENE.instantiate() as Swordsman
	var enemy: Spearman = SPEARMAN_SCENE.instantiate() as Spearman
	add_child(unit)
	add_child(enemy)
	await get_tree().process_frame
	unit.global_position = Vector3.ZERO
	enemy.global_position = Vector3(1.5, 0, 0)
	enemy.add_to_group(&"enemies")

	unit.command_attack(enemy)
	_expect(failures, "stop/combat: has attack target", unit._attack_target == enemy)

	unit.issue_stop()
	_expect(failures, "stop during combat: cleared attack", unit._attack_target == null)
	_expect(failures, "stop during combat: not chasing", not unit._has_chase_target)
	_expect(failures, "stop during combat: idle move", not unit.has_move_target)
	enemy.queue_free()
	unit.queue_free()
	await get_tree().process_frame


func _verify_hold_position(failures: PackedStringArray) -> void:
	var unit: Swordsman = SWORDSMAN_SCENE.instantiate() as Swordsman
	add_child(unit)
	unit.global_position = Vector3(3, 0, 0)
	unit.issue_order(UnitOrder.hold_position(), false)
	_expect(failures, "hold: flag set", unit._is_holding_position)
	_expect(failures, "hold: no move target", not unit.has_move_target)
	_expect(
		failures,
		"hold: anchor near unit",
		unit._hold_anchor.distance_to(unit.global_position) < 0.1
	)

	unit.issue_order(UnitOrder.move(Vector3(10, 0, 0)), false)
	_expect(failures, "hold: move clears hold", not unit._is_holding_position)
	unit.queue_free()


func _verify_patrol_points(failures: PackedStringArray) -> void:
	var unit: Swordsman = SWORDSMAN_SCENE.instantiate() as Swordsman
	add_child(unit)
	unit.global_position = Vector3.ZERO
	var points: Array[Vector3] = [Vector3.ZERO, Vector3(8, 0, 0), Vector3(8, 0, 8)]
	unit.issue_order(UnitOrder.patrol(points), false)
	_expect(failures, "patrol: active", unit._is_patrolling)
	_expect(failures, "patrol: at least 2 points", unit._patrol_points.size() >= 2)
	_expect(failures, "patrol: attack-move leg", unit._has_attack_move_destination)

	unit.append_patrol_point(Vector3(0, 0, 8))
	_expect(failures, "patrol: append grows route", unit._patrol_points.size() >= 3)

	unit.issue_stop()
	_expect(failures, "patrol: stop clears patrol", not unit._is_patrolling)
	unit.queue_free()


func _verify_attack_move_resume(failures: PackedStringArray) -> void:
	var unit: Swordsman = SWORDSMAN_SCENE.instantiate() as Swordsman
	var enemy: Spearman = SPEARMAN_SCENE.instantiate() as Spearman
	add_child(unit)
	add_child(enemy)
	await get_tree().process_frame
	unit.global_position = Vector3.ZERO
	enemy.global_position = Vector3(2, 0, 0)
	enemy.add_to_group(&"enemies")

	unit.command_attack_move(Vector3(12, 0, 0))
	_expect(failures, "amove: destination set", unit._has_attack_move_destination)

	unit._begin_attack_on_target(enemy, -1, false)
	_expect(failures, "amove: opportunistic attack", unit._attack_target == enemy)
	_expect(failures, "amove: not committed", not unit._committed_attack_order)

	enemy._health_component.current_health = 0
	unit._sanitize_attack_target()
	_expect(failures, "amove: resumed after combat", unit._has_attack_move_destination)
	_expect(failures, "amove: chase cleared", unit._attack_target == null)

	enemy.queue_free()
	unit.queue_free()
	await get_tree().process_frame

	## At destination with a second local target: keep attack-move and re-engage.
	var camp_fighter: Swordsman = SWORDSMAN_SCENE.instantiate() as Swordsman
	var first: Spearman = SPEARMAN_SCENE.instantiate() as Spearman
	var second: Spearman = SPEARMAN_SCENE.instantiate() as Spearman
	add_child(camp_fighter)
	add_child(first)
	add_child(second)
	await get_tree().process_frame
	camp_fighter.global_position = Vector3(20, 0, 0)
	first.global_position = Vector3(21, 0, 0)
	second.global_position = Vector3(21.5, 0, 0)
	first.add_to_group(&"enemies")
	second.add_to_group(&"enemies")
	camp_fighter.command_attack_move(Vector3(20, 0, 0))
	camp_fighter._begin_attack_on_target(first, -1, false)
	_expect(failures, "amove@dest: attacking first", camp_fighter._attack_target == first)
	first._health_component.current_health = 0
	camp_fighter._sanitize_attack_target()
	_expect(failures, "amove@dest: keeps attack-move", camp_fighter._has_attack_move_destination)
	_expect(failures, "amove@dest: re-engages second", camp_fighter._attack_target == second)
	first.queue_free()
	second.queue_free()
	camp_fighter.queue_free()
	await get_tree().process_frame


## A/B — Enemy Pike can command_attack player Hero and Town Hall and deal damage.
func _verify_enemy_pike_combat_targets(failures: PackedStringArray) -> void:
	var pike: Spearman = SPEARMAN_SCENE.instantiate() as Spearman
	var hero: Hero = HERO_SCENE.instantiate() as Hero
	add_child(pike)
	add_child(hero)
	await get_tree().process_frame
	pike.global_position = Vector3(0, 0, 0)
	pike.team_id = 1
	pike.add_to_group(&"enemies")
	hero.global_position = Vector3(1.5, 0, 0)
	hero.team_id = TeamVisuals.PLAYER_TEAM_ID
	hero.add_to_group(&"heroes")
	hero.add_to_group(&"units")
	_expect(
		failures,
		"A: pike may attack player Hero",
		CombatTargetValidation.is_attack_target_for_attacker(pike, hero)
	)
	var hero_hp_before: int = hero.get_current_health()
	pike.command_attack(hero)
	_expect(failures, "A: pike attack target is Hero", pike._attack_target == hero)
	## Place already in melee range and strike once through the combat pipeline.
	DamageService.apply(hero, float(pike.attack_damage), pike)
	_expect(failures, "A: Hero took damage from Pike", hero.get_current_health() < hero_hp_before)
	hero.queue_free()
	pike.queue_free()
	await get_tree().process_frame

	var pike2: Spearman = SPEARMAN_SCENE.instantiate() as Spearman
	var town_hall: CommandCenter = CC_SCENE.instantiate() as CommandCenter
	add_child(pike2)
	add_child(town_hall)
	await get_tree().process_frame
	pike2.global_position = Vector3(10, 0, 0)
	pike2.team_id = 1
	pike2.add_to_group(&"enemies")
	town_hall.global_position = Vector3(12, 0, 0)
	town_hall.team_id = TeamVisuals.PLAYER_TEAM_ID
	town_hall.set_completed()
	if town_hall.is_in_group(&"enemy_command_center"):
		town_hall.remove_from_group(&"enemy_command_center")
	town_hall.add_to_group(&"player_command_center")
	town_hall.add_to_group(&"buildings")
	_expect(
		failures,
		"B: pike may attack player Town Hall",
		CombatTargetValidation.is_attack_target_for_attacker(pike2, town_hall)
	)
	var th_hp_before: int = town_hall.get_node("HealthComponent").current_health
	pike2.command_attack(town_hall)
	_expect(failures, "B: pike attack target is Town Hall", pike2._attack_target == town_hall)
	DamageService.apply(town_hall, float(pike2.attack_damage), pike2)
	var th_hp_after: int = town_hall.get_node("HealthComponent").current_health
	_expect(failures, "B: Town Hall took damage from Pike", th_hp_after < th_hp_before)
	town_hall.queue_free()
	pike2.queue_free()
	await get_tree().process_frame


## C — Enemy attack-move at approach standoff reacquires Town Hall after local target death.
func _verify_enemy_attack_move_objective_continuation(failures: PackedStringArray) -> void:
	var pike: Spearman = SPEARMAN_SCENE.instantiate() as Spearman
	var local_enemy: Hero = HERO_SCENE.instantiate() as Hero
	var town_hall: CommandCenter = CC_SCENE.instantiate() as CommandCenter
	add_child(pike)
	add_child(local_enemy)
	add_child(town_hall)
	await get_tree().process_frame

	town_hall.global_position = Vector3(40, 0, 0)
	town_hall.team_id = TeamVisuals.PLAYER_TEAM_ID
	town_hall.set_completed()
	if town_hall.is_in_group(&"enemy_command_center"):
		town_hall.remove_from_group(&"enemy_command_center")
	town_hall.add_to_group(&"player_command_center")
	town_hall.add_to_group(&"buildings")

	## Approach standoff slot: outside short engage ring historically, inside objective range.
	pike.global_position = town_hall.global_position + Vector3(-16, 0, 4)
	pike.team_id = 1
	pike.add_to_group(&"enemies")
	local_enemy.global_position = pike.global_position + Vector3(1.2, 0, 0)
	local_enemy.team_id = TeamVisuals.PLAYER_TEAM_ID
	local_enemy.add_to_group(&"heroes")
	local_enemy.add_to_group(&"units")

	var approach: Vector3 = pike.global_position
	pike.command_attack_move(approach)
	_expect(failures, "C: amove set", pike._has_attack_move_destination)
	pike._begin_attack_on_target(local_enemy, -1, false)
	_expect(failures, "C: fighting local Hero", pike._attack_target == local_enemy)

	local_enemy.get_node("HealthComponent").current_health = 0
	pike._sanitize_attack_target()
	_expect(failures, "C: keeps amove after local death", pike._has_attack_move_destination)
	## At destination: must reacquire Town Hall instead of cancelling into IDLE.
	var engaged: bool = pike._try_attack_move_engagement()
	_expect(failures, "C: reacquires objective after local death", engaged)
	_expect(failures, "C: objective is Town Hall", pike._attack_target == town_hall)
	_expect(failures, "C: not idle after continuation", pike._attack_target != null)

	local_enemy.queue_free()
	town_hall.queue_free()
	pike.queue_free()
	await get_tree().process_frame


func _verify_queued_moves(failures: PackedStringArray) -> void:
	var unit: Swordsman = SWORDSMAN_SCENE.instantiate() as Swordsman
	add_child(unit)
	unit.global_position = Vector3.ZERO
	unit.issue_order(UnitOrder.move(Vector3(5, 0, 0)), false)
	unit.issue_order(UnitOrder.move(Vector3(10, 0, 0)), true)
	unit.issue_order(UnitOrder.move(Vector3(15, 0, 0)), true)
	_expect(failures, "queue moves: 2 queued", unit.get_queued_orders().size() == 2)
	_expect(
		failures,
		"queue moves: active is first",
		unit.get_active_order() != null and unit.get_active_order().type == UnitOrder.Type.MOVE
	)

	unit.notify_order_completed(UnitOrder.Type.MOVE)
	_expect(failures, "queue moves: advanced", unit.get_queued_orders().size() == 1)
	_expect(
		failures,
		"queue moves: second now active",
		unit.get_active_order() != null and unit.get_active_order().destination.x == 10.0
	)
	unit.queue_free()


func _verify_queued_move_then_attack(failures: PackedStringArray) -> void:
	var unit: Swordsman = SWORDSMAN_SCENE.instantiate() as Swordsman
	var enemy: Spearman = SPEARMAN_SCENE.instantiate() as Spearman
	add_child(unit)
	add_child(enemy)
	await get_tree().process_frame
	unit.global_position = Vector3.ZERO
	enemy.global_position = Vector3(4, 0, 0)
	enemy.add_to_group(&"enemies")

	unit.issue_order(UnitOrder.move(Vector3(2, 0, 0)), false)
	unit.issue_order(UnitOrder.attack(enemy), true)
	_expect(failures, "queue move+attack: one queued", unit.get_queued_orders().size() == 1)

	unit.notify_order_completed(UnitOrder.Type.MOVE)
	_expect(
		failures,
		"queue move+attack: attack started",
		unit.get_active_order() != null and unit.get_active_order().type == UnitOrder.Type.ATTACK
	)
	_expect(failures, "queue move+attack: targeting enemy", unit._attack_target == enemy)

	enemy.queue_free()
	unit.queue_free()
	await get_tree().process_frame


func _verify_invalid_queued_target(failures: PackedStringArray) -> void:
	var unit: Swordsman = SWORDSMAN_SCENE.instantiate() as Swordsman
	var enemy: Spearman = SPEARMAN_SCENE.instantiate() as Spearman
	add_child(unit)
	add_child(enemy)
	unit.global_position = Vector3.ZERO
	enemy.global_position = Vector3(3, 0, 0)

	unit.issue_order(UnitOrder.move(Vector3(1, 0, 0)), false)
	unit.issue_order(UnitOrder.attack(enemy), true)
	unit.issue_order(UnitOrder.move(Vector3(20, 0, 0)), true)
	enemy.free()

	unit.notify_order_completed(UnitOrder.Type.MOVE)
	_expect(
		failures,
		"invalid queued target skipped",
		unit.get_active_order() != null and unit.get_active_order().type == UnitOrder.Type.MOVE
	)
	_expect(
		failures,
		"invalid queued target: fell through to next move",
		is_equal_approx(unit.get_active_order().destination.x, 20.0)
	)
	unit.queue_free()


func _verify_non_shift_replaces_queue(failures: PackedStringArray) -> void:
	var unit: Swordsman = SWORDSMAN_SCENE.instantiate() as Swordsman
	add_child(unit)
	unit.global_position = Vector3.ZERO
	unit.issue_order(UnitOrder.move(Vector3(5, 0, 0)), false)
	unit.issue_order(UnitOrder.move(Vector3(10, 0, 0)), true)
	unit.issue_order(UnitOrder.move(Vector3(15, 0, 0)), true)
	_expect(failures, "replace: had queue", unit.has_queued_orders())

	unit.issue_order(UnitOrder.move(Vector3(7, 0, 0)), false)
	_expect(failures, "replace: queue cleared", not unit.has_queued_orders())
	_expect(
		failures,
		"replace: new active destination",
		unit.get_active_order() != null and is_equal_approx(unit.get_active_order().destination.x, 7.0)
	)
	unit.queue_free()


func _verify_worker_accepts_move_queue(failures: PackedStringArray) -> void:
	var worker: Worker = WORKER_SCENE.instantiate() as Worker
	add_child(worker)
	worker.global_position = Vector3.ZERO
	worker.issue_order(UnitOrder.move(Vector3(4, 0, 0)), false)
	worker.issue_order(UnitOrder.move(Vector3(9, 0, 0)), true)
	_expect(failures, "worker queue: has queued move", worker.has_queued_orders())
	_expect(failures, "worker rejects combat hold", not worker.supports_hold_position())
	worker.issue_stop()
	_expect(failures, "worker stop clears queue", not worker.has_queued_orders())
	worker.queue_free()


func _expect(failures: PackedStringArray, label: String, ok: bool) -> void:
	if not ok:
		failures.append(label)
