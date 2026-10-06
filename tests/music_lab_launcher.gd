extends SceneTree
## Standalone interactive developer lab: no saved game or multiplayer session.
func _initialize() -> void:
	_open.call_deferred()

func _open() -> void:
	InputSetup.install()
	root.size=Vector2i(1440,900)
	var lab = preload("res://scripts/music_dev_dashboard.gd").new()
	root.add_child(lab)
	lab.closed.connect(func(): quit())
