extends RefCounted
## Keep lightweight gameplay test doubles compatible with the world audio API.
static func emit(game: Node,kind: String,at: Vector2) -> void:
	if not is_instance_valid(game) or not at.is_finite(): return
	if game.has_method("sound_at"): game.sound_at(kind,at)
	elif game.has_method("sound"): game.sound(kind)
