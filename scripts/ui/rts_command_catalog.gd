class_name RtsCommandCatalog
extends RefCounted

## Modular catalog of player unit command-panel entries.
## Add new commands here; the HUD binds buttons/hotkeys from these definitions.

const ID_STOP := &"stop"
const ID_HOLD_POSITION := &"hold_position"
const ID_PATROL := &"patrol"
const ID_ATTACK_MOVE := &"attack_move"

const HOTKEY_STOP := KEY_S
const HOTKEY_HOLD := KEY_H
const HOTKEY_PATROL := KEY_P
const HOTKEY_ATTACK_MOVE := KEY_A


static func unit_command_definitions() -> Array[Dictionary]:
	return [
		{
			"id": ID_STOP,
			"label": "Stop",
			"hotkey": HOTKEY_STOP,
			"hotkey_label": "S",
			"tooltip": "Stop (S)\nCancel movement, combat, and queued orders.",
			"requires_combat": false,
			"placeholder_icon_text": "S",
		},
		{
			"id": ID_HOLD_POSITION,
			"label": "Hold",
			"hotkey": HOTKEY_HOLD,
			"hotkey_label": "H",
			"tooltip": "Hold Position (H)\nStay near this spot and attack enemies in range without chasing.",
			"requires_combat": true,
			"placeholder_icon_text": "H",
		},
		{
			"id": ID_PATROL,
			"label": "Patrol",
			"hotkey": HOTKEY_PATROL,
			"hotkey_label": "P",
			"tooltip": "Patrol (P)\nClick ground to patrol. Shift-click adds waypoints. Engages enemies en route.",
			"requires_combat": true,
			"placeholder_icon_text": "P",
		},
		{
			"id": ID_ATTACK_MOVE,
			"label": "Attack",
			"hotkey": HOTKEY_ATTACK_MOVE,
			"hotkey_label": "A",
			"tooltip": "Attack / Attack-Move (A)\nClick ground to attack-move, or right-click an enemy to attack.",
			"requires_combat": true,
			"placeholder_icon_text": "A",
		},
	]


static func definition_for(command_id: StringName) -> Dictionary:
	for definition: Dictionary in unit_command_definitions():
		if definition.get("id", &"") == command_id:
			return definition
	return {}
