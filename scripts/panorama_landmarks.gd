extends RefCounted
## Source-pixel annotations share one versioned image reference across effects.
static var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/environments/v3/landmarks.json"))

static func entry(environment: String) -> Dictionary:
	return data.environments.get(environment, {})
