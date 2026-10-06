extends SceneTree
## Prepared appearance comparison: actual WorkerVisual at native size and 2x;
## two four-worker game scenes retain the supported gameplay party limit.
const Cleanup := preload("res://tests/scene_cleanup.gd")
const Identity := preload("res://scripts/worker_identity_art.gd")
const Personality := preload("res://scripts/worker_personality.gd")
const Locomotion := preload("res://scripts/worker_locomotion.gd")
const IDS := ["mara","branko","ivo","nora","levin","selma","oskar","rika"]
var output := "res://artifacts/crew-identities-20261005/visuals"
var phase := "before"
var checks := 0
var failures := 0
var captures: Array[Dictionary] = []

class Matrix extends Node2D:
	var actors: Array[Worker] = []
	var factor := 1.0
	func _draw() -> void:
		draw_rect(Rect2(0,0,1920,1080),Color("141f22"))
		UiArt.text(self,Vector2(28,40),"BUNKERCREW / CHARACTER IDENTITIES",26,UiArt.IVORY,UiArt.MENU_FONT)
		UiArt.text(self,Vector2(28,74),"Actual WorkerVisual · prepared side/rear poses · native sampling · %sx" % factor,16,UiArt.MUTED)
		for column in IDS.size():
			var x := 140+column*218
			UiArt.text(self,Vector2(x-36,100),IDS[column].capitalize(),22,UiArt.IVORY,UiArt.MENU_FONT)
		for row in 6:
			var y := 250+row*155
			UiArt.text(self,Vector2(24,y-64),["Atlas","Idle","Walk","Carry","Ladder","Care"][row],15,UiArt.MUTED)
			draw_line(Vector2(104,y+3),Vector2(1892,y+3),Color(UiArt.MUTED,.3),1)
	func layout(value: float) -> void:
		factor = value
		for index in actors.size():
			actors[index].scale=Vector2.ONE*value
		queue_redraw()

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): output=argument.trim_prefix("--output=")
		elif argument.begins_with("--phase="): phase=argument.trim_prefix("--phase=")
	run.call_deferred()

func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func frames(count: int=4) -> void:
	for unused in count: await process_frame

func capture(view: Viewport,label: String,fixture: String) -> void:
	await frames()
	await RenderingServer.frame_post_draw
	var picture := view.get_texture().get_image()
	var path := output.path_join(phase+"-"+label+".png")
	check(picture.get_size()==Vector2i(1920,1080) and picture.save_png(path)==OK,"Actual renderer captures "+label)
	captures.append({"file":phase+"-"+label+".png","fixture":fixture,"size":[1920,1080]})

func configure_pose(actor: Worker,visual: WorkerVisual,row: int) -> void:
	actor.set_physics_process(false)
	visual.set_process(false)
	visual.set_physics_process(false)
	visual._identity.hide()
	visual.get_node("GroundShadow").hide()
	visual.pose_name="idle"
	if row==0: return
	if row==5:
		visual.special_pose="aid_bandage"
		visual.pose_skeleton=WorkerPoseArt.sample("aid_bandage",.45,0,Vector2(24,-20),actor.character_id)
	else:
		var state: String = ["","idle","walk","carry_walk","climb"][row]
		actor.velocity=Vector2(130,0) if state.ends_with("walk") else Vector2.ZERO
		if state=="carry_walk": actor.inventory={"ore":3}
		if state=="climb":
			actor.climbing=true
			actor._ladder=Rect2(actor.position+Vector2(-14,-280),Vector2(28,300))
		var pose := Locomotion.new().advance(actor,state,.6,false,visual)
		if pose.has("cargo"): pose.cargo_kind="ore"
		visual.locomotion_pose=pose
		visual.pose_skeleton=pose
		visual.pose_name=state
	visual.queue_redraw()

func run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args() or DisplayServer.get_name()=="headless": quit(2); return
	InputSetup.install()
	AudioServer.set_bus_mute(0,true)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	root.size=Vector2i(1920,1080)
	var view := SubViewport.new()
	view.size=Vector2i(1920,1080)
	view.world_2d=World2D.new()
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	var matrix := Matrix.new()
	view.add_child(matrix)
	for row in 6:
		for column in IDS.size():
			var actor := Worker.new()
			actor.character_id=IDS[column]
			actor.position=Vector2(140+column*218,250+row*155)
			matrix.add_child(actor)
			var visual := WorkerVisual.new()
			visual.name="PixelVisual"
			actor.add_child(visual)
			configure_pose(actor,visual,row)
			matrix.actors.append(actor)
	matrix.layout(1.0)
	await capture(view,"native-matrix","All eight actual WorkerVisual instances at native scale, labels separated from avatars; shared atlas/continuous idle/walk/carry/ladder/care states.")
	matrix.layout(2.0)
	await capture(view,"detail-matrix","The same runtime actors and anchor poses at 2x nearest sampling. Side views and existing rear ladder view, no frontal dance.")
	await Cleanup.free_scene(matrix,self)
	var roster := preload("res://scripts/crew_roster.gd")
	roster.persistence_enabled=false
	for id: String in IDS: roster.unlock(id)
	for group in 2:
		var game = load("res://scenes/main.tscn").instantiate()
		view.add_child(game)
		await frames()
		game.selected_characters.assign(IDS.slice(group*4,group*4+4))
		game.start_scenario(4,{"environment":"ash_foundry","position":"left","build_type":"bastion"})
		game.rounds.running=false
		game.rounds.set_process(false)
		game.story.set_process(false)
		game.camera.position=Vector2(990,220)
		game.camera.zoom=Vector2.ONE
		game.camera.position_smoothing_enabled=false
		game.set_process(false)
		game.notice=""
		game.notice_time=0
		for index in game.players.size():
			var actor: Worker=game.players[index]
			actor.position=Vector2(690+index*180,430)
			actor.set_physics_process(false)
			var visual: WorkerVisual=actor.get_node("PixelVisual")
			visual.set_process(false)
			visual.set_physics_process(false)
			visual.special_pose=""
			visual.pose_name="idle"
			visual.locomotion_pose=Personality.stance(WorkerPoseArt.neutral(),actor.character_id)
			visual.pose_skeleton=visual.locomotion_pose
			visual.queue_redraw()
		check(game.players.size()==4,"Prepared game keeps the four-worker party limit")
		await capture(view,"level-party-%d" % (group+1),"Actual 1920x1080 Aschewerk scene, four prepared stationary workers, camera zoom1, waves frozen, no enemy or network session; group%d." % (group+1))
		await Cleanup.free_scene(game,self)
	var hashes: Dictionary={}
	for id: String in IDS:
		for part: String in ["body","arms","torso","head","back_torso","back_head"]:
			var path := "res://assets/workers/%s_%s.png" % [id,part]
			hashes[path]=FileAccess.get_sha256(path)
	FileAccess.open(output.path_join(phase+"-capture.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"captures":captures,"source_hashes":hashes,"prepared_state":"Appearance fixtures; no regular campaign playthrough, sockets, microphone or profile save."},"  ")+"\n")
	view.queue_free()
	await frames()
	print("WORKER IDENTITY EXPANSION GALLERY: %d/%d checks passed" % [checks-failures,checks])
	quit(1 if failures else 0)
