class_name MilitaryAIConfig
extends RefCounted

## SimpleWc3AI is the sole enemy decision authority. No legacy/V2 toggles.

static func is_simple_wc3_ai_enabled() -> bool:
	return true


static func is_v2_enabled() -> bool:
	return false


static func is_v2_runtime_active() -> bool:
	return false


static func is_legacy_military_suspended() -> bool:
	return true


static func ai_version_label() -> String:
	return "SimpleWC3"
