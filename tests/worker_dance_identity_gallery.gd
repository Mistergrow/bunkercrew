class_name WorkerDanceIdentityGallery
extends SceneTree
## Real side-view textures and heard-beat joint blending at native1x and3x.
## Optional --video stores each complete eight-beat120BPM phrase at30FPS.
const Dance := preload("res://scripts/worker_dance_catalog.gd")
const Rhythm := preload("res://scripts/worker_rhythm_pose.gd")
const PoseArt := preload("res://scripts/worker_pose_art.gd")
const Defaults := preload("res://scripts/audio_defaults.gd")
const Cleanup := preload("res://tests/scene_cleanup.gd")
const SIZE := Vector2i(1440,960)
const FPS := 30
const BPM := 120.0
const BEATS := 8.0
const OUTPUT := "res://artifacts/character-dance-identity-20261005/gallery"
var checks := 0
var failures := 0
var records: Array[Dictionary] = []
var view: SubViewport

class Dancer extends Node2D:
	var character_id := "mara"
	var pose: Dictionary = {}
	func _draw() -> void:
		PoseArt.draw_identity_pose(self,pose,character_id)

class Board extends Node2D:
	var slot := 0
	var beats := 0.0
	var styles: Array[String] = []
	var dancers: Array[Dancer] = []
	var rhythms: Array = []
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO,Vector2(SIZE)),Color("10191c"))
		Art.text(self,Vector2(32,42),"ACHT FIGUREN · ACHT EIGENE TANZSTILE",28,UiArt.IVORY)
		var title := LocaleText.text(Dance.label(styles[0])) if slot<3 else "Persönlicher Move "+str(slot-2)+" · ab Charakterstufe "+str(Dance.UNLOCK_LEVELS[slot-3])
		Art.text(self,Vector2(32,74),title,20,UiArt.AMBER)
		Art.text(self,Vector2(32,103),"Echtes Seiten-Rig · native Spielgröße 1× und Detail 3× · bestehende Standard-Tanzstärke · 120 BPM",14,Art.MUTED)
		for index in Dance.IDS.size():
			var x := 24.0+float(index%4)*354.0
			var y := 128.0+floorf(float(index)/4.0)*390.0
			var id: String = Dance.IDS[index]
			var accent := Color(CharacterCatalog.data(id).accent)
			draw_rect(Rect2(x,y,330,366),Color("1b2829"))
			draw_rect(Rect2(x,y,330,2),accent)
			Art.text(self,Vector2(x+14,y+30),str(CharacterCatalog.data(id).title),23,accent)
			Art.text(self,Vector2(x+14,y+55),LocaleText.text(Dance.label(styles[index])),15,UiArt.IVORY)
			Art.text(self,Vector2(x+36,y+113),"1×",13,Art.MUTED)
			Art.text(self,Vector2(x+244,y+113),"3×",13,Art.MUTED)
			draw_line(Vector2(x+14,y+304),Vector2(x+316,y+304),Color("65766c"))
			Art.text(self,Vector2(x+14,y+337),"Schlag %.2f · %s"%[beats,str(dancers[index*2].pose.get("dance_stage","standing"))],13,Art.MUTED)
		Art.text(self,Vector2(32,934),"Vorbereitete stumme Prüfung · vollständige 8 Beats · Freischaltungen nur für diese Entwicklungsvorschau",14,Art.MUTED)
	func advance(beat: float,delta: float) -> void:
		beats = fposmod(beat,BEATS)
		for index in Dance.IDS.size():
			var id: String = Dance.IDS[index]
			var frame := WorkerDanceIdentityGallery.frame_at(beat,id,styles[index])
			var rhythm = rhythms[index]
			rhythm.advance(delta,true,frame)
			var pose := PoseArt.neutral()
			rhythm.apply(pose,frame)
			for dancer in dancers.slice(index*2,index*2+2):
				dancer.pose = pose
				dancer.queue_redraw()
		queue_redraw()

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

static func frame_at(beats: float,id: String,style: String) -> Dictionary:
	return {"active":true,"phase":fposmod(beats,1.0),"bar":floori(beats/4.0),"beat":floori(beats)%4,"audible_seconds":beats*.5,"last_kick_seconds":floorf(beats)*.5,"last_kick_strength":1.0,"kick_count":floori(beats)+1,"bpm":BPM,"beat_period_seconds":.5,"motion_gain":1.0,"dance_intensity":Defaults.DANCE_INTENSITY,"dance_profiles":{id:{"style":style,"intensity":1.0}},"genre":"minimal_techno","character_level":10,"dance_preview":false}

