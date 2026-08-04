class_name MilitaryAIConfig
extends RefCounted

## Feature toggle for the Military AI V2 stack.
## When false, legacy military AI runs unchanged.
## When true, legacy military decision-makers and main-army order issuers
## must not run; economy / production AI remains active.

const USE_MILITARY_AI_V2: bool = false


static func is_v2_enabled() -> bool:
	return USE_MILITARY_AI_V2


static func ai_version_label() -> String:
	return "V2" if USE_MILITARY_AI_V2 else "Legacy"
