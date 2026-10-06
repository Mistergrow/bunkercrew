extends SceneTree
## Actual worker/robot renderers, prepared mirrored poses and an original room.
## Pose samples are explicit: no gameplay inputs, costs or contacts are invented.
const CLEANUP := preload("res://tests/scene_cleanup.gd")
const LOCOMOTION := preload("res://scripts/worker_locomotion.gd")
const WORK := preload("res://scripts/worker_work_pose.gd")
const MINING := preload("res://scripts/mining_worker_pose.gd")
const RHYTHM := preload("res://scripts/worker_rhythm_pose.gd")
const DANCE := preload("res://scripts/worker_dance_catalog.gd")
const OUTPUT := "res://artifacts/worker-arm-direction-20261005"
const SIZE := Vector2i(1920,1080)
const IDS: Array[String] = ["mara","branko","ivo","nora","levin","selma","oskar","rika"]
var phase := "before"
var checks := 0
var failures := 0
var captures: Array[Dictionary] = []
var view: SubViewport

class Board extends Node2D:
	var title := ""
	var subtitle := ""
	var rows := 2
	var robot_pair := false
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO,Vector2(1920,1080)),Color("101b1c"))
		UiArt.text(self,Vector2(30,45),title,26,UiArt.IVORY,UiArt.MENU_FONT)
		UiArt.text(self,Vector2(30,78),subtitle,14,UiArt.MUTED)
		if robot_pair:
			draw_line(Vector2(30,714),Vector2(1890,714),Color("58644f"),2)
			UiArt.text(self,Vector2(570,760),"Blick nach rechts",20,UiArt.MUTED)
			UiArt.text(self,Vector2(1270,760),"Blick nach links",20,UiArt.MUTED)
			return
		for row in rows:
			var floor_y := 400+row*460
			draw_line(Vector2(30,floor_y+4),Vector2(1890,floor_y+4),Color("58644f"),2)
			UiArt.text(self,Vector2(30,floor_y+40),"Blick nach rechts" if row==0 else "Blick nach links",16,UiArt.MUTED)
		for column in IDS.size():
			UiArt.text(self,Vector2(125+column*222-30,140),IDS[column].capitalize(),20,Color(CharacterCatalog.data(IDS[column]).accent),UiArt.MENU_FONT)

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child: Node in node.get_children(): freeze(child)

func capture(id: String,record: Dictionary) -> void:
	for unused in 3: await process_frame
	await RenderingServer.frame_post_draw
	var picture := view.get_texture().get_image()
	var filename := phase+"/"+id+".png"
	check(picture.get_size()==SIZE and picture.save_png(OUTPUT+"/"+filename)==OK,"native "+id)
	record["file"] = filename
	record["native_resolution"] = [1920,1080]
	captures.append(record)

func _worker(parent: Node2D,id: String,at: Vector2,facing: float) -> Worker:
	var worker := Worker.new()
	worker.character_id = id
	worker.position = at
	worker.facing = facing
	parent.add_child(worker)
	var visual := WorkerVisual.new()
	visual.name = "PixelVisual"
	worker.add_child(visual)
	freeze(worker)
	visual._identity.hide()
	visual.get_node("GroundShadow").hide()
	visual.idle_clock.wait_remaining = 1000.0
	return worker

func _pose(worker: Worker,kind: String,sample: float) -> Dictionary:
	var visual: WorkerVisual = worker.get_node("PixelVisual")
	worker.inventory.clear()
	worker.selected_kind = "ore"
	worker.velocity = Vector2.ZERO
	worker.climbing = false
	visual.crouched = false
	visual.ceiling_height = 128.0
	var state := kind
	if kind.begins_with("carry"): worker.inventory = {"ore":3}
	if kind.ends_with("walk"): worker.velocity.x = worker.facing*120.0
	if kind=="crawl":
		state = "crouch_walk"
		worker.velocity.x = worker.facing*85.0
		visual.crouched = true
		visual.ceiling_height = 40.0
	elif kind=="crouch":
		visual.crouched = true
		visual.ceiling_height = 58.0
	elif kind=="climb":
		worker.climbing = true
		worker._ladder = Rect2(worker.position+Vector2(-14,-253),Vector2(28,300))
	var rig := LOCOMOTION.new()
	var pose: Dictionary
	if kind.begins_with("dance"):
		state = "idle"
		var style := str(DANCE.UNIQUE_STYLES[worker.character_id][1])
		pose = RHYTHM.choreography(style,sample,worker.character_id,1.0)
	elif kind=="mining":
		state = "mine"
		pose = MINING._sample_local(Vector2(44,-27),3,false,worker.character_id,0.0)
		pose.facing = worker.facing
		visual.mining_pose = pose
	elif kind.begins_with("work"):
		state = "work"
		worker.inventory = {"ore":3}
		if kind=="work_behind_moving": worker.velocity.x = worker.facing*120.0
		var station := ProductionStation.new()
		station.kind = "furnace"
		station.position = worker.position+Vector2(worker.facing*(-46.0 if kind.begins_with("work_behind") else 46.0),0)
		worker.get_parent().add_child(station)
		freeze(station)
		station.hide()
		station.output_amount = 1 if kind=="work_collect" else 0
		station.transfer[worker.get_instance_id()] = sample*Balance.TRANSFER_TIME
		var resting: Dictionary = rig.advance(worker,"carry_walk",.22,false,visual) if kind=="work_behind_moving" else {}
		pose = WORK.sample(worker,station,false,resting)
		worker.get_parent().remove_child(station)
		station.free()
	else:
		pose = rig.advance(worker,state,sample,false,visual)
	if pose.has("cargo"):
		pose.cargo_kind = "ore" if kind!= "work_collect" else "steel"
	visual.pose_name = state
	visual.pose_frame = 0
	visual.special_pose = ""
	visual.pose_skeleton = pose
	if kind!="mining": visual.locomotion_pose = pose
	visual.queue_redraw()
	return pose

