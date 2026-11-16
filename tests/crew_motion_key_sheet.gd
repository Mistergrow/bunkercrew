extends SceneTree
## Key-pose sheets of the articulated crew rig (pass 7A-crew): the idle at the
## visual review's sampling (every 6 frames) and every held key, a full-speed
## walk cycle frame by frame, a revival (kneel, administer, stand-up) and the
## dance at 4-frame sampling on an explicit 126 BPM kick clock. Real Worker,
## WorkerMedical and WorkerVisual state is stepped at 60 fps and every sampled
## pose is drawn by WorkerPoseArt at 3x on a plain backdrop. Presentation
## fixture only; nothing is asserted here.
## Run (display :78 only): godot --path . --script tests/crew_motion_key_sheet.gd -- --no-profile-save --no-upnp --out=artifacts/visual-pass7a-crew/keys/after
const Rhythm := preload("res://scripts/worker_rhythm_pose.gd")
const SCALE := 3.0
const CELL := Vector2(64, 84)
const BPM := 126.0

class Sheet extends Node2D:
	## Rows of [label, cells]; a cell is [[pose, id, local x, facing], ...].
	var rows: Array = []
	var cell_size := CELL
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, Vector2(4096, 4096)), Color("1b2422"))
		var font := ThemeDB.fallback_font
		for row_index in rows.size():
			var row: Array = rows[row_index]
			var top: float = 30.0+row_index*(cell_size.y*SCALE+34.0)
			draw_string(font, Vector2(8, top-8), str(row[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("d9d4b8"))
			var floor_y: float = top+cell_size.y*SCALE-12.0
			for column in row[1].size():
				var left: float = 8.0+column*cell_size.x*SCALE
				draw_rect(Rect2(left, top, cell_size.x*SCALE-4.0, cell_size.y*SCALE), Color("2a3532"))
				draw_line(Vector2(left, floor_y), Vector2(left+cell_size.x*SCALE-4.0, floor_y), Color("6b745f"), 2.0)
				draw_string(font, Vector2(left+4, top+14), str(column), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("8f9682"))
				# Lower z first, as the canvas orders the real actors.
				var entries: Array = row[1][column].duplicate()
				entries.sort_custom(func(a: Array, b: Array) -> bool: return int(a[4] if a.size() > 4 else 0) < int(b[4] if b.size() > 4 else 0))
				for entry: Array in entries:
					var at := Vector2(left+(cell_size.x*0.5+float(entry[2]))*SCALE, floor_y)
					draw_set_transform(at, 0.0, Vector2(SCALE*float(entry[3]), SCALE))
					WorkerPoseArt.draw_identity_pose(self, entry[0], str(entry[1]))
					draw_set_transform(Vector2.ZERO)

var out := "res://artifacts/visual-pass7a-crew/keys/after"

func _initialize() -> void:
	_run.call_deferred()

func _arg(name: String, fallback: String) -> String:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--%s=" % name): return argument.get_slice("=", 1)
	return fallback

func _worker(world: Node, id: String, at: Vector2, player: int = 1) -> Worker:
	var worker := Worker.new()
	worker.game = world
	worker.player_id = player
	worker.character_id = id
	worker.position = at
	world.add_child(worker)
	worker.set_physics_process(false)
	var visual := WorkerVisual.new()
	visual.name = "PixelVisual"
	worker.add_child(visual)
	visual.set_process(false)
	visual.set_physics_process(false)
	visual.idle_clock.wait_remaining = 1000
	return worker

static func _pose(worker: Worker) -> Dictionary:
	var visual: WorkerVisual = worker.get_node("PixelVisual")
	var pose: Dictionary = visual.pose_skeleton.duplicate(true)
	pose.erase("hidden_limbs")
	return pose

func _save(rows: Array, name: String, cell: Vector2 = CELL) -> void:
	var columns := 0
	for row: Array in rows: columns = maxi(columns, row[1].size())
	var view := SubViewport.new()
	view.size = Vector2i(int(16+columns*cell.x*SCALE), int(30+rows.size()*(cell.y*SCALE+34.0)))
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	view.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	root.add_child(view)
	var sheet := Sheet.new()
	sheet.rows = rows
	sheet.cell_size = cell
	view.add_child(sheet)
	for unused in 3: await process_frame
	await RenderingServer.frame_post_draw
	var path := ProjectSettings.globalize_path(out.path_join(name+".png"))
	view.get_texture().get_image().save_png(path)
	print("KEY SHEET ", path)
	view.queue_free()
	await process_frame

## Idle: per character, 14 samples 6 frames apart (the review's sampling).
func _idle(world: Node) -> void:
	var rows: Array = []
	for id: String in ["mara", "branko", "ivo", "nora", "levin", "selma", "oskar", "rika"]:
		var worker := _worker(world, id, Vector2(200, 300))
		var visual: WorkerVisual = worker.get_node("PixelVisual")
		for frame in 30: visual._process(1.0/60.0)
		var cells: Array = []
		for sample in 14:
			cells.append([[_pose(worker), id, 0.0, 1.0]])
			for frame in 6: visual._process(1.0/60.0)
		rows.append([id+" idle, 6 frames apart", cells])
		worker.free()
	await _save(rows, "idle")

## Walk: full-speed walk right, one sample per frame over a stride, then
## 14 samples 3 frames apart (the review's sampling).
func _walk(world: Node) -> void:
	var rows: Array = []
	for id: String in ["mara", "branko", "selma"]:
		var worker := _worker(world, id, Vector2(200, 300))
		var visual: WorkerVisual = worker.get_node("PixelVisual")
		var speed := Balance.PLAYER_SPEED*float(CharacterCatalog.data(id).speed)
		for frame in 20: visual._process(1.0/60.0)
		var every: Array = []
		var spaced: Array = []
		for frame in 60:
			worker.velocity.x = speed
			worker.position.x += speed/60.0
			visual._process(1.0/60.0)
			if frame >= 20 and every.size() < 16: every.append([[_pose(worker), id, 0.0, 1.0]])
			if frame >= 18 and (frame-18)%3 == 0 and spaced.size() < 14: spaced.append([[_pose(worker), id, 0.0, 1.0]])
		rows.append([id+" walk, every frame", every])
		rows.append([id+" walk, 3 frames apart", spaced])
		worker.velocity.x = 0
		var stop: Array = []
		for frame in 24:
			visual._process(1.0/60.0)
			if frame%2 == 0: stop.append([[_pose(worker), id, 0.0, 1.0]])
		rows.append([id+" stop, 2 frames apart", stop])
		worker.free()
	await _save(rows, "walk")

## Revive: Mara is knocked out and Branko revives her from 34 or 46 units on
## her feet side or 30 on her head side, facing her; then both stand up. The
## cell draws them in their canvas order (the reviver's visual z).
func _revive(world: Node) -> void:
	var rows: Array = []
	for setup: Array in [[34.0, false], [46.0, false], [-30.0, false], [34.0, true]]:
		var distance: float = setup[0]
		# Held on: the interact stays down after the revival, so the reviver
		# goes on to bandage the risen crew mate (the review shot does this).
		var held: bool = setup[1]
		var patient := _worker(world, "mara", Vector2(400, 300), 1)
		var helper := _worker(world, "branko", Vector2(400+distance, 300), 2)
		helper.facing = -signf(distance)
		var patient_visual: WorkerVisual = patient.get_node("PixelVisual")
		var helper_visual: WorkerVisual = helper.get_node("PixelVisual")
		patient.invulnerability = 0
		patient.take_damage(patient.hp+500.0, Vector2.LEFT)
		var cells: Array = []
		var finished := -1
		for frame in 60*9:
			var aiding := frame >= 60 and (finished < 0 or held)
			if aiding and patient.medical.begin_or_continue_aid(helper, 1.0/60.0) and finished < 0: finished = frame
			patient.medical.tick(1.0/60.0)
			helper.medical.tick(1.0/60.0)
			patient.hurt_flash = maxf(0.0, patient.hurt_flash-1.0/60.0)
			patient.hurt_stun = maxf(0.0, patient.hurt_stun-1.0/60.0)
			patient.invulnerability = maxf(0.0, patient.invulnerability-1.0/60.0)
			patient_visual._process(1.0/60.0)
			helper_visual._process(1.0/60.0)
			# Samples: every 4 frames around the kneel and the stand-up, every
			# 30 frames through the administering.
			var near_event := (frame >= 56 and frame < 96) or (finished >= 0 and frame-finished < 60)
			if (near_event and frame%4 == 0) or (not near_event and frame%30 == 0 and frame >= 60):
				cells.append([[_pose(patient), "mara", -18.0, patient.facing, patient_visual.z_index], [_pose(helper), "branko", -18.0+distance, helper.facing, helper_visual.z_index]])
			if finished >= 0 and frame-finished >= 60: break
		rows.append(["revive from %+d units%s (kneel 4 frames apart, then every 30, stand-up 4 apart)" % [int(distance), ", interact held on" if held else ""], cells])
		patient.free()
		helper.free()
	await _save(rows, "revive", Vector2(112, 84))

func _dance_frame(seconds: float, id: String, style: String) -> Dictionary:
	var period := 60.0/BPM
	var beats := seconds/period
	return {"active": true, "phase": fposmod(beats, 1.0), "bar": floori(beats/4.0), "beat": floori(beats)%4, "audible_seconds": seconds,
		"last_kick_seconds": floorf(beats)*period, "last_kick_strength": 1.0, "kick_count": floori(beats)+1, "bpm": BPM, "beat_period_seconds": period,
		"motion_gain": 1.0, "dance_intensity": 1.0, "dance_profiles": {id: {"style": style, "intensity": 1.0}}, "genre": "minimal_techno", "character_level": 10, "dance_preview": false}

## Dance: the idle rig plus WorkerRhythmPose as WorkerVisual applies it, 14
## samples 4 frames apart (the review's sampling) for a few repertoire moves.
func _dance(world: Node) -> void:
	var rows: Array = []
	for entry: Array in [["mara", "mara_box_glide"], ["mara", "crew_bounce"], ["branko", "branko_hammer_pop"], ["levin", "levin_toprock"], ["selma", "selma_v_step"], ["rika", "crew_clap"]]:
		var id: String = entry[0]
		var worker := _worker(world, id, Vector2(200, 300))
		var visual: WorkerVisual = worker.get_node("PixelVisual")
		var rig := Rhythm.new()
		rig.configure(id)
		var cells: Array = []
		var clock := 0.0
		for frame in 60*8:
			clock += 1.0/60.0
			visual._process(1.0/60.0)
			var dance := _dance_frame(clock, id, entry[1])
			rig.advance(1.0/60.0, true, dance)
			var pose: Dictionary = visual.pose_skeleton.duplicate(true)
			rig.apply(pose, dance)
			if frame >= 60*6 and (frame-60*6)%4 == 0 and cells.size() < 14: cells.append([[pose, id, 0.0, 1.0]])
		rows.append(["%s %s, 4 frames apart at %d BPM" % [id, entry[1], int(BPM)], cells])
		worker.free()
	await _save(rows, "dance")

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Key sheets need the isolated display")
		quit(2)
		return
	InputSetup.install()
	out = _arg("out", out)
	if not out.begins_with("res://") and not out.begins_with("/"): out = "res://"+out
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	var world := Node2D.new()
	root.add_child(world)
	var only := _arg("only", "idle,walk,revive,dance").split(",")
	if "idle" in only: await _idle(world)
	if "walk" in only: await _walk(world)
	if "revive" in only: await _revive(world)
	if "dance" in only: await _dance(world)
	world.queue_free()
	await process_frame
	quit(0)
