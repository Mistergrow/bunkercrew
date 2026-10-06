extends SceneTree
## Real follow-camera projection; positions are prepared to exercise each edge.
const ObjectivePanel:=preload("res://scripts/story_objective_panel.gd")
const Cleanup:=preload("res://tests/scene_cleanup.gd")
var checks:=0
var failures:=0
func _initialize() -> void: run.call_deferred()
func check(value: bool,label: String) -> void:
	checks+=1
	if not value: failures+=1; push_error(label)
func run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args(): quit(2); return
	var game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.story_mode=true
	game.start_scenario(1,{"environment":"mountain_pass","position":"center","build_type":"bastion"})
	game.rounds.set_process(false)
	game.players[0].set_physics_process(false)
	var target: Vector2=game.story.target_position()
	check(target.is_finite(),"Story has a real construction target")
	for zoom in [1.8,2.5]:
		game.set_camera_zoom(zoom)
		for direction in [Vector2.LEFT,Vector2.RIGHT,Vector2.UP,Vector2.DOWN]:
			game.players[0].global_position=target-direction*700.0+Vector2(-60,95)
			game.player_camera.update_view(0,true)
			var projected: Vector2=game.hud.world_to_ui(target)
			var marker:=ObjectivePanel.marker_layout(projected)
			check(marker.offscreen,"High-zoom objective uses an edge cue")
			check(marker.direction.dot(direction)>.99,"Edge cue points toward the true objective")
			check(Rect2(27,219,1386,482).has_point(marker.point),"Edge cue stays in the safe HUD area")
			check(Rect2(20,210,1400,500).has_point(marker.label),"Objective label stays readable inside the screen")
	var inside:=Vector2(810,490)
	var anchored:=ObjectivePanel.marker_layout(inside)
	check(not anchored.offscreen and anchored.point==inside,"Visible objective remains anchored to the object")
	var diagonal:=ObjectivePanel.marker_layout(Vector2(-500,-500))
	check(diagonal.offscreen and diagonal.direction.x<0 and diagonal.direction.y<0,"Corner cue preserves both direction components")
	var radio_safe:=Rect2(28,220,1384,360)
	var below:=ObjectivePanel.marker_layout(Vector2(720,1600),radio_safe)
	check(below.point.y==580 and below.label.y<580,"Lower edge can reserve the visible radio subtitle area")
	await Cleanup.free_scene(game,self)
	print("Story objective markers: %d/%d checks passed"%[checks-failures,checks])
	quit(1 if failures else 0)
