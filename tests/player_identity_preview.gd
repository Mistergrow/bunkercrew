extends "res://scripts/game.gd"
## Prepared real scene for MCP: normal camera, two workers, no wave progression.
@export var second_character := "branko"

func _ready() -> void:
	super._ready()
	selected_characters[0] = "mara"
	selected_characters[1] = second_character
	start_scenario(2,{"environment":"sector07","build_type":"bastion","position":"left"})
	rounds.set_process(false)
	rounds.running = false
	notice = ""
	notice_time = 0
	camera.position = camera_target_center
	camera.zoom = Vector2.ONE*camera_target_zoom
	for index in players.size():
		players[index].position = Vector2(805+index*110,430)
		players[index].set_physics_process(false)
