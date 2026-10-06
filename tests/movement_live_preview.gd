extends SceneTree
## Actual moving actors and contact controllers; use --fixed-fps 30 with
## --write-movie and --movement-world=<id>. Combat is held for this close view.
class Caption extends Node2D:
	var title := ""
	func _draw() -> void:
		draw_rect(Rect2(0,0,1600,66),Color("101917"))
		Art.text(self,Vector2(24,28),title,21)
		Art.text(self,Vector2(24,52),"Echte Laufanimationen und Bodenkontakte · vorbereitete Spielsituation · 1440 × 900",12,Color("a9b8ad"))
var game
var worker: Worker
var enemy: SiegeMachine
var center := Vector2(1100,430)
var elapsed := 0.0
var recording := false
var world := "ash_foundry"

func _initialize() -> void: run.call_deferred()
func run() -> void:
	if DisplayServer.get_name()=="headless" or "--no-profile-save" not in OS.get_cmdline_user_args():
		quit(1)
		return
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1440,900)
	for frame in 120:
		await RenderingServer.frame_post_draw
		if root.get_texture().get_image().get_size()==Vector2i(1440,900): break
	if root.get_texture().get_image().get_size()!=Vector2i(1440,900):
		push_error("Movement movie needs native 1440x900; use movement_frame_benchmark for native QHD")
		quit(1)
		return
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--movement-world="): world = argument.trim_prefix("--movement-world=")
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.start_scenario(1,{"environment":world,"position":"left","build_type":"bastion"})
	game.rounds.running = false
	game.rounds.set_process(false)
	game.set_process(false)
	game.audio.settings_path = "user://movement-capture.cfg"
	game.audio.set_music_volume(0)
	game.audio.set_sfx_volume(.8)
	game.weather.lightning_enabled = false
	game.hud.canvas.hide()
	for frame in 6: await physics_frame
	if world in ["frozen_rail_yard","flooded_power_station"]:
		for field in game.weather.surface_effects.ground.fields:
			if field.point.x>900 and field.point.x<1370:
				center = field.point
				break
	worker = game.players[0]
	worker.set_physics_process(false)
	worker.position = center
	worker._airborne = false
	worker._landing_time = 0
	worker.wetness._last_position = worker.position
	enemy = game._entity("enemy",center+Vector2(165,0),{"kind":"colossus","wave":1})
	enemy.set_physics_process(false)
	enemy.show_status_labels = false
	enemy.moving = true
	game.camera.position = center+Vector2(80,-115)
	game.camera.zoom = Vector2.ONE*1.9
	game.camera.reset_smoothing()
	game.camera.force_update_scroll()
	var overlay := CanvasLayer.new()
	var caption := Caption.new()
	caption.title = {"ash_foundry":"LAUFEN / STAUB UND MASCHINENGEWICHT","flooded_power_station":"LAUFEN / PFÜTZEN UND WASSERSPRITZER","frozen_rail_yard":"LAUFEN / EIS UND SCHNEEGRIES"}.get(world,world)
	overlay.layer = 110
	overlay.add_child(caption)
	game.add_child(overlay)
	await process_frame
	recording = true

func _process(delta: float) -> bool:
	if not recording: return false
	elapsed += delta
	worker.position = center+Vector2(sin(elapsed*1.1)*52,0)
	worker.velocity = Vector2(cos(elapsed*1.1)*57.2,0)
	worker.facing = signf(worker.velocity.x)
	enemy.position = center+Vector2(165+sin(elapsed*.8)*48,0)
	enemy.attack_direction = signf(cos(elapsed*.8))
	enemy.age += delta
	enemy.gait += delta*float(enemy.profile.gait)
	enemy.locomotion_speed = absf(cos(elapsed*.8)*38.4)
	enemy._pose_parts()
	for part in [enemy.body_part,enemy.legs_part,enemy.weapon_part]: part.queue_redraw()
	if elapsed>=6.0:
		recording = false
		finish.call_deferred()
	return false

func finish() -> void:
	print("MOVEMENT PREVIEW: ",world," player contacts=",worker.wetness.steps_emitted," machine contacts=",enemy.wetness.steps_emitted," spatial sounds=",game.audio.movement.steps_played)
	var ok: bool = worker.wetness.steps_emitted>3 and enemy.wetness.steps_emitted>3
	await preload("res://tests/scene_cleanup.gd").free_scene(game,self)
	quit(0 if ok else 1)
