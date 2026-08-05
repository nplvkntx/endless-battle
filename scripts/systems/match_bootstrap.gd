extends Node3D

## Match scene bootstrap. MatchCompositionRoot (MatchSystems) owns AI wiring;
## this node only guarantees MatchSession wipe before gameplay ticks.


func _ready() -> void:
	MatchSession.prepare_new_match()
