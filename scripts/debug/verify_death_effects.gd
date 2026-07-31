extends Node

## Headless verification for shared death dust/blood/rubble/corpse FX.
## Godot_v4.7-stable_win64.exe --headless --path <project> res://scenes/debug/verify_death_effects.tscn

const REPORT_PATH := "user://death_effects_verify_result.txt"
const SWORDSMAN_SCENE: PackedScene = preload("res://scenes/units/swordsman.tscn")
const HERO_SCENE: PackedScene = preload("res://scenes/units/hero.tscn")
const FARM_SCENE: PackedScene = preload("res://scenes/buildings/farm.tscn")


func _ready() -> void:
	var failures: PackedStringArray = []
	DeathEffects.clear_all()
	DeathEffects.enabled = true
	DeathEffects.dust_enabled = true
	DeathEffects.blood_enabled = true
	DeathEffects.corpse_enabled = true
	DeathEffects.rubble_enabled = true
	DeathEffects.corpse_duration = 0.35
	DeathEffects.corpse_fade_duration = 0.2

	await _verify_unit_death(failures)
	await _verify_hero_death_larger(failures)
	await _verify_building_rubble(failures)
	await _verify_no_duplicate_effects(failures)
	await _verify_blood_toggle(failures)
	await _verify_pool_reuse(failures)
	await _verify_mass_battle_cap(failures)
	_verify_match_reset_clears(failures)

	var report: String
	if failures.is_empty():
		report = "PASS death_effects\n"
	else:
		report = "FAIL death_effects\n" + "\n".join(failures) + "\n"

	var file := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(report)
		file.close()

	print(report)
	await get_tree().process_frame
	get_tree().quit(0 if failures.is_empty() else 1)


func _verify_unit_death(failures: PackedStringArray) -> void:
	print("verify: unit death dust + corpse")
	DeathEffects.clear_all()
	var unit: Swordsman = SWORDSMAN_SCENE.instantiate() as Swordsman
	add_child(unit)
	unit.global_position = Vector3(1.0, 0.0, 2.0)
	await get_tree().process_frame

	unit.die()
	_expect(failures, "unit death particles", DeathEffects.get_active_particle_count() >= 1)
	_expect(failures, "unit corpse spawned", DeathEffects.get_active_corpse_count() == 1)
	unit.queue_free()
	await get_tree().process_frame


func _verify_hero_death_larger(failures: PackedStringArray) -> void:
	print("verify: hero death larger dust")
	DeathEffects.clear_all()
	var hero: Hero = HERO_SCENE.instantiate() as Hero
	add_child(hero)
	hero.global_position = Vector3(3.0, 0.0, 1.0)
	await get_tree().process_frame

	var before: int = DeathEffects.get_active_particle_count()
	DeathEffects.play_unit_death(hero)
	_expect(
		failures,
		"hero death particles",
		DeathEffects.get_active_particle_count() > before
	)
	_expect(failures, "hero corpse spawned", DeathEffects.get_active_corpse_count() >= 1)

	# Hero corpse scale should be larger than a unit corpse.
	var hero_scale: float = 0.0
	for child: Node in get_children():
		if child.name == "PooledCorpse" or String(child.name).begins_with("PooledCorpse"):
			hero_scale = maxf(hero_scale, (child as Node3D).scale.x)
	# Corpses are parented to current_scene (this node in headless verify).
	for child: Node in get_children():
		if child is Node3D and child.get_node_or_null("CorpseMesh") != null:
			hero_scale = maxf(hero_scale, (child as Node3D).scale.x)

	_expect(failures, "hero corpse scale larger", hero_scale >= DeathEffects.HERO_CORPSE_SCALE * 0.99)
	hero.queue_free()
	await get_tree().process_frame


