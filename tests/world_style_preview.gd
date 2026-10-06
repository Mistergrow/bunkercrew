extends "res://scripts/game.gd"
## Saved preview scene for MCP dev_render. Prepared start; waves stay disabled.
@export var preview_environment := "ash_foundry"

func _ready() -> void:
	super._ready()
	start_scenario(1, {"environment":preview_environment, "build_type":"bastion", "position":"left"})
	rounds.set_process(false)
	notice = ""
	notice_time = 0
	camera.position = camera_target_center
	camera.zoom = Vector2.ONE*camera_target_zoom
