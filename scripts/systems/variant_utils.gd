class_name VariantUtils
extends RefCounted

## Safe Variant-to-bool conversion for config dictionaries, Callable.call results,
## and mixed settings values. Never throws; unsupported types return default_value.
static func to_bool(value: Variant, default_value: bool = false) -> bool:
	if value == null:
		return default_value

	match typeof(value):
		TYPE_BOOL:
			return value
		TYPE_INT:
			return value != 0
		TYPE_FLOAT:
			return absf(value) > 0.000001
		TYPE_STRING, TYPE_STRING_NAME:
			var normalized := String(value).strip_edges().to_lower()
			if normalized in ["true", "1", "yes", "on"]:
				return true
			if normalized in ["false", "0", "no", "off", ""]:
				return false
			return default_value
		_:
			return default_value