func _matrix(kind: String,sample: float,id: String) -> void:
	var board := Board.new()
	board.title = "BUNKERCREW · ARMRICHTUNG · "+kind.to_upper()
	board.subtitle = "Alle acht echten WorkerVisual-Rigs · beide Richtungen · native 3,2×-Inspektion · vorbereitet: "+phase
	view.add_child(board)
	var poses: Array[Dictionary] = []
	for row in 2:
		for column in IDS.size():
			var facing := 1.0 if row==0 else -1.0
			var worker := _worker(board,IDS[column],Vector2(125+column*222,400+row*460),facing)
			var pose := _pose(worker,kind,sample)
			check(not pose.is_empty(),id+": actual pose for "+worker.character_id)
			poses.append({"character":worker.character_id,"facing":facing,"velocity":[worker.velocity.x,worker.velocity.y],"inventory":worker.inventory.duplicate(),"pose":var_to_str(pose)})
			worker.scale = Vector2.ONE*3.2
	await capture(id,{"type":"matrix","kind":kind,"sample":sample,"draw_scale":3.2,"camera_zoom":1.0,"poses":poses,"fixture":"Eight original worker rigs per row; authoritative facing right above/left below. Pose sampled at original unscaled coordinates, then whole rigs magnified by actual Godot transform at nearest texture sampling; no raster editing or invented sprites. Mining is explicit canonical frame3/contact44,-27. Work uses a real furnace's read-only transfer state at facing46 ahead or facing-46 for behind variants; moving work holds facing120 velocity and passes a real carry-walk(.22) lower rig. Dance is each character's second personal move at explicit beat count; no heard-event claim."})
	check(await CLEANUP.free_scene(board,self),id+": rig cleanup")

func _furnace() -> void:
	var game := load("res://scenes/main.tscn").instantiate() as Node2D
	view.add_child(game)
	game.selected_characters.assign(["ivo"])
	game.start_scenario(1,{"environment":"ash_foundry","build_type":"bastion","position":"left"})
	game.rounds.running = false
	game.notice_time = 0.0
	game.weather.lightning_enabled = false
	game.weather.elapsed = 37.5
	game.scenery.elapsed = 37.5
	game.hud.hide()
	freeze(game)
	AudioServer.set_bus_mute(0,true)
	var station: ProductionStation = null
	for child: Node in game.get_children():
		if child is ProductionStation and child.kind=="furnace": station = child
	check(is_instance_valid(station),"original bunker room contains its furnace")
	var worker: Worker = game.players[0]
	check(worker.character_id=="ivo","actual room uses Ivo")
	var visual: WorkerVisual = worker.get_node("PixelVisual")
	visual.idle_clock.gesture = ""
	visual.idle_clock.wait_remaining = 1000.0
	game.camera.make_current()
	for kind: String in ["idle","carry_idle","work_deposit","work_behind","work_behind_moving"]:
		for facing: float in [1.0,-1.0]:
			worker.position = station.position-Vector2(facing*(-76.0 if kind.begins_with("work_behind") else 76.0),0)
			worker.facing = facing
			worker.velocity = Vector2(facing*120.0,0) if kind=="work_behind_moving" else Vector2.ZERO
			worker._airborne = false
			worker.inventory = {} if kind=="idle" else {"ore":3}
			worker.selected_kind = "ore"
			worker.focus = station if kind.begins_with("work") else null
			worker._interacting = kind.begins_with("work")
			station.working = false
			station.input_amount = 0
			station.output_amount = 0
			station.transfer[worker.get_instance_id()] = .45*Balance.TRANSFER_TIME
			visual.locomotion.reset()
			visual.special_pose = ""
			visual._process(.19 if kind=="work_behind_moving" else 0.0)
			for zoom: float in [1.25,6.0]:
				game.camera.position = worker.position+Vector2(facing*45.0,-125.0 if zoom<2.0 else -85.0)
				game.camera.zoom = Vector2.ONE*zoom
				game.camera.reset_smoothing()
				game.camera.force_update_scroll()
				game.scenery._process(0.0)
				var id := "ivo-furnace-"+kind+("-right" if facing>0 else "-left")+("-normal" if zoom<2 else "-detail")
				await capture(id,{"type":"actual_room","character":"ivo","kind":kind,"facing":facing,"target_behind":kind.begins_with("work_behind"),"velocity":[worker.velocity.x,worker.velocity.y],"camera_zoom":zoom,"worker_position":[worker.position.x,worker.position.y],"station_position":[station.position.x,station.position.y],"inventory":worker.inventory.duplicate(),"pose_name":visual.pose_name,"pose":var_to_str(visual.pose_skeleton),"fixture":"Original single-Ivo Aschewerk bunker and original furnace, callbacks/physics/AI/waves held. Worker at furnace-x minus facing76 for ordinary states, plus facing76 for explicit target-behind work. Moving-work holds velocity facing120 and one real WorkerVisual._process(.19) sample; other states sample _process(0). Transfer45% held; no material is consumed or world movement simulated. Normal1.25 and actual-camera detail6.0; no image postprocessing."})
	check(not game.network.active and not game.microphone.capturing,"room capture opens no networking/microphone")
	check(await CLEANUP.free_scene(game,self),"original room cleanup")