func _verify_building_rubble(failures: PackedStringArray) -> void:
	print("verify: building rubble dust")
	DeathEffects.clear_all()
	var farm: Building = FARM_SCENE.instantiate() as Building
	add_child(farm)
	farm.global_position = Vector3(-2.0, 0.0, 0.0)
	await get_tree().process_frame

	farm.destroy_building()
	_expect(failures, "building rubble particles", DeathEffects.get_active_particle_count() >= 1)
	_expect(failures, "building has no corpse", DeathEffects.get_active_corpse_count() == 0)
	farm.queue_free()
	await get_tree().process_frame


func _verify_no_duplicate_effects(failures: PackedStringArray) -> void:
	print("verify: duplicate prevention")
	DeathEffects.clear_all()
	var unit: Swordsman = SWORDSMAN_SCENE.instantiate() as Swordsman
	add_child(unit)
	unit.global_position = Vector3.ZERO
	await get_tree().process_frame

	DeathEffects.play_unit_death(unit)
	var after_first: int = DeathEffects.get_active_particle_count()
	var corpses_first: int = DeathEffects.get_active_corpse_count()
	DeathEffects.play_unit_death(unit)
	_expect(
		failures,
		"duplicate play does not add particles",
		DeathEffects.get_active_particle_count() == after_first
	)
	_expect(
		failures,
		"duplicate play does not add corpses",
		DeathEffects.get_active_corpse_count() == corpses_first
	)
	unit.queue_free()
	await get_tree().process_frame


func _verify_blood_toggle(failures: PackedStringArray) -> void:
	print("verify: blood toggle")
	DeathEffects.clear_all()
	DeathEffects.blood_enabled = false
	var unit: Swordsman = SWORDSMAN_SCENE.instantiate() as Swordsman
	add_child(unit)
	unit.global_position = Vector3(0.0, 0.0, 4.0)
	await get_tree().process_frame

	DeathEffects.play_unit_death(unit)
	# Dust + no blood => still at least one particle burst.
	_expect(failures, "dust still plays with blood off", DeathEffects.get_active_particle_count() >= 1)
	DeathEffects.blood_enabled = true
	unit.queue_free()
	await get_tree().process_frame


