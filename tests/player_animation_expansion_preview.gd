extends SceneTree
## Prepared demonstration, not a live playthrough. Each character uses real
## WorkerVisual instances at native size and 2x. Only idle choice is selected;
## recovery/clear gestures start from actual work and round-state transitions.

const Library := preload("res://scripts/worker_gesture_library.gd")
const Personality := preload("res://scripts/worker_personality.gd")
const IDS := ["mara","branko","ivo"]
const OUTPUT := "res://artifacts/player-animation-expansion/"

class RoundProbe extends Node:
	var phase := "build"

class Gallery extends Node2D:
	var rounds := RoundProbe.new()
	var actors: Array[Worker] = []
	var elapsed := 0.0
	var stage := 0
	var stage_elapsed := 0.0
	var stage_duration := 5.0
	var idle_started := false
	var total_duration := 0.0

	func _ready() -> void:
		add_child(rounds)

	func enter_stage(index: int) -> void:
		stage = index
		stage_elapsed = 0.0
		idle_started = false
		stage_duration = 0.0
		rounds.phase = "attack" if stage==5 else "build"
		for id in IDS:
			stage_duration = maxf(stage_duration,Personality.duration(Library.names(id)[stage])+1.8)
		for actor in actors:
			var visual: WorkerVisual = actor.get_node("PixelVisual")
			actor.mining = false
			visual.idle_clock.cancel()
			visual.idle_clock.wait_remaining = 1000
			visual.expression_clock.reset()
			visual._process(0.0)

	func advance(delta: float) -> void:
		if stage==5 and stage_elapsed>=0.6:
			rounds.phase = "salvage"
		for index in actors.size():
			var actor: Worker = actors[index]
			var visual: WorkerVisual = actor.get_node("PixelVisual")
			var column := floori(float(index)/2.0)
			actor.mining = stage==4 and stage_elapsed<0.8
			if stage<4 and stage_elapsed>=0.6 and not idle_started:
				visual.idle_clock.begin(Library.names(IDS[column])[stage])
			visual._process(delta)
			visual._identity.hide()
		if stage<4 and stage_elapsed>=0.6:
			idle_started = true
		stage_elapsed += delta
		elapsed += delta
		queue_redraw()

	func _draw() -> void:
		draw_rect(Rect2(0,0,1440,900),Color("151b1d"))
		Art.text(self,Vector2(48,55),"NEUE BEWEGUNGEN FÜR DIE CREW",27,Art.LIGHT)
		Art.text(self,Vector2(49,84),"Echte Spielfiguren in vorbereiteten Zuständen · normales Tempo · jede Animation mit eigener Vorbereitung und Rückkehr",12,Art.MUTED)
		for column in 3:
			var x := 48+column*468
			var id: String = IDS[column]
			var entry := CharacterCatalog.data(id)
			var kind := Library.names(id)[stage]
			var info: Dictionary = Library.CATALOG[kind]
			var accent := Color(entry.accent)
			Art.text(self,Vector2(x,151),entry.title,25,accent)
			Art.text(self,Vector2(x,180),["Kontrolliert und aufmerksam","Bedächtig und standfest","Rastlos und erfinderisch"][column],13,Art.MUTED)
			Art.text(self,Vector2(x,229),"SPIELGRÖSSE",11,Art.MUTED)
			draw_line(Vector2(x,335),Vector2(x+391,335),Color("4a5854"),1)
			Art.text(self,Vector2(x,396),"DETAILANSICHT  2×",11,Art.MUTED)
			draw_line(Vector2(x,613),Vector2(x+391,613),Color("4a5854"),1)
			Art.text(self,Vector2(x,671),str(info.label).to_upper(),16,accent)
			Art.text(self,Vector2(x,702),"%.1f Sekunden"%float(info.duration),12,Art.MUTED)
			if column<2:
				draw_line(Vector2(x+427,135),Vector2(x+427,738),Color("293335"),1)
		var trigger: String = ["Ruhe · freie Hände · keine Bedrohung","Nach längerer Arbeit und kurzer Ruhe","Nach abgewehrter Welle bei freier Bewegung"][0 if stage<4 else stage-3]
		Art.text(self,Vector2(49,786),"%d / 6    %s"%[stage+1,trigger],16,Art.LIGHT)
		Art.text(self,Vector2(49,820),"Bewegung, Zielen, Schaden und nahe Gegner brechen diese Gesten sofort ab.",13,Art.MUTED)
		Art.text(self,Vector2(49,850),"Die beiden bisherigen Ruhegesten und alle Bewegungs-, Kampf- und Pflegeanimationen bleiben erhalten.",12,Art.MUTED)
		draw_rect(Rect2(48,881,1343*clampf(stage_elapsed/stage_duration,0,1),2),Art.AMBER)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if DisplayServer.get_name()=="headless":
		push_error("Additional animation capture requires a graphical display")
		quit(1)
		return
	InputSetup.install()
	root.size = Vector2i(1440,900)
	var gallery := Gallery.new()
	root.add_child(gallery)
	for column in 3:
		for size_index in 2:
			var actor := Worker.new()
			actor.game = gallery
			actor.character_id = IDS[column]
			actor.player_id = 1
			actor.position = Vector2(48+column*468+193,331 if size_index==0 else 609)
			actor.scale = Vector2.ONE*(1+size_index)
			gallery.add_child(actor)
			actor.set_physics_process(false)
			var visual := WorkerVisual.new()
			visual.name = "PixelVisual"
			actor.add_child(visual)
			visual.set_process(false)
			visual.set_physics_process(false)
			visual._identity.hide()
			gallery.actors.append(actor)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT+"frames"))
	var capture_metadata := {
		"fixture":"Prepared scene. Six actual WorkerVisuals. Idle choices selected explicitly; recovery and clear start from real work/round transitions. Gameplay simulation disabled.",
		"fps":30,"native_and_double":true,"catalog":Library.CATALOG,"stages":[],
	}
	var frame_number := 0
	for stage in 6:
		gallery.enter_stage(stage)
		var frame_count := ceili(gallery.stage_duration*30)
		capture_metadata.stages.append({"stage":stage+1,"start_frame":frame_number,"frames":frame_count,"names":IDS.map(func(id):return Library.names(id)[stage])})
		for frame in frame_count:
			gallery.advance(1.0/30.0)
			await process_frame
			await RenderingServer.frame_post_draw
			var capture := root.get_texture().get_image()
			capture.save_jpg(OUTPUT+"frames/%04d.jpg"%frame_number,0.93)
			if frame in [48,72,96]:
				capture.save_png(OUTPUT+"stage-%d-%03d.png"%[stage+1,frame])
			frame_number += 1
		print("PLAYER CAPTURE: stage %d / 6, %d frames total"%[stage+1,frame_number])
	capture_metadata.frames = frame_number
	capture_metadata.seconds = float(frame_number)/30.0
	var metadata_file := FileAccess.open(OUTPUT+"capture.json",FileAccess.WRITE)
	metadata_file.store_string(JSON.stringify(capture_metadata,"\t"))
	metadata_file.close()
	print("PLAYER CAPTURE COMPLETE: %d frames at 30 fps, %.2f seconds"%[frame_number,float(frame_number)/30.0])
	await preload("res://tests/scene_cleanup.gd").free_scene(gallery,self)
	quit()