func _san(dance: bool=false) -> void:
	var board := Board.new()
	board.title = "SAN-1 · "+("TANZ" if dance else "RUHIGE INSPEKTION")
	board.subtitle = "Zwei echte FieldMedic-Rigs · Blick rechts / links · native 5×-Inspektion"
	board.rows = 1
	board.robot_pair = true
	view.add_child(board)
	for index in 2:
		var medic := FieldMedic.new()
		medic.position = Vector2(650+index*700,710)
		medic.facing = 1.0 if index==0 else -1.0
		board.add_child(medic)
		freeze(medic)
		medic._idle_time = 4.0
		medic.elapsed = 7.2
		medic.rhythm_pose.clear()
		if dance:
			medic.rhythm_pose.weight = 1.0
			medic.rhythm_pose.pose = preload("res://scripts/medic_rhythm_pose.gd").choreography("san_arm_wave",2.125,.06,.5,1.0,1.0)
		medic.scale = Vector2.ONE*5.0
		medic.queue_redraw()
	await capture("san-dance" if dance else "san-idle-inspection",{"type":"robot","facings":[1,-1],"elapsed":7.2,"idle_time":4.0,"draw_scale":5.0,"rhythm_weight":1.0 if dance else 0.0,"fixture":"Actual FieldMedic renderers with no target, treatment, road or cargo. Idle inspection holds elapsed7.2/idletime4, rhythm cleared/no music. Optional dance holds actual Hydraulik-Welle pose at beat2.125; no audio-event claim."})
	check(await CLEANUP.free_scene(board,self),"SAN inspection cleanup")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if DisplayServer.get_name()=="headless" or "--no-profile-save" not in args:
		quit(2)
		return
	if "--after" in args: phase = "after"
	InputSetup.install()
	AudioServer.set_bus_mute(0,true)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT+"/"+phase))
	root.size = Vector2i(1280,720)
	view = SubViewport.new()
	view.size = SIZE
	view.world_2d = World2D.new()
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	await _furnace()
	for entry: Array in [["idle",.6,"idle"],["carry_idle",.6,"carry-idle"],["walk",.19,"walk-a"],["walk",.44,"walk-b"],["carry_walk",.22,"carry-walk-a"],["carry_walk",.47,"carry-walk-b"],["crouch",.6,"crouch"],["crawl",.33,"crawl"],["climb",.6,"climb"],["work_deposit",.45,"work-deposit"],["work_collect",.55,"work-collect"],["work_behind",.45,"work-behind"],["work_behind_moving",.45,"work-behind-moving"],["mining",0.0,"mining-contact"],["dance",2.125,"dance-a"],["dance",2.5,"dance-b"]]:
		await _matrix(str(entry[0]),float(entry[1]),str(entry[2]))
	await _san()
	await _san(true)
	var source_hashes: Dictionary = {}
	for path: String in ["res://scripts/worker_pose_art.gd","res://scripts/worker_locomotion.gd","res://scripts/worker_work_pose.gd","res://scripts/mining_worker_pose.gd","res://scripts/field_medic.gd","res://tests/worker_arm_direction_gallery.gd"]:
		source_hashes[path] = FileAccess.get_sha256(path)
	FileAccess.open(OUTPUT+"/"+phase+"-gallery.json",FileAccess.WRITE).store_string(JSON.stringify({"phase":phase,"checks":checks,"failures":failures,"captures":captures,"source_hashes":source_hashes,"renderer":RenderingServer.get_video_adapter_name(),"scope":"Prepared actual rigs and one original bunker room; mirrored drawing/contact inspection, not gameplay/animation/audio acceptance. Native1920x1080 readback, explicit pose/phase samples, isolated profile and no network/microphone/audible output."},"  "))
	await CLEANUP.free_scene(view,self)
	print("WORKER ARM DIRECTION GALLERY %s: %d/%d checks passed; %d native captures"%[phase,checks-failures,checks,captures.size()])
	quit(0 if failures==0 else 1)
