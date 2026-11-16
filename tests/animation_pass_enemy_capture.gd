extends SceneTree
## Prepared motion study for every ground enemy class: walk, stop, hit, wind-up,
## shot, restart and defeat on a ruled floor. Real scenes and drawing delegates;
## the stepping below repeats the movement/timer lines of SiegeMachine so the
## floor ticks show actual world travel. Presentation fixture, not a playthrough.
## Usage: godot --path . --script tests/animation_pass_enemy_capture.gd -- --no-profile-save --no-upnp --label=before [--direction=1] [--reduced]
const Cleanup := preload("res://tests/scene_cleanup.gd")
const CELL := Vector2(320,300)
const COLUMNS := 6
const STEP := 1.0/60.0
class WeatherProbe extends RefCounted:
	var reduced_effects := false
class Stage extends Node2D:
	var weather := WeatherProbe.new()
	var kinds: Array[String] = []
	var stats := {}
	func fx(_at: Vector2, _color: Color, _count: int = 0) -> void: pass
	func spawn_pickup(_kind: String, _amount: int, _at: Vector2) -> void: pass
	func sound(_name: String, _at: Variant = null, _gain: Variant = null) -> void: pass
	func _draw() -> void:
		draw_rect(Rect2(0,0,1920,1200),Color("121a18"))
		for index in kinds.size():
			var origin := Vector2(index%COLUMNS,floori(float(index)/COLUMNS))*CELL
			var floor_y := origin.y+CELL.y-40.0
			draw_rect(Rect2(origin.x,floor_y,CELL.x,2),Color("46544c"))
			for tick in range(0,int(CELL.x),8):
				draw_rect(Rect2(origin.x+tick,floor_y+2,1,6 if tick%32==0 else 3),Color("7d8a7c"))
			draw_rect(Rect2(origin.x,origin.y,1,CELL.y),Color("22302b"))
var stage: Stage
var actors: Array[Node2D] = []
var fired: Array[bool] = []
func _initialize() -> void: call_deferred("run")
func run() -> void:
	ThemeDB.fallback_font = load("res://assets/mono.ttf")
	root.content_scale_size = Vector2i(1920,1200)
	root.size = Vector2i(1920,1200)
	var label := "capture"
	var direction := -1.0
	var reduced := false
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--label="): label = argument.trim_prefix("--label=")
		if argument.begins_with("--direction="): direction = signf(float(argument.trim_prefix("--direction=")))
		if argument == "--reduced": reduced = true
	stage = Stage.new()
	stage.weather.reduced_effects = reduced
	stage.kinds.assign(EnemyCatalog.GROUND_CLASSES)
	root.add_child(stage)
	var directory := "res://artifacts/visual-pass-animation/enemies-%s" % label
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory+"/frames"))
	for index in stage.kinds.size():
		var kind := stage.kinds[index]
		var origin := Vector2(index%COLUMNS,floori(float(index)/COLUMNS))*CELL
		var actor = load("res://scenes/ground_infantry.tscn" if EnemyCatalog.is_human(kind) else "res://scenes/enemy.tscn").instantiate()
		actor.kind = kind
		actor.game = stage
		actor.show_status_labels = false
		actor.attack_direction = direction
		if EnemyCatalog.is_human(kind): actor.squad_slot = index%3
		actor.position = origin+Vector2(CELL.x*0.5-direction*70.0,CELL.y-40.0)
		stage.add_child(actor)
		actor.set_physics_process(false)
		actor.set_process(false)
		actor.motion.set_process(false)
		if "infantry" in actor and is_instance_valid(actor.infantry): actor.infantry.set_process(false)
		var aim := Node2D.new()
		aim.position = actor.position+Vector2(direction*400.0,0)
		stage.add_child(aim)
		actor.target = aim
		actors.append(actor)
		fired.append(false)
	var frame := 0
	for tick in 570:
		var time := tick*STEP
		for index in actors.size():
			var actor = actors[index]
			if not is_instance_valid(actor) or actor.dead: continue
			if time>=7.5:
				actor.die()
				continue
			_step(actor,index,time)
		for wreck in get_nodes_in_group("enemy_motion_wrecks"):
			wreck.set_process(false)
			if not wreck.is_queued_for_deletion(): wreck._process(STEP)
		for remains in get_nodes_in_group("infantry_remains"):
			remains.set_process(false)
			if not remains.is_queued_for_deletion(): remains._process(STEP)
		if tick%2==1:
			stage.queue_redraw()
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(directory+"/frames/%04d.png" % frame)
			frame += 1
	var output := FileAccess.open(directory+"/capture.json",FileAccess.WRITE)
	output.store_string(JSON.stringify({"prepared":true,"kinds":stage.kinds,"fps":30,"cell":[CELL.x,CELL.y],"columns":COLUMNS,"direction":direction,"reduced_effects":reduced,"timeline":{"walk":[0,2.5],"stop":[2.5,3.5],"hit":3.5,"windup_from":4.0,"walk_again":[6.5,7.5],"defeat":7.5}},"\t"))
	output.close()
	print("ANIMATION PASS ENEMY CAPTURE label=",label," frames=",frame)
	var clean := await Cleanup.free_scene(stage,self)
	quit(0 if clean else 1)

func _step(actor, index: int, time: float) -> void:
	var profile: Dictionary = actor.profile
	actor.age += STEP
	actor.hit_flash = maxf(0,actor.hit_flash-STEP)
	actor.stagger = maxf(0,actor.stagger-STEP)
	actor.muzzle_flash = maxf(0,actor.muzzle_flash-STEP)
	actor.weapon_recoil = move_toward(actor.weapon_recoil,0,STEP*(12 if actor.chassis_kind()=="siege" else 24))
	var walking := time<2.5 or (time>=6.5 and time<7.5)
	actor.moving = walking
	if walking:
		var desired: float = actor.move_speed*(0.3 if actor.stagger>0 else 1.0)
		actor.locomotion_speed = move_toward(actor.locomotion_speed,desired,actor.move_speed*STEP*3.6)
		actor.position.x += actor.attack_direction*actor.locomotion_speed*STEP
		actor.gait += STEP*float(profile.gait)*clampf(actor.locomotion_speed/actor.move_speed,0.3,1.0)
	else:
		actor.locomotion_speed = move_toward(actor.locomotion_speed,0,actor.move_speed*STEP*4)
		actor.gait = move_toward(actor.gait,roundf(actor.gait/PI)*PI,STEP*5)
	if absf(time-3.5)<STEP*0.5:
		actor.hp = actor.max_hp*0.7
		actor.hit_flash = 0.2
		actor.stagger = 0.16
	if time>=4.0 and not fired[index]:
		actor.windup += STEP
		if actor.windup>=float(profile.windup):
			fired[index] = true
			actor.windup = 0
			actor.attack_count += 1
			actor.tracer_end = Vector2(actor.attack_direction*150.0,-30)
			actor.weapon_recoil = (11.0 if actor.chassis_kind()=="siege" else (3.0 if actor.chassis_kind()=="assault" else 5.0))*actor.visual_scale
			actor.muzzle_flash = 0.19 if actor.chassis_kind()=="siege" else 0.09
	if "stance" in actor:
		actor.stance = move_toward(actor.stance,0.0 if actor.moving else 1.0,STEP*3.8)
	actor.motion._process(STEP)
	actor._pose_parts()
	for child in actor.get_children():
		if child is CanvasItem: child.queue_redraw()
	if is_instance_valid(actor.variant_visual): actor.variant_visual.queue_redraw()
	actor.queue_redraw()