func _board(slot: int) -> Board:
	var board := Board.new()
	board.slot = slot
	board.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	for index in Dance.IDS.size():
		var id: String = Dance.IDS[index]
		var style: String = Dance.SHARED_STYLES[slot] if slot<3 else Dance.UNIQUE_STYLES[id][slot-3]
		board.styles.append(style)
		var rhythm := Rhythm.new()
		rhythm.configure(id)
		for beat in 8:
			rhythm.advance(.5,true,frame_at(float(beat),id,style))
		board.rhythms.append(rhythm)
		for zoom: float in [1.0,3.0]:
			var dancer := Dancer.new()
			dancer.character_id = id
			dancer.position = Vector2(24+index%4*354+(90 if zoom==1 else 244),128+floorf(float(index)/4.0)*390+304)
			dancer.scale = Vector2.ONE*zoom
			board.add_child(dancer)
			board.dancers.append(dancer)
	return board

func _capture(path: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var image := view.get_texture().get_image()
	check(image.get_size()==SIZE and image.save_png(path)==OK,"Actual native rendering captured: "+path.get_file())

func _run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args() or DisplayServer.get_name()=="headless":
		push_error("Use a graphical display and --no-profile-save for dance identity captures")
		quit(2)
		return
	AudioServer.set_bus_mute(0,true)
	LocaleText.set_locale("de",false)
	root.mode = Window.MODE_WINDOWED
	root.size = SIZE
	root.content_scale_size = SIZE
	var directory := OUTPUT
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			directory = argument.trim_prefix("--output=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	view = SubViewport.new()
	view.size = SIZE
	view.disable_3d = true
	view.world_2d = World2D.new()
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	var preview := TextureRect.new()
	preview.texture = view.get_texture()
	preview.size = Vector2(SIZE)
	root.add_child(preview)
	var video := "--video" in OS.get_cmdline_user_args()
	for slot in 8:
		var board := _board(slot)
		view.add_child(board)
		var subdirectory := directory+"/slot-"+str(slot)
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(subdirectory))
		var captured: Array[String] = []
		if video:
			for frame in ceili(BEATS*60.0/BPM*float(FPS)):
				board.advance(8.0+float(frame)*BPM/(60.0*float(FPS)),1.0/float(FPS))
				await _capture(subdirectory+"/%03d.png"%frame)
				for dancer: Dancer in board.dancers:
					check(not dancer.pose.has("front_weight"),dancer.character_id+": original side representation")
			captured.append("slot-"+str(slot)+"/000.png")
			captured.append("slot-"+str(slot)+"/038.png")
			captured.append("slot-"+str(slot)+"/083.png")
		else:
			for phase: float in [.25,2.5,5.25]:
				board.advance(8.0+phase,.5)
				var filename := "slot-%d/beat-%.2f.png"%[slot,phase]
				await _capture(directory+"/"+filename)
				captured.append(filename)
		var crops: Array[Array] = []
		for index in Dance.IDS.size():
			crops.append([24+(index%4)*354+50,128+floorf(float(index)/4.0)*390+224,80,84])
		records.append({"slot":slot,"styles":board.styles.duplicate(),"captures":captured,"native_crop_rects":crops})
		await Cleanup.free_scene(board,self)
		print("WORKER DANCE IDENTITY GALLERY: slot "+str(slot))
	var report := {"checks":checks,"failures":failures,"records":records,"video_frames_per_slot":120 if video else 0,"size":[SIZE.x,SIZE.y],"existing_global_default":Defaults.DANCE_INTENSITY,"existing_character_default":1.0,"fps":FPS,"bpm":BPM,"beats":BEATS,"fixture":"Actual WorkerRhythmPose heard-beat advance/apply, WorkerPoseArt original side identities, native 1x and 3x, existing global intensity 1.5 and character gain 1.0, no gameplay changes or profile saves. All 40 exclusive unlocks enabled only in this prepared developer preview. Audio intentionally silent for visual comparison."}
	var file := FileAccess.open(directory+"/verification.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	await Cleanup.free_scene(preview,self)
	await Cleanup.free_scene(view,self)
	print("WORKER DANCE IDENTITY GALLERY: %d/%d passed"%[checks-failures,checks])
	quit(1 if failures else 0)