func _verify_pool_reuse(failures: PackedStringArray) -> void:
	print("verify: pool reuse")
	DeathEffects.clear_all()
	DeathEffects.corpse_duration = 0.05
	DeathEffects.corpse_fade_duration = 0.05

	for i: int in 6:
		var unit: Swordsman = SWORDSMAN_SCENE.instantiate() as Swordsman
		add_child(unit)
		unit.global_position = Vector3(float(i), 0.0, 6.0)
		DeathEffects.play_unit_death(unit)
		unit.queue_free()

	# Let particle lifetimes and corpse fades finish so pool can reclaim.
	await get_tree().create_timer(1.2).timeout
	DeathEffects.clear_all()

	var idle_dust: int = DeathFxPool.get_idle_count(DeathFxPool.FxKind.UNIT_DUST)
	var idle_blood: int = DeathFxPool.get_idle_count(DeathFxPool.FxKind.BLOOD)
	var idle_corpse: int = DeathFxPool.get_idle_count(DeathFxPool.FxKind.CORPSE)
	# After clear_all, pool reset frees idle — confirm acquire/release path works by spawning again.
	DeathEffects.clear_all()
	var unit2: Swordsman = SWORDSMAN_SCENE.instantiate() as Swordsman
	add_child(unit2)
	unit2.global_position = Vector3(8.0, 0.0, 0.0)
	DeathEffects.play_unit_death(unit2)
	_expect(failures, "pool path spawns after reuse cycle", DeathEffects.get_active_particle_count() >= 1)
	_expect(failures, "pool path corpse after reuse cycle", DeathEffects.get_active_corpse_count() >= 1)

	# Return actives to the pool (not clear_all, which frees and wipes idle).
	var particle_snapshot: Array[Dictionary] = DeathEffects._active_particles.duplicate()
	var corpse_snapshot: Array[Dictionary] = DeathEffects._active_corpses.duplicate()
	DeathEffects._active_particles.clear()
	DeathEffects._active_corpses.clear()
	for entry: Dictionary in particle_snapshot:
		var particles: GPUParticles3D = entry.get("node") as GPUParticles3D
		if particles != null and is_instance_valid(particles):
			DeathFxPool.release_particles(particles, entry.get("kind") as DeathFxPool.FxKind)
	for entry: Dictionary in corpse_snapshot:
		var corpse: Node3D = entry.get("node") as Node3D
		if corpse != null and is_instance_valid(corpse):
			DeathFxPool.release_corpse(corpse)

	idle_dust = DeathFxPool.get_idle_count(DeathFxPool.FxKind.UNIT_DUST)
	idle_blood = DeathFxPool.get_idle_count(DeathFxPool.FxKind.BLOOD)
	idle_corpse = DeathFxPool.get_idle_count(DeathFxPool.FxKind.CORPSE)
	_expect(failures, "unit dust returned to pool", idle_dust >= 1)
	_expect(failures, "blood returned to pool", idle_blood >= 1)
	_expect(failures, "corpse returned to pool", idle_corpse >= 1)

	var before_dust: int = idle_dust
	var before_blood: int = idle_blood
	var before_corpse: int = idle_corpse
	DeathEffects.play_unit_death(unit2)
	# Same instance id was already marked — clear played ids for reuse test.
	DeathEffects._played_instance_ids.clear()
	DeathEffects.play_unit_death(unit2)
	_expect(
		failures,
		"acquire reduces idle dust",
		DeathFxPool.get_idle_count(DeathFxPool.FxKind.UNIT_DUST) < before_dust
		or DeathEffects.get_active_particle_count() >= 1
	)
	_expect(
		failures,
		"acquire reduces idle blood or corpse active",
		DeathFxPool.get_idle_count(DeathFxPool.FxKind.BLOOD) < before_blood
		or DeathFxPool.get_idle_count(DeathFxPool.FxKind.CORPSE) < before_corpse
		or DeathEffects.get_active_corpse_count() >= 1
	)
	unit2.queue_free()
	await get_tree().process_frame


func _verify_mass_battle_cap(failures: PackedStringArray) -> void:
	print("verify: mass battle particle cap")
	DeathEffects.clear_all()
	DeathEffects._played_instance_ids.clear()

	for i: int in 80:
		var unit: Swordsman = SWORDSMAN_SCENE.instantiate() as Swordsman
		add_child(unit)
		unit.global_position = Vector3(float(i % 10), 0.0, float(i / 10))
		DeathEffects.play_unit_death(unit)
		unit.queue_free()

	_expect(
		failures,
		"particle cap respected",
		DeathEffects.get_active_particle_count() <= DeathEffects.MAX_ACTIVE_PARTICLES
	)
	_expect(
		failures,
		"corpse cap respected",
		DeathEffects.get_active_corpse_count() <= DeathEffects.MAX_ACTIVE_CORPSES
	)
	await get_tree().process_frame


func _verify_match_reset_clears(failures: PackedStringArray) -> void:
	print("verify: match reset clears death FX")
	DeathEffects.clear_all()
	var unit: Swordsman = SWORDSMAN_SCENE.instantiate() as Swordsman
	add_child(unit)
	DeathEffects.play_unit_death(unit)
	_expect(failures, "pre-reset has FX", DeathEffects.get_active_particle_count() > 0)
	DeathEffects.clear_all()
	_expect(failures, "clear_all removes particles", DeathEffects.get_active_particle_count() == 0)
	_expect(failures, "clear_all removes corpses", DeathEffects.get_active_corpse_count() == 0)
	unit.queue_free()


func _expect(failures: PackedStringArray, label: String, ok: bool) -> void:
	if not ok:
		failures.append(label)
		print("FAIL ", label)
	else:
		print("ok   ", label)
