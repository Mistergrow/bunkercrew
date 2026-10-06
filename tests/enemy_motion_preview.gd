extends SceneTree
## Prepared performance gallery using real scenes, drawing delegates and runtime
## motion clocks. Normal timing, native size and 2x, all seven new performances.
const Pose := preload("res://scripts/enemy_motion_pose.gd")
const Cleanup := preload("res://tests/scene_cleanup.gd")
const FPS := 30
const HOLD := 2.4
class Gallery extends Node2D:
	var kinds: Array[String] = []
	var stage := "deploy"
	var clock := 0.0
	var page := 0
	var preview_duration := HOLD*7
	func _draw() -> void:
		draw_rect(Rect2(0,0,1920,1200),Color("111917"))
		Art.text(self,Vector2(56,60),"MASCHINEN / BEWEGUNGSSTUDIEN",30,Color("e3e0d1"))
		Art.text(self,Vector2(56,97),"%02d / 07   %s" % [Pose.STATES.find(stage)+1,Pose.LABELS[stage]],20,Color("d7ad72"))
		Art.text(self,Vector2(1470,62),"NATIV   +   2x",18,Color("939c92"))
		Art.text(self,Vector2(1470,94),"%.1f s / %.1f s" % [clock,preview_duration],15,Color("939c92"))
		for row in kinds.size():
			var y := 410.0+row*350.0
			var label := "MUTTERMASCHINE" if kinds[row]=="boss" else str(EnemyCatalog.profile(kinds[row]).label)
			Art.text(self,Vector2(56,y-237),label,22,Color("dddccb"))
			Art.text(self,Vector2(56,y-209),kinds[row],14,Color("929b91"))
			Art.text(self,Vector2(302,y+30),"Originalgroesse",14,Color("929b91"))
			Art.text(self,Vector2(1120,y+30),"2x · gleiche Bewegung",14,Color("929b91"))
			if not AirEnemyCatalog.is_air(kinds[row]):
				draw_line(Vector2(260,y),Vector2(1580,y),Color("3b4841"),2)
			else:
				for x in range(270,1580,22): draw_line(Vector2(x,y),Vector2(x+8,y),Color("26372f"),1)
		Art.text(self,Vector2(56,1180),"Vorbereitete Ausloeser · echte Laufzeit-Rigs · normale Geschwindigkeit · 30 Bilder/s · Seite %d/7" % [page+1],15,Color("929b91"))
var gallery: Gallery
var actors: Array[Node2D] = []
func _initialize() -> void: call_deferred("run")
func run() -> void:
	ThemeDB.fallback_font = load("res://assets/mono.ttf")
	root.content_scale_size = Vector2i(1920,1200)
	root.size = Vector2i(1920,1200)
	var page := 0
	var stills_only := "--stills" in OS.get_cmdline_user_args()
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--page="): page = clampi(int(argument.trim_prefix("--page=")),0,6)
	var all_kinds: Array[String] = EnemyCatalog.CLASS_ORDER.filter(func(kind):return not EnemyCatalog.is_human(kind))
	all_kinds.append("boss")
	gallery = Gallery.new()
	gallery.page = page
	gallery.preview_duration = 4.2 if stills_only else HOLD*7
	for index in range(page*3,mini(page*3+3,all_kinds.size())): gallery.kinds.append(all_kinds[index])
	root.add_child(gallery)
	var directory := "res://artifacts/enemy-motion/page-%02d" % [page+1]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory+"/frames"))
	for row in gallery.kinds.size():
		for magnification in 2:
			var kind := gallery.kinds[row]
			var flying := AirEnemyCatalog.is_air(kind)
			var path := "res://scenes/boss_enemy.tscn" if kind=="boss" else ("res://scenes/air_enemy.tscn" if flying else "res://scenes/enemy.tscn")
			var actor = load(path).instantiate()
			actor.kind = "siege" if kind=="boss" else kind
			actor.show_status_labels = false
			gallery.add_child(actor)
			actor.position = Vector2(355 if magnification==0 else 1200,410+row*350-(150 if flying else 0))
			actor.scale = Vector2.ONE*(1.0 if magnification==0 else 2.0)
			actor.set_physics_process(false)
			actor.set_process(false)
			actor.motion.set_process(false)
			actor.motion.automatic = false
			actors.append(actor)
	var frame := 0
	var metadata := {"prepared":true,"page":page+1,"figures":gallery.kinds,"additional_states":Pose.STATES,"fps":FPS,"scales":[1,2],"stage_seconds":0.6 if stills_only else HOLD,"stills_only":stills_only,"notes":"Real scenes and controller pose evaluation; actions selected explicitly for inspection. Death calls the real die() lifecycle. Combat triggers covered separately by enemy_motion_test.gd."}
	for action in Pose.STATES:
		gallery.stage = action
		for actor in actors:
			if action=="destroy": actor.die()
			else: actor.motion.play(action,true)
		for wreck in get_nodes_in_group("enemy_motion_wrecks"): wreck.set_process(false)
		for local_frame in (18 if stills_only else int(HOLD*FPS)):
			for wreck in get_nodes_in_group("enemy_motion_wrecks"):
				if not wreck.is_queued_for_deletion(): wreck._process(1.0/FPS)
			gallery.clock = float(frame)/FPS
			for actor in actors:
				if not is_instance_valid(actor) or actor.dead: continue
				actor.age += 1.0/FPS
				actor.motion.advance(1.0/FPS)
				actor._pose_parts()
				for child in actor.get_children():
					if child is CanvasItem: child.queue_redraw()
				actor.queue_redraw()
			gallery.queue_redraw()
			await process_frame
			await RenderingServer.frame_post_draw
			var capture := root.get_texture().get_image()
			if not stills_only: capture.save_jpg(directory+"/frames/%05d.jpg" % frame,0.95)
			if local_frame==14: capture.save_png(directory+"/"+action+".png")
			frame += 1
	var output := FileAccess.open(directory+"/review.json",FileAccess.WRITE)
	output.store_string(JSON.stringify(metadata,"\t"))
	output.close()
	print("ENEMY MOTION CAPTURE page=",page+1," frames=",frame," figures=",gallery.kinds)
	var clean := await Cleanup.free_scene(gallery,self)
	quit(0 if clean else 1)
