extends SceneTree
## Arranged runtime comparison at native game size plus enlarged details.
## Optional --video saves 180 frames at deterministic 30 fps for ffmpeg.

class Gallery extends Node2D:
	var actors: Array[Worker] = []
	var elapsed := 0.0
	var kinds := ["idle","walk","mine","climb","guard","downed"]
	func _draw() -> void:
		draw_rect(Rect2(0,0,1440,900),Color("121b1e"))
		Art.text(self,Vector2(26,38),"MARA / BRANKO / IVO — DREI EIGENE FIGUREN",24,Art.LIGHT)
		Art.text(self,Vector2(27,66),"Echte Laufzeitgrafik · normale Spielgröße oben · vergrößerte Animationen und medizinische Posen darunter",12,Art.MUTED)
		for column in 3:
			var x := 24+column*472
			draw_rect(Rect2(x,87,452,783),Color("293331"))
			draw_rect(Rect2(x+2,89,448,779),Color("1b2628"))
			var entry: Dictionary = CharacterCatalog.CHARACTERS[column]
			Art.text(self,Vector2(x+18,118),entry.title,24,Color(entry.accent))
			Art.text(self,Vector2(x+18,143),entry.detail,12,Art.MUTED)
			Art.text(self,Vector2(x+18,170),"NORMALGRÖSSE   1×",11,Art.MUTED)
			Art.text(self,Vector2(x+240,170),"DETAIL   2×",11,Art.MUTED)
			for row in 3:
				for col in 2:
					var index := row*2+col
					var px := x+15+col*219
					var py := 337+row*174
					draw_rect(Rect2(px,py,204,164),Color("111d20"))
					Art.text(self,Vector2(px+10,py+23),["RUHE","GEHEN","ABBAU","LEITER","VERLETZT","BEWUSSTLOS"][index],11,Art.MUTED)
					draw_line(Vector2(px+8,py+139),Vector2(px+196,py+139),Color("7c8270"),2)
	func advance(delta: float) -> void:
		elapsed += delta
		for index in actors.size():
			var actor: Worker = actors[index]
			var visual: WorkerVisual = actor.get_node("PixelVisual")
			var local_index := index%8
			var kind: String = "idle" if local_index<2 else kinds[local_index-2]
			visual.pose_name = kind if kind in ["idle","walk","mine","climb"] else "idle"
			visual.pose_frame = int(elapsed*(12.8 if kind=="mine" else (9.0 if kind in ["walk","climb"] else 3.0)))%int(visual._frames[visual.pose_name].frames)
			visual.special_pose = kind if kind in ["guard","downed"] else ""
			visual.pose_skeleton = WorkerPoseArt.sample(kind,1.0) if not visual.special_pose.is_empty() else {}
			visual.queue_redraw()
		queue_redraw()

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if DisplayServer.get_name()=="headless":
		push_error("Character gallery needs a display")
		quit(1)
		return
	InputSetup.install()
	root.size = Vector2i(1440,900)
	var gallery := Gallery.new()
	root.add_child(gallery)
	for column in 3:
		for index in 8:
			var actor := Worker.new()
			actor.character_id = CharacterCatalog.CHARACTERS[column].id
			actor.player_id = 1 if column!=1 else 2
			var x := 24+column*472
			if index==0: actor.position = Vector2(x+111,288)
			elif index==1:
				actor.position = Vector2(x+337,313)
				actor.scale = Vector2.ONE*2
			else:
				actor.position = Vector2(x+115+((index-2)%2)*219,475+floori(float(index-2)/2)*174)
				actor.scale = Vector2.ONE*1.55
			gallery.add_child(actor)
			actor.set_physics_process(false)
			var visual := WorkerVisual.new()
			visual.name = "PixelVisual"
			actor.add_child(visual)
			visual.set_process(false)
			visual.set_physics_process(false)
			visual._identity.hide()
			gallery.actors.append(actor)
	var video := "--video" in OS.get_cmdline_user_args()
	var directory := "res://artifacts/character-identities"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory+"/frames"))
	for frame in 180 if video else 2:
		gallery.advance(1.0/30.0)
		await process_frame
		await RenderingServer.frame_post_draw
		var capture := root.get_texture().get_image()
		if video: capture.save_png(directory+"/frames/%03d.png"%frame)
		if frame==1: capture.save_png(directory+"/runtime-gallery.png")
	print("CHARACTER GALLERY: actual identity atlases and articulated medical poses; arranged fixture")
	await preload("res://tests/scene_cleanup.gd").free_scene(gallery,self)
	quit()
