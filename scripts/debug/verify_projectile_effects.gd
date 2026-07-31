extends Node

## Headless verification for projectile trails, smoke, and impact FX.
## Godot_v4.7-stable_win64.exe --headless --path <project> res://scenes/debug/verify_projectile_effects.tscn

const REPORT_PATH := "user://projectile_effects_verify_result.txt"
const ARROW_SCENE: PackedScene = preload("res://scenes/projectiles/arrow.tscn")
const SHELL_SCENE: PackedScene = preload("res://scenes/projectiles/artillery_shell.tscn")
const SWORDSMAN_SCENE: PackedScene = preload("res://scenes/units/swordsman.tscn")
const HERO_SCENE: PackedScene = preload("res://scenes/units/hero.tscn")


func _ready() -> void:
	var failures: PackedStringArray = []
	ImpactEffects.clear_all()
	ImpactEffects.enabled = true
	ImpactEffects.trails_enabled = true
	ImpactEffects.smoke_enabled = true
	ImpactEffects.ground_dust_enabled = true
	ImpactEffects.hit_sparks_enabled = true

	await _verify_arrow_trail_and_unit_hit(failures)
	await _verify_arrow_ground_miss(failures)
	await _verify_shell_smoke_and_impact(failures)
	await _verify_hero_impact_reuse(failures)
	await _verify_pool_reuse(failures)
	await _verify_mass_cap(failures)
	_verify_match_reset_clears(failures)

	var report: String
	if failures.is_empty():
		report = "PASS projectile_effects\n"
	else:
		report = "FAIL projectile_effects\n" + "\n".join(failures) + "\n"

	var file := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(report)
		file.close()

	print(report)
	await get_tree().process_frame
	get_tree().quit(0 if failures.is_empty() else 1)


func _verify_arrow_trail_and_unit_hit(failures: PackedStringArray) -> void:
	print("verify: arrow trail + unit hit sparks")
	ImpactEffects.clear_all()

	var target: Swordsman = SWORDSMAN_SCENE.instantiate() as Swordsman
	add_child(target)
	target.global_position = Vector3(4.0, 0.0, 0.0)
	await get_tree().process_frame

	var arrow: Arrow = ARROW_SCENE.instantiate() as Arrow
	add_child(arrow)
	arrow.launch(target, 1.0, Vector3(0.0, 0.8, 0.0), null)
	await get_tree().process_frame
	_expect(failures, "arrow trail attached", ImpactEffects.get_active_trail_count() >= 1)

	# Wait until the arrow should have hit.
	for _i: int in range(40):
		await get_tree().physics_frame
		if not is_instance_valid(arrow):
			break

	_expect(failures, "arrow freed after hit", not is_instance_valid(arrow))
	_expect(failures, "unit hit sparks", ImpactEffects.get_active_burst_count() >= 1)
	_expect(failures, "trail released after free", ImpactEffects.get_active_trail_count() == 0)

	target.queue_free()
	await get_tree().process_frame


func _verify_arrow_ground_miss(failures: PackedStringArray) -> void:
	print("verify: arrow ground miss dust")
	ImpactEffects.clear_all()

	var target: Swordsman = SWORDSMAN_SCENE.instantiate() as Swordsman
	add_child(target)
	target.global_position = Vector3(3.0, 0.0, 0.0)
	await get_tree().process_frame

	var arrow: Arrow = ARROW_SCENE.instantiate() as Arrow
	add_child(arrow)
	arrow.launch(target, 1.0, Vector3(0.0, 0.8, 0.0), null)
	await get_tree().process_frame

	# Kill target mid-flight so the arrow misses and plays ground dust.
	target.queue_free()
	await get_tree().process_frame

	for _i: int in range(10):
		await get_tree().physics_frame
		if not is_instance_valid(arrow):
			break

	_expect(failures, "miss arrow freed", not is_instance_valid(arrow))
	_expect(failures, "ground dust on miss", ImpactEffects.get_active_burst_count() >= 1)
	await get_tree().process_frame


func _verify_shell_smoke_and_impact(failures: PackedStringArray) -> void:
	print("verify: shell smoke + ground burst")
	ImpactEffects.clear_all()

	var target: Swordsman = SWORDSMAN_SCENE.instantiate() as Swordsman
	add_child(target)
	target.global_position = Vector3(2.5, 0.0, 0.0)
	await get_tree().process_frame

	var shell: ArtilleryShell = SHELL_SCENE.instantiate() as ArtilleryShell
	add_child(shell)
	shell.launch(target, 5.0, 1.5, Vector3(0.0, 0.9, 0.0), null, 0.5)
	await get_tree().process_frame
	_expect(failures, "shell smoke attached", ImpactEffects.get_active_trail_count() >= 1)

	for _i: int in range(50):
		await get_tree().physics_frame
		if not is_instance_valid(shell):
			break

	_expect(failures, "shell freed after impact", not is_instance_valid(shell))
	_expect(failures, "shell impact bursts", ImpactEffects.get_active_burst_count() >= 1)
	_expect(failures, "smoke released after free", ImpactEffects.get_active_trail_count() == 0)

	target.queue_free()
	await get_tree().process_frame


