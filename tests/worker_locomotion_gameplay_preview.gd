extends SceneTree
## Real input, CharacterBody physics, supported footsteps and roof ray probes.
## Prepared solo ash_foundry scene with a temporary 42px test tunnel. Waves
## stopped, camera at 2.2; movement/jump are not manually posed or advanced.
const CLEANUP := preload("res://tests/scene_cleanup.gd")
var game: Node

class Tunnel extends Node2D:
	func _draw() -> void:
		draw_rect(Rect2(1050,382,250,6),Color("303c3c"))
		draw_line(Vector2(1050,382),Vector2(1300,382),Color("a1a489"),1)
		draw_line(Vector2(1050,388),Vector2(1300,388),Color("171e20"),2)
		for x in [1054, 1296]:
			# Painted rear braces have no invisible movement collision.
			draw_rect(Rect2(x,388,4,42),Color("45514d"))
			for y in [394,422]: draw_rect(Rect2(x+1,y,2,2),Color("a6ab91"))

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if DisplayServer.get_name()=="headless":
		push_error("Gameplay capture requires a graphical display")
		quit(1)
		return
	Engine.max_fps=60
	root.size=Vector2i(1440,900)
	game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene=game
	game.start_scenario(1,{"environment":"ash_foundry","build_type":"bastion","position":"left"})
	game.rounds.set_process(false)
	game.player_camera.mode="follow"
	game.player_camera._save_delay=-1.0
	game.player_camera.view_zoom=2.2
	var actor: Worker=game.players[0]
	actor.global_position=Vector2(850,430)
	actor.velocity=Vector2.ZERO
	game.add_terrain(Rect2(1050,382,250,6))
	var tunnel := Tunnel.new()
	tunnel.z_index=4
	game.add_child(tunnel)
	for frame in 4: await physics_frame
	game.player_camera.update_view(1,true)
	var directory := "res://artifacts/worker-locomotion/gameplay-frames"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var observed: Dictionary={}
	var sounds_before: int=game.audio.movement.steps_played
	for frame in 420:
		if frame==24: Input.action_press("p1_right")
		if frame==162: Input.action_release("p1_right")
		if frame==174: Input.action_press("p1_left")
		if frame==312: Input.action_release("p1_left")
		if frame==324:
			Input.action_press("p1_right")
			Input.action_press("p1_jump")
		if frame==334: Input.action_release("p1_jump")
		if frame==395: Input.action_release("p1_right")
		await process_frame
		await RenderingServer.frame_post_draw
		var visual: WorkerVisual=actor.get_node("PixelVisual")
		observed[visual.pose_name]=true
		observed[visual.locomotion.kind]=true
		var capture := root.get_texture().get_image()
		capture.save_png(directory+"/%04d.png"%frame)
		if frame in [74, 112, 224, 350, 377]: capture.save_png("res://artifacts/worker-locomotion/gameplay-%04d.png"%frame)
	Input.action_release("p1_right")
	Input.action_release("p1_left")
	Input.action_release("p1_jump")
	var steps: int=game.audio.movement.steps_played-sounds_before
	var valid: bool=observed.has("run") and observed.has("crawl") and observed.has("jump_up") and observed.has("fall") and steps>5
	print("LOCOMOTION GAMEPLAY: actual input and physics; observed ",observed.keys(),"; supported footstep sounds ",steps,"; pass=",valid)
	await CLEANUP.free_scene(game,self)
	quit(0 if valid else 1)
