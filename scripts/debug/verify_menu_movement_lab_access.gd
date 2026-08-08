extends Node

## Headless check: main menu exposes Movement Lab and lab stays isolated.
## Godot --headless --path <project> --scene res://scenes/debug/verify_menu_movement_lab_access.tscn

const MENU_SCENE := "res://scenes/ui/main_menu.tscn"
const LAB_SCENE := "res://scenes/debug/rts_movement_lab.tscn"


func _ready() -> void:
	var failures: PackedStringArray = []
	print("verify_menu_movement_lab_access: start")

	var menu_packed: PackedScene = load(MENU_SCENE) as PackedScene
	if menu_packed == null:
		failures.append("failed to load main menu scene")
	else:
		var menu: Node = menu_packed.instantiate()
		add_child(menu)
		await get_tree().process_frame
		var button: Button = menu.get_node_or_null("CenterContainer/VBoxContainer/MovementLabButton") as Button
		if button == null:
			failures.append("MOVEMENT LAB button missing on main menu")
		elif button.text.find("MOVEMENT LAB") < 0:
			failures.append("MOVEMENT LAB button label unexpected: %s" % button.text)
		else:
			print("menu button ok: %s" % button.text)
		menu.queue_free()
		await get_tree().process_frame

	var lab_packed: PackedScene = load(LAB_SCENE) as PackedScene
	if lab_packed == null:
		failures.append("failed to load movement lab scene")
	else:
		var lab: RtsMovementLab = lab_packed.instantiate() as RtsMovementLab
		add_child(lab)
		await get_tree().process_frame
		await get_tree().process_frame
		if lab.units.size() != RtsMovementLab.UNIT_COUNT:
			failures.append("expected %d lab units, got %d" % [RtsMovementLab.UNIT_COUNT, lab.units.size()])
		var nav_agents: Array = lab.find_children("*", "NavigationAgent3D", true, false)
		if not nav_agents.is_empty():
			failures.append("lab has NavigationAgent3D count=%d" % nav_agents.size())
		else:
			print("NavigationAgent3D count on lab units/tree: 0")
		if lab.get_node_or_null("Obstacles") == null:
			failures.append("lab Obstacles root missing")
		var status: Dictionary = lab.issue_group_move(Vector3(28.0, 0.0, 0.0))
		if not bool(status.get("route_exists", false)):
			failures.append("RMB-equivalent group move did not create a route")
		if int(status.get("path_calculations_this_command", 0)) != 1:
			failures.append("expected one shared path calculation")
		print("lab status after move: units=%s arrived=%s path_calc=%s" % [
			status.get("units", -1),
			status.get("arrived", -1),
			status.get("path_calculations_this_command", -1),
		])
		lab.queue_free()
		await get_tree().process_frame

	var report: String
	if failures.is_empty():
		report = "PASS menu_movement_lab_access\n"
	else:
		report = "FAIL menu_movement_lab_access\n" + "\n".join(failures) + "\n"
	print(report)
	await get_tree().process_frame
	get_tree().quit(0 if failures.is_empty() else 1)
