extends SceneTree
## Actual menu entry, actual native audio mixer and a mature sixteen-beat
## dance phrase. --write-movie records the audio mixed by Godot with the video.
const Cleanup := preload("res://tests/scene_cleanup.gd")
const Dance := preload("res://scripts/worker_dance_catalog.gd")
const Rhythm := preload("res://scripts/worker_rhythm_pose.gd")
const Themes := preload("res://scripts/music_theme_catalog.gd")
const Identity := preload("res://scripts/worker_identity_art.gd")
const SHOWCASE := {"mara":"mara_cross_turn","branko":"branko_hammer_pop","ivo":"ivo_tick_tock","nora":"nora_sway_turn","levin":"levin_air_freeze","selma":"selma_kick_turn"}
var failures := 0
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/music-beat-refresh/dance"))
	if not "--no-profile-save" in OS.get_cmdline_user_args() or not "--no-upnp" in OS.get_cmdline_user_args():
		push_error("Native dance refresh requires --no-profile-save and --no-upnp")
		quit(1)
		return
	if DisplayServer.get_name()=="headless":
		push_error("Native dance comparison requires graphics")
		quit(1)
		return
	InputSetup.install()
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
	check(is_instance_valid(lab),"Actual options entry opens the lab")
	lab.configuration.genre = "minimal_techno"
	lab.configuration.music_intensity = 2
	var tempo := float(Themes.theme("ash_foundry","minimal_techno").bpm)
	lab.configuration.bpm = tempo
	lab.configuration.dance_profiles = Dance.defaults()
	for character: String in SHOWCASE:
		lab.configuration.dance_profiles[character] = {"style":SHOWCASE[character],"intensity":1.0}
	lab.configuration.dance_intensity = 1.0
	lab.configuration.reduced_motion = false
	lab._sync_controls()
	lab._start_music()
	check(lab.preview_session.native_active,"Dance comparison uses the real native mixer")
	var maturity := false
	for frame in 900:
		await process_frame
		if int(lab.preview_clock.state.get("kick_count",0))>=5 and lab.preview_world.actors.all(func(actor): return actor.get_node("PixelVisual").rhythm._dance_blend==1.0):
			maturity = true
			break
	check(maturity,"Actual heard kicks begin the individual full-body dances")
	var actual: Dictionary = lab.preview_session.native_stream.metadata()
	check(int(actual.get("intensity",-1))==2,"Selected attack is the actual native arrangement, not just a UI label")
	if not maturity:
		await Cleanup.free_scene(game,self)
		quit(1)
		return
	var clock = lab.preview_session.clock
	var start_beat: float = float(clock.bar_index*4+clock.beat_index)+float(clock.beat_phase)
	var start_sample := int(lab.preview_session.native_stream.mixed_samples())
	var capture_start_seconds := float(Engine.get_process_frames())/60.0
	var end_beat: float = start_beat+16.0
	var max_kicks := 0
	var floor_freeze := false
	var tempo_frames := 0
	var frames := 0
	var synchronized_frames := 0
	var max_foot_error := 0.0
	var max_kick_sample_error := 0.0
	var side_identity_frames := 0
	var rate := float(lab.preview_session.native_stream.mix_rate())
	for frame in 1200:
		await process_frame
		frames += 1
		var beat: float = float(clock.bar_index*4+clock.beat_index)+float(clock.beat_phase)
		max_kicks = maxi(max_kicks,int(lab.preview_clock.state.get("kick_count",0)))
		var state: Dictionary = lab.preview_clock.state
		var audible_beat := float(state.get("bar",0))*4.0+float(state.get("beat",0))+float(state.get("phase",0.0))
		if is_equal_approx(float(state.get("beat_period_seconds",0.0)),60.0/tempo): tempo_frames += 1
		var kick_sample := int(state.get("last_kick_sample",-1))
		if kick_sample>=0:
			var sample_beat := float(kick_sample)/rate*tempo/60.0
			max_kick_sample_error = maxf(max_kick_sample_error,absf(float(kick_sample)-roundf(roundf(sample_beat)*rate*60.0/tempo)))
		for actor in lab.preview_world.actors:
			var rig = actor.get_node("PixelVisual")
			if rig.rhythm._dance_blend<1.0 or not rig.rhythm._transition_pose.is_empty(): continue
			var expected := Rhythm.choreography(str(rig.rhythm._movement),audible_beat,actor.character_id,1.0)
			for index in 2:
				max_foot_error = maxf(max_foot_error,Vector2(rig.pose_skeleton.feet[index]).distance_to(expected.feet[index]))
			if Identity.head(actor.character_id).resource_path=="res://assets/workers/"+str(actor.character_id)+"_head.png" and Identity.torso(actor.character_id).resource_path=="res://assets/workers/"+str(actor.character_id)+"_torso.png": side_identity_frames += 1
			synchronized_frames += 1
		var visual = lab.preview_world.actors[4].get_node("PixelVisual")
		if str(visual.pose_skeleton.get("dance_stage",""))=="freeze":
			floor_freeze = true
			if frames%10==0:
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png("res://artifacts/music-beat-refresh/dance/native-lab-freeze.png")
		if frames==80:
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://artifacts/music-beat-refresh/dance/native-lab-compare.png")
		if beat>=end_beat: break
	check(frames<1200,"Sample-derived preview clock completes sixteen musical beats")
	check(floor_freeze,"Actual native beat timeline reaches the rendered breakdance freeze")
	check(max_kicks>=16,"Preview heard genuine repeated native kick events")
	check(tempo_frames==frames,"Every actual audible native frame carries the authoritative musical tempo")
	check(max_kick_sample_error<=2.0,"Actual native bass-drum hits stay on the integer audible sample grid")
	check(synchronized_frames>=frames*5 and max_foot_error<0.0001,"Rendered steps use the same audible sample-derived grid as the real kick events")
	check(side_identity_frames>=frames*5,"Actual native dance timeline retains the original side-view character parts")
	check(lab.preview_session.native_stream.mixed_samples()>start_sample,"Native audio continues mixing under full-body animation")
	check(game.audio.calibration_active and not game.started,"Lab keeps music and dancing separate from a live match")
	var result := {"prepared_state":"Main scene options Music Lab; isolated native Aschewerk attack at actual default%.0f BPM; six original articulated side-view rigs; one learned own move per character;1.0 dance intensity; no gameplay, profile saving or invented drum events" % tempo, "capture_start_seconds":capture_start_seconds,"authoritative_tempo_frames":tempo_frames,"renderer":RenderingServer.get_video_adapter_name(),"checks":checks,"failures":failures,"frames_after_mature_kicks":frames,"musical_beats_after_mature_kicks":16,"actual_native_audio":true,"real_menu_entry":true,"kick_count":max_kicks,"styles":SHOWCASE,"floor_freeze":floor_freeze,"side_identity_actor_frames":side_identity_frames,"bpm":tempo,"stage":2,"max_kick_sample_error":max_kick_sample_error,"max_visual_foot_error_pixels":max_foot_error,"synchronized_actor_frames":synchronized_frames}
	var file := FileAccess.open("res://artifacts/music-beat-refresh/dance/native-verification.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"\t"))
	print("NATIVE DANCE COMPARISON: ",JSON.stringify(result))
	await Cleanup.free_scene(game,self)
	quit(1 if failures else 0)
