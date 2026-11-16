extends SceneTree
## Prepared study of aircraft defeats over a solid floor: every class is shot
## down in level flight and its detached wreck falls, tumbles, trails smoke,
## crashes and dissolves. The aircraft are frozen fixtures (no flight logic);
## only the wreck and its local blast run. Presentation fixture, not a playthrough.
## Usage: godot --path . --script tests/animation_pass2_air_crash_capture.gd -- --no-profile-save --no-upnp --label=after [--reduced] [--only=scout_drone,gunship]
const Cleanup := preload("res://tests/scene_cleanup.gd")
const STEP := 1.0/60.0
const FLOOR := 520.0
class WeatherProbe extends RefCounted:
	var reduced_effects := false
class Stage extends Node2D:
	var weather := WeatherProbe.new()
	var stats := {"kills":0}
	func fx(_at: Vector2, _color: Color, _count: int = 0) -> void: pass
	func spawn_pickup(_kind: String, _amount: int, _at: Vector2) -> void: pass
	func sound(_name: String, _at: Variant = null, _gain: Variant = null) -> void: pass
	func _draw() -> void:
		draw_rect(Rect2(0,0,1920,1200),Color("26343c"))
		draw_rect(Rect2(0,FLOOR,1920,680),Color("3a3a32"))
		draw_rect(Rect2(0,FLOOR,1920,2),Color("8c8a70"))
		for tick in range(0,1920,32): draw_rect(Rect2(tick,FLOOR+2,1,6),Color("6d6c58"))

func _initialize() -> void: call_deferred("run")

func run() -> void:
	ThemeDB.fallback_font = load("res://assets/mono.ttf")
	root.content_scale_size = Vector2i(1920,1200)
	root.size = Vector2i(1920,1200)
	var label := "capture"
	var only: Array[String] = []
	var stage := Stage.new()
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--label="): label = argument.trim_prefix("--label=")
		if argument.begins_with("--only="): only.assign(argument.trim_prefix("--only=").split(","))
		if argument == "--reduced": stage.weather.reduced_effects = true
	root.add_child(stage)
	var floor_body := StaticBody2D.new()
	floor_body.collision_layer = 1
	var shape := CollisionShape2D.new()
	shape.shape = RectangleShape2D.new()
	shape.shape.size = Vector2(4000,200)
	shape.position = Vector2(960,FLOOR+100)
	floor_body.add_child(shape)
	stage.add_child(floor_body)
	var kinds: Array[String] = []
	for kind: String in AirEnemyCatalog.CLASS_ORDER:
		if only.is_empty() or kind in only: kinds.append(kind)
	var directory := "res://artifacts/visual-pass2-anim/air-crash-%s" % label
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory+"/frames"))
	var aircraft: Array[Node2D] = []
	for index in kinds.size():
		var machine = load("res://scenes/air_enemy.tscn").instantiate()
		machine.kind = kinds[index]
		machine.game = stage
		machine.show_status_labels = false
		machine.attack_direction = -1.0
		machine.position = Vector2(160+index*(1600.0/maxf(1,kinds.size()-1)) if kinds.size()>1 else 960.0,180+(index%3)*40)
		stage.add_child(machine)
		aircraft.append(machine)
	await physics_frame
	await physics_frame
	for machine in aircraft:
		machine.set_physics_process(false)
		machine.entered = true
		machine.scenario_floor = FLOOR
		machine.flight_velocity = Vector2(-60.0,8.0)
		machine.motion.set_process(false)
	var frame := 0
	for tick in 200:
		if tick==20:
			for machine in aircraft:
				if is_instance_valid(machine): machine.die()
		for machine in aircraft:
			if is_instance_valid(machine) and not machine.dead:
				machine.age += STEP
				machine._pose_parts()
				for child in machine.get_children():
					if child is CanvasItem: child.queue_redraw()
		for wreck in get_nodes_in_group("enemy_motion_wrecks"):
			wreck.set_process(false)
			if not wreck.is_queued_for_deletion(): wreck._process(STEP)
		await physics_frame
		if tick%2==1:
			stage.queue_redraw()
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(directory+"/frames/%04d.png" % frame)
			frame += 1
	print("AIR CRASH CAPTURE label=",label," frames=",frame)
	var clean := await Cleanup.free_scene(stage,self)
	quit(0 if clean else 1)