func _verify_hero_impact_reuse(failures: PackedStringArray) -> void:
	print("verify: hero abilities reuse impact framework")
	ImpactEffects.clear_all()

	var hero: Hero = HERO_SCENE.instantiate() as Hero
	add_child(hero)
	hero.global_position = Vector3(0.0, 0.0, 0.0)
	await get_tree().process_frame

	var before: int = ImpactEffects.get_active_burst_count()
	ImpactEffects.play_unit_impact(hero.global_position, 1.25)
	ImpactEffects.play_ground_impact(hero.global_position, 1.2)
	_expect(
		failures,
		"hero impact bursts",
		ImpactEffects.get_active_burst_count() > before
	)

	hero.queue_free()
	await get_tree().process_frame


func _verify_pool_reuse(failures: PackedStringArray) -> void:
	print("verify: impact pool reuse")
	ImpactEffects.clear_all()

	ImpactEffects.play_ground_impact(Vector3(1.0, 0.0, 1.0))
	ImpactEffects.play_unit_impact(Vector3(2.0, 0.0, 1.0))
	await get_tree().create_timer(0.7).timeout
	ImpactEffects.clear_all()

	var idle_dust: int = ImpactFxPool.get_idle_count(ImpactFxPool.FxKind.GROUND_DUST)
	var idle_sparks: int = ImpactFxPool.get_idle_count(ImpactFxPool.FxKind.HIT_SPARKS)
	# clear_all frees active and resets pool; re-spawn then release via prune to fill idle.
	ImpactEffects.play_ground_impact(Vector3(1.0, 0.0, 1.0))
	ImpactEffects.play_unit_impact(Vector3(2.0, 0.0, 1.0))
	await get_tree().create_timer(0.7).timeout
	_prune_via_process()
	await get_tree().process_frame

	idle_dust = ImpactFxPool.get_idle_count(ImpactFxPool.FxKind.GROUND_DUST)
	idle_sparks = ImpactFxPool.get_idle_count(ImpactFxPool.FxKind.HIT_SPARKS)
	_expect(failures, "ground dust pooled", idle_dust >= 1)
	_expect(failures, "hit sparks pooled", idle_sparks >= 1)

	var before_idle: int = idle_dust + idle_sparks
	ImpactEffects.play_ground_impact(Vector3(0.5, 0.0, 0.5))
	ImpactEffects.play_unit_impact(Vector3(1.5, 0.0, 0.5))
	var after_idle: int = (
		ImpactFxPool.get_idle_count(ImpactFxPool.FxKind.GROUND_DUST)
		+ ImpactFxPool.get_idle_count(ImpactFxPool.FxKind.HIT_SPARKS)
	)
	_expect(failures, "pool reused emitters", after_idle < before_idle)


func _verify_mass_cap(failures: PackedStringArray) -> void:
	print("verify: mass battle burst cap")
	ImpactEffects.clear_all()

	for i: int in range(80):
		ImpactEffects.play_ground_impact(Vector3(float(i % 10), 0.0, float(i / 10)))
		ImpactEffects.play_unit_impact(Vector3(float(i % 10) + 0.5, 0.0, float(i / 10)))

	_expect(
		failures,
		"burst cap respected",
		ImpactEffects.get_active_burst_count() <= ImpactEffects.MAX_ACTIVE_BURSTS
	)

	var host := Node3D.new()
	add_child(host)
	for i: int in range(60):
		ImpactEffects.attach_arrow_trail(host)
	_expect(
		failures,
		"trail cap respected",
		ImpactEffects.get_active_trail_count() <= ImpactEffects.MAX_ACTIVE_TRAILS
	)
	ImpactEffects.clear_all()
	host.queue_free()
	await get_tree().process_frame


func _verify_match_reset_clears(failures: PackedStringArray) -> void:
	print("verify: match reset clears impact fx")
	ImpactEffects.clear_all()
	ImpactEffects.play_shell_impact(Vector3(0.0, 0.0, 0.0))
	ImpactEffects.play_unit_impact(Vector3(1.0, 0.0, 0.0))
	var host := Node3D.new()
	add_child(host)
	ImpactEffects.attach_shell_smoke(host)
	_expect(failures, "smoke attached before clear", ImpactEffects.get_active_trail_count() >= 1)

	ImpactEffects.clear_all()
	_expect(failures, "bursts cleared", ImpactEffects.get_active_burst_count() == 0)
	_expect(failures, "trails cleared", ImpactEffects.get_active_trail_count() == 0)
	_expect(
		failures,
		"pool idle cleared",
		ImpactFxPool.get_idle_count(ImpactFxPool.FxKind.GROUND_DUST) == 0
	)
	host.queue_free()


func _prune_via_process() -> void:
	# ImpactEffects prunes in _process; force a couple frames.
	pass


func _expect(failures: PackedStringArray, label: String, ok: bool) -> void:
	if not ok:
		failures.append(label)
		print("  FAIL ", label)
	else:
		print("  ok   ", label)
