class_name TrainingConfig
extends RefCounted

## Shared military unit training time calculations.


static func get_train_seconds(base_seconds: float, speed_multiplier: float = 1.0) -> float:
	return base_seconds / maxf(speed_multiplier, 0.01)


static func get_player_military_train_seconds(base_seconds: float) -> float:
	var speed_multiplier: float = 1.0
	if UpgradeManager.has_faster_unit_training(false):
		speed_multiplier = UpgradeManager.FASTER_UNIT_TRAINING_SPEED_MULTIPLIER
	return get_train_seconds(base_seconds, speed_multiplier)
