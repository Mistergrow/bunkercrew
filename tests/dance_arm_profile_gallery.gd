extends SceneTree
## Native prepared dance poses from the real worker renderer, including half
## intensity and both facings. The beat clock is explicit, not an audio test.
const Cleanup := preload("res://tests/scene_cleanup.gd")
const Rhythm := preload("res://scripts/worker_rhythm_pose.gd")
const Catalog := preload("res://scripts/worker_dance_catalog.gd")
const Personality := preload("res://scripts/worker_personality.gd")
const PoseArt := preload("res://scripts/worker_pose_art.gd")
const OUTPUT := "res://artifacts/dance-arm-pass-20261005"
const SIZE := Vector2i(1920,1080)
var phase := "after"
var checks := 0
var failures := 0
var view: SubViewport
var records: Array[Dictionary] = []

class Board extends Node2D:
	var title := ""
	var subtitle := ""
	var ids: Array[String] = []
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO,Vector2(1920,1080)),Color("101b1c"))
		UiArt.text(self,Vector2(30,45),title,26,UiArt.IVORY,UiArt.MENU_FONT)
		UiArt.text(self,Vector2(30,78),subtitle,14,UiArt.MUTED)
		for row in 2:
			var floor_y := 395+row*445
			draw_line(Vector2(30,floor_y),Vector2(1890,floor_y),Color("58644f"),2)
			UiArt.text(self,Vector2(30,floor_y+40),"Blick nach rechts" if row==0 else "Blick nach links",16,UiArt.MUTED)
		for column in ids.size():
			var step := 1800.0/float(ids.size())
			UiArt.text(self,Vector2(100+float(column)*step-25,140),ids[column].capitalize(),20,Color(CharacterCatalog.data(ids[column]).accent),UiArt.MENU_FONT)

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool,label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)

func freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child: Node in node.get_children(): freeze(child)

func make_worker(board: Board,id: String,at: Vector2,facing: float) -> Worker:
	var worker := Worker.new()
	worker.character_id = id
	worker.position = at
	worker.facing = facing
	board.add_child(worker)
	var visual := WorkerVisual.new()
	visual.name = "PixelVisual"
	worker.add_child(visual)
	freeze(worker)
	visual._identity.hide()
	visual.get_node("GroundShadow").hide()
	worker.scale = Vector2.ONE*3.0
	return worker

func present(worker: Worker,style: String,beats: float,intensity: float) -> Dictionary:
	var visual: WorkerVisual = worker.get_node("PixelVisual")
	var rig := Rhythm.new()
	rig.configure(worker.character_id)
	rig._movement = style
	rig._dance_blend = 1.0
	rig.weight = intensity
	var pose := Personality.stance(PoseArt.neutral(),worker.character_id)
	pose.hip_spread = 2.0
	rig.apply(pose,{"bar":floori(beats/4.0),"beat":floori(beats)%4,"phase":fposmod(beats,1.0),"audible_seconds":beats*.5,"last_kick_seconds":floorf(beats)*.5,"last_kick_strength":1.0})
	visual.pose_name = "idle"
	visual.pose_skeleton = pose
	visual.locomotion_pose = pose
	visual.queue_redraw()
	return pose

func capture(key: String,record: Dictionary) -> void:
	for unused in 2: await process_frame
	await RenderingServer.frame_post_draw
	var image := view.get_texture().get_image()
	var path := phase+"/"+key+".png"
	check(image.get_size()==SIZE and image.save_png(OUTPUT+"/"+path)==OK,key+": native capture")
	record.file = path
	record.native_resolution = [1920,1080]
	records.append(record)

func matrix(key: String,styles: Array[String],beats: float,intensity: float) -> void:
	var board := Board.new()
	board.ids.assign(Catalog.IDS)
	board.title = "BUNKERCREW · TANZARME · "+key.to_upper()
	board.subtitle = "Echte WorkerVisual-Rigs · beide Richtungen · Beat %.3f · Stärke %.0f %% · %s"%[beats,intensity*100.0,phase]
	view.add_child(board)
	var poses: Array[Dictionary] = []
	for row in 2:
		for column in Catalog.IDS.size():
			var id: String = Catalog.IDS[column]
			var worker := make_worker(board,id,Vector2(110+column*225,395+row*445),1.0 if row==0 else -1.0)
			var original := worker.position
			var pose := present(worker,styles[column],beats,intensity)
			check(worker.position==original and worker.velocity==Vector2.ZERO,key+": no real actor movement")
			poses.append({"character":id,"facing":worker.facing,"style":styles[column],"pose":var_to_str(pose)})
	await capture(key,{"kind":"all_eight","beat":beats,"intensity":intensity,"poses":poses,"fixture":"Original workers and actual WorkerVisual canvas, pinned positions, physics held, no inventory, scale3x. The original stance is blended by actual Rhythm.apply at stated strength; no heard-audio claim or raster postprocessing."})
	check(await Cleanup.free_scene(board,self),key+": cleanup")

func _run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args():
		quit(2)
		return
	if "--before" in OS.get_cmdline_user_args(): phase="before"
	if DisplayServer.get_name()=="headless":
		push_error("Native dance captures require a graphical display")
		quit(2)
		return
	InputSetup.install()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT+"/"+phase))
	view = SubViewport.new()
	view.size = SIZE
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	view.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	root.add_child(view)
	for index in 5:
		var styles: Array[String] = []
		for id: String in Catalog.IDS: styles.append(Catalog.UNIQUE_STYLES[id][index])
		await matrix("own-%d-full"%index,styles,.5,1.0)
		await matrix("own-%d-half"%index,styles,.5,.5)
	for style: String in Catalog.SHARED_STYLES:
		var styles: Array[String] = []
		for unused in 8: styles.append(style)
		await matrix(style+"-kick",styles,0.0,1.0)
		await matrix(style+"-offbeat",styles,.5,.5)
	var defaults: Array[String] = []
	for id: String in Catalog.IDS: defaults.append(Catalog.DEFAULT_STYLES[id])
	await matrix("legacy-defaults",defaults,.5,1.0)
	check(await Cleanup.free_scene(view,self),"viewport cleanup")
	var hashes := {}
	for path: String in ["res://scripts/worker_pose_art.gd","res://scripts/worker_rhythm_pose.gd","res://scripts/worker_dance_moves.gd","res://tests/dance_arm_profile_gallery.gd"]:
		hashes[path] = FileAccess.get_file_as_string(path).sha256_text()
	var file := FileAccess.open(OUTPUT+"/"+phase+"-gallery.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"phase":phase,"checks":checks,"failures":failures,"captures":records,"source_hashes":hashes},"\t"))
	print("DANCE ARM PROFILE GALLERY %s: %d/%d checks; %d native captures"%[phase,checks-failures,checks,records.size()])
	quit(0 if failures==0 else 1)
