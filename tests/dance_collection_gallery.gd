extends SceneTree
## All forty-three repertoire dances through the real side-view identity renderer.
const Dance := preload("res://scripts/worker_dance_catalog.gd")
const Rhythm := preload("res://scripts/worker_rhythm_pose.gd")
const Identity := preload("res://scripts/worker_identity_art.gd")
const Cleanup := preload("res://tests/scene_cleanup.gd")
const OUTPUT := "res://artifacts/dance-collection"
const SIZE := Vector2i(1440,960)
const SAMPLE_BEATS := [.25,1.25,2.5,3.5,5.25,7.25]
var checks := 0
var failures := 0
var view: SubViewport
var records: Array[Dictionary] = []
var captured := false

class Dancer extends Node2D:
	var character_id := "mara"
	var pose: Dictionary = {}
	func _draw() -> void:
		WorkerPoseArt.draw_identity_pose(self,pose,character_id)

class Board extends Node2D:
	var character_id := "mara"
	var style := "crew_bounce"
	var magnification := 2.0
	var poses: Array[Dictionary] = []
	var crew_board := false
	func _draw() -> void:
		draw_rect(Rect2(0,0,1440,960),Color("10191c"))
		var accent := Color(CharacterCatalog.data(character_id).accent)
		Art.text(self,Vector2(32,42),"SEITENANSICHTEN DER CREW" if crew_board else Dance.label(style).to_upper(),28,accent)
		var fixture_owner := Dance.owner(style)
		var label := "Acht unverwechselbare Identitäten · bestehende Arme, Beine und Gelenke" if crew_board else ("Gemeinsamer Move · ab Level 1" if fixture_owner.is_empty() else str(CharacterCatalog.data(character_id).title)+" · ab Charakterlevel "+str(Dance.required_level(style)))
		Art.text(self,Vector2(32,74),label,17,Art.MUTED)
		Art.text(self,Vector2(32,100),"Entwicklungs-Vorschau aller Freischaltungen · Gelenke direkt an musikalischen Beatpositionen",13,Art.MUTED)
		var columns := 4 if crew_board else 3
		var stride := 1416.0/columns
		for index in poses.size():
			var x := 24.0+float(index%columns)*stride
			var y := 124.0+float(floori(float(index)/columns))*390.0
			draw_rect(Rect2(x,y,stride-24,366),Color("1b2829"))
			draw_rect(Rect2(x,y,stride-24,2),accent)
			draw_line(Vector2(x+16,y+304),Vector2(x+stride-40,y+304),Color("65766c"))
			var title := str(CharacterCatalog.data(Dance.IDS[index]).title) if crew_board else "Schlag %.2f · %d×"%[float(SAMPLE_BEATS[index]),int(magnification)]
			Art.text(self,Vector2(x+16,y+28),title,18,UiArt.IVORY)
			var pose: Dictionary = poses[index]
			Art.text(self,Vector2(x+16,y+338),"Seitenansicht · %s"%str(pose.get("dance_stage","standing")),13,Art.MUTED)
		Art.text(self,Vector2(32,934),"Echter Godot-Renderer · native Pixeltexturen · kosmetische Choreografie am Standort",14,Art.MUTED)

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func capture(path: String) -> void:
	for index in 3:
		await process_frame
	if not captured:
		return
	for index in 2:
		await RenderingServer.frame_post_draw
	var image := view.get_texture().get_image()
	check(image.get_size()==SIZE,path+": exact prepared viewport")
	check(image.save_png(path)==OK,path+": captured actual rig rendering")

func board_for(id: String,style: String,scale_factor: float,crew_board: bool=false) -> Board:
	var board := Board.new()
	board.character_id = id
	board.style = style
	board.magnification = scale_factor
	board.crew_board = crew_board
	board.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var columns := 4 if crew_board else 3
	var stride := 1416.0/columns
	for index in (Dance.IDS.size() if crew_board else SAMPLE_BEATS.size()):
		var character: String = Dance.IDS[index] if crew_board else id
		var pose := WorkerPoseArt.neutral() if crew_board else Rhythm.choreography(style,float(SAMPLE_BEATS[index]),character,1.0)
		if crew_board:
			pose.continuous = true
		board.poses.append(pose)
		var dancer := Dancer.new()
		dancer.character_id = character
		dancer.pose = pose
		dancer.position = Vector2(24+(index%columns)*stride+(stride-24)*.5,124+floori(float(index)/columns)*390+304)
		dancer.scale = Vector2.ONE*scale_factor
		board.add_child(dancer)
	return board

func run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args():
		quit(2)
		return
	AudioServer.set_bus_mute(0,true)
	LocaleText.set_locale("de",false)
	captured = DisplayServer.get_name()!="headless"
	if captured:
		root.mode = Window.MODE_WINDOWED
		root.size = SIZE
	var styles: Array[String] = []
	styles.assign(Dance.SHARED_STYLES)
	for id: String in Dance.IDS:
		styles.append_array(Dance.UNIQUE_STYLES[id])
	check(styles.size()==43,"Exactly three shared and forty character dances are rendered")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
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
	for style: String in styles:
		var id := Dance.owner(style)
		if id.is_empty():
			id = "mara"
		check(Identity.head(id)!=null and Identity.torso(id)!=null,style+": existing side identity is imported")
		var captures: Array[String] = []
		var stages: Array[String] = []
		for scale_factor in [2.0,4.0]:
			var board := board_for(id,style,scale_factor)
			view.add_child(board)
			for pose: Dictionary in board.poses:
				check(Vector2(pose.hip).is_finite() and Vector2(pose.shoulder).is_finite() and Vector2(pose.head_shift).is_finite(),style+": anatomical pivots remain finite")
				var stage := str(pose.get("dance_stage","standing"))
				if stage not in stages:
					stages.append(stage)
			var filename := "%s-%dx.png"%[style,int(scale_factor)]
			await capture(OUTPUT+"/"+filename)
			if captured:
				captures.append(filename)
			await Cleanup.free_scene(board,self)
		records.append({"style":style,"label":Dance.label(style),"owner":Dance.owner(style),"character":id,"level":Dance.required_level(style),"captures":captures,"side_art":true,"stages":stages})
		print("DANCE COLLECTION: "+style)
	var crew_board := board_for("mara","crew_bounce",4,true)
	view.add_child(crew_board)
	await capture(OUTPUT+"/side-crew.png")
	await Cleanup.free_scene(crew_board,self)
	var report := {"checks":checks,"failures":failures,"rendered":captured,"size":[SIZE.x,SIZE.y],"styles":records,"sample_beats":SAMPLE_BEATS,"side_crew":"side-crew.png" if captured else "","fixture":"Actual WorkerPoseArt articulated renderer and WorkerRhythmPose choreography sampled at six audible beat positions, intensity1. No player progress. Full repertoire is explicitly a developer preview, including future level unlocks. Paired captures use native2x and4x scales. Original side-view head/chest parts and the existing continuous limbs remain."}
	var file := FileAccess.open(OUTPUT+"/verification-"+("rendered" if captured else "headless")+".json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	preview.queue_free()
	view.queue_free()
	await process_frame
	print("DANCE COLLECTION GALLERY: %d/%d passed"%[checks-failures,checks])
	quit(1 if failures else 0)
