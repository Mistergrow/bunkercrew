extends SceneTree
## Real menu -> music lab, real Gewitterpass synth, original side-view rigs.
const Cleanup := preload("res://tests/scene_cleanup.gd")
const Dance := preload("res://scripts/worker_dance_catalog.gd")
const Rhythm := preload("res://scripts/worker_rhythm_pose.gd")
const Themes := preload("res://scripts/music_theme_catalog.gd")
const Identity := preload("res://scripts/worker_identity_art.gd")
const DIRECTORY := "res://artifacts/head-nod"
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool,label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)

func capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(DIRECTORY+"/"+name+".png")==OK,"Real viewport saves "+name)

func _run() -> void:
	if DisplayServer.get_name()=="headless" or "--no-profile-save" not in OS.get_cmdline_user_args():
		push_error("Head nod capture requires graphics and --no-profile-save")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRECTORY))
	LocaleText.set_locale("de",false)
	root.size = Vector2i(1440,900)
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	game.hud._toggle_audio()
	await process_frame
	var options = game.hud.options_panel
	options.tab_buttons[3].pressed.emit()
	options.music_lab_button.pressed.emit()
	await process_frame
	var lab = options.music_lab
	check(is_instance_valid(lab),"Actual options entry opens the production music lab")
	lab.configuration.theme_id = "mountain_pass"
	lab.configuration.bpm = Themes.theme("mountain_pass").bpm
	lab.configuration.genre = "minimal_techno"
	lab.configuration.music_intensity = 2
	lab.configuration.dance_profiles = Dance.defaults()
	for character: String in Dance.IDS:
		lab.configuration.dance_profiles[character] = {"style":"head_nod","intensity":1.0}
	lab.configuration.dance_intensity = 1.5
	lab.configuration.reduced_motion = false
	lab._sync_controls()
	lab._start_music()
	check(lab.preview_session.native_active and lab.preview_session.environment_id=="mountain_pass","Gewitterpass uses its actual native Höhenlicht theme")
	var maturity := false
	for frame in 900:
		await process_frame
		if int(lab.preview_clock.state.get("kick_count",0))>=5 and lab.preview_world.actors.all(func(actor): return actor.get_node("PixelVisual").rhythm._dance_blend==1.0):
			maturity = true
			break
	check(maturity,"Actual heard kick stream establishes all six head-nod poses")
	var sample_begin := int(lab.preview_session.native_stream.mixed_samples())
	var max_neck_error := 0.0
	var dip_frames := 0
	var mature_frames := 0
	var side_frames := 0
	var captured_dip := false
	var captured_rest := false
	var captured_individual := false
	var heard_kicks := {}
	var maximum_tilt := 0.0
	var minimum_tilt := INF
	for frame in 960:
		await process_frame
		if frame==480:
			lab.configuration.dance_profiles = Dance.defaults()
			lab._update_dance()
			lab._sync_controls()
		var state: Dictionary = lab.preview_clock.state
		heard_kicks[int(state.get("kick_count",0))] = true
		var first = lab.preview_world.actors[0].get_node("PixelVisual")
		var age := float(state.get("audible_seconds",0.0))-float(state.get("last_kick_seconds",-1.0))
		var envelope := Rhythm.head_nod_envelope(age,float(first.rhythm._beat_period))
		for actor in lab.preview_world.actors:
			var rig = actor.get_node("PixelVisual")
			var pose: Dictionary = rig.pose_skeleton
			if rig.rhythm._dance_blend<1.0: continue
			mature_frames += 1
			if Identity.head(actor.character_id).resource_path.ends_with("/"+str(actor.character_id)+"_head.png") and not pose.has("front_weight"):
				side_frames += 1
			if pose.has("head_pivot"):
				var pivot: Vector2 = pose.head_pivot
				var body := WorkerPoseArt.torso_transform(pose)
				var neck := body*(Vector2(1,-15)+Vector2(pose.head_shift)+pivot)
				max_neck_error = maxf(max_neck_error,(WorkerPoseArt.head_transform(pose)*pivot).distance_to(neck))
			if frame<480:
				maximum_tilt = maxf(maximum_tilt,float(pose.head_tilt))
				minimum_tilt = minf(minimum_tilt,float(pose.head_tilt))
				if envelope>.85 and float(pose.head_tilt)>.14: dip_frames += 1
		if frame<480 and envelope>.98 and not captured_dip:
			await capture("01-heard-kick-chin-dip")
			captured_dip = true
		elif frame<480 and captured_dip and age/float(first.rhythm._beat_period)>.85 and not captured_rest:
			await capture("02-between-kicks")
			captured_rest = true
		elif frame>600 and envelope>.98 and not captured_individual:
			await capture("03-individual-dances")
			captured_individual = true
	check(captured_dip and captured_rest and captured_individual,"Actual rendering shows the dip, relaxed return and individual dances")
	check(dip_frames>300 and maximum_tilt-minimum_tilt>.20,"Head nod is visibly stronger at the actual default dance intensity")
	check(mature_frames>5000 and side_frames==mature_frames,"All six characters retain their original side-view artwork")
	check(heard_kicks.size()>25,"The movie follows genuine repeated native bass-drum events")
	check(max_neck_error<.0001,"Actual rendered heads stay attached at the neck pivot")
	check(int(lab.preview_session.native_stream.mixed_samples())>sample_begin,"Native stereo playback keeps advancing during visible nods")
	check(game.audio.calibration_active and not game.started,"Prepared lab capture leaves normal gameplay and progress untouched")
	var result := {"checks":checks,"failures":failures,"renderer":RenderingServer.get_video_adapter_name(),"actual_native_audio":true,"real_menu_entry":true,"environment":"mountain_pass","track":"Höhenlicht","bpm":lab.configuration.bpm,"music_intensity":2,"dance_intensity":1.5,"prepared_state":"Production music lab, six original side-view rigs, head_nod followed by individual default dances; actual native Gewitterpass kicks; no injected beat frames","frame_count":960,"heard_kicks":heard_kicks.size(),"dip_actor_frames":dip_frames,"mature_actor_frames":mature_frames,"side_actor_frames":side_frames,"minimum_head_tilt":minimum_tilt,"maximum_head_tilt":maximum_tilt,"maximum_neck_attachment_error":max_neck_error}
	var file := FileAccess.open(DIRECTORY+"/render-verification.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"\t"))
	file.close()
	check(await Cleanup.free_scene(game,self),"Recorded menu/music lab releases its native player cleanly")
	print("HEAD NOD CAPTURE: ",JSON.stringify(result))
	quit(1 if failures else 0)
