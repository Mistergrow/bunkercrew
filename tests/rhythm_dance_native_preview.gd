extends SceneTree
## Actual menu entry, actual native audio mixer and a mature sixteen-beat
## dance phrase. --write-movie records the audio mixed by Godot with the video.
const Cleanup := preload("res://tests/scene_cleanup.gd")
const Dance := preload("res://scripts/worker_dance_catalog.gd")
const Rhythm := preload("res://scripts/worker_rhythm_pose.gd")
const Identity := preload("res://scripts/worker_identity_art.gd")
const SHOWCASE := {"mara":"mara_cross_turn","branko":"branko_hammer_pop","ivo":"ivo_tick_tock","nora":"nora_sway_turn","levin":"levin_air_freeze","selma":"selma_kick_turn","oskar":"oskar_heel_press","rika":"rika_coil_finish"}
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
	if "--no-profile-save" not in OS.get_cmdline_user_args() or "--no-upnp" not in OS.get_cmdline_user_args() or AudioServer.get_driver_name()!="Dummy": quit(2);return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/rhythm-dance"))
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
	check(game.audio.music_volume==.5 and game.audio.sfx_volume==.5 and game.audio.voice_volume==.5 and game.voice.output_volume==.5 and game.audio.dance_intensity==1.5,"Fresh native menu keeps all four authored fifty-percent defaults and current dance intensity")
	game.hud._toggle_audio()
	await process_frame
	var options = game.hud.options_panel
	options.tab_buttons[3].pressed.emit()
	options.music_lab_button.pressed.emit()
	await process_frame
	var lab = options.music_lab
	check(is_instance_valid(lab),"Actual options entry opens the lab")
	check(lab.preview_world.actors.size()==8 and SHOWCASE.size()==8,"Native comparison includes every current crew identity")
	lab.configuration.genre = "minimal_techno"
	lab.configuration.music_intensity = 2
	lab.configuration.bpm = 118.0
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
	var capture := AudioEffectCapture.new()
	capture.buffer_length = 15.0
	var master := AudioServer.get_bus_index("Master")
	var capture_slot := AudioServer.get_bus_effect_count(master)
	AudioServer.add_bus_effect(master,capture)
	var clock = lab.preview_session.clock
	var start_beat: float = float(clock.bar_index*4+clock.beat_index)+float(clock.beat_phase)
	var start_sample := int(lab.preview_session.native_stream.mixed_samples())
	var end_beat: float = start_beat+16.0
	var max_kicks := 0
	var floor_freeze := false
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
		var kick_sample := int(state.get("last_kick_sample",-1))
		if kick_sample>=0:
			var sample_beat := float(kick_sample)/rate*118.0/60.0
			max_kick_sample_error = maxf(max_kick_sample_error,absf(float(kick_sample)-roundf(roundf(sample_beat)*rate*60.0/118.0)))
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
				root.get_texture().get_image().save_png("res://artifacts/rhythm-dance/native-lab-freeze.png")
		if frames==80:
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://artifacts/rhythm-dance/native-lab-compare.png")
			lab.preview_view.get_texture().get_image().save_png("res://artifacts/rhythm-dance/native-eight-crew.png")
		if beat>=end_beat: break
	check(frames<1200,"Sample-derived preview clock completes sixteen musical beats")
	check(floor_freeze,"Actual native beat timeline reaches the rendered breakdance freeze")
	check(max_kicks>=16,"Preview heard genuine repeated native kick events")
	check(max_kick_sample_error<=2.0,"Actual native bass-drum hits stay on the integer audible sample grid")
	check(synchronized_frames>=frames*8 and max_foot_error<0.0001,"All eight rendered step paths use the same audible sample-derived grid as the real kick events")
	check(side_identity_frames>=frames*8,"All eight native dance identities retain the original side-view character parts")
	check(lab.preview_session.native_stream.mixed_samples()>start_sample,"Native audio continues mixing under full-body animation")
	check(game.audio.calibration_active and not game.started,"Lab keeps music and dancing separate from a live match")
	var pcm := capture.get_buffer(capture.get_frames_available())
	var peak := 0.0
	var power := 0.0
	var finite := true
	for sample: Vector2 in pcm:
		finite = finite and sample.is_finite()
		peak = maxf(peak,maxf(absf(sample.x),absf(sample.y)))
		power += sample.length_squared()
	check(pcm.size()>AudioServer.get_mix_rate()*6 and finite and peak>.005 and capture.get_discarded_frames()==0,"Actual native dance timeline emits finite non-silent master PCM without capture loss")
	AudioServer.remove_bus_effect(master,capture_slot)
	var result := {"renderer":RenderingServer.get_video_adapter_name(),"checks":checks,"failures":failures,"frames_after_mature_kicks":frames,"musical_beats_after_mature_kicks":16,"actual_native_audio":true,"real_menu_entry":true,"kick_count":max_kicks,"styles":SHOWCASE,"floor_freeze":floor_freeze,"side_identity_actor_frames":side_identity_frames,"bpm":118,"stage":2,"max_kick_sample_error":max_kick_sample_error,"max_visual_foot_error_pixels":max_foot_error,"synchronized_actor_frames":synchronized_frames,"actual_master_pcm_frames":pcm.size(),"actual_master_peak":peak,"actual_master_rms":sqrt(power/maxi(1,pcm.size()*2)),"prepared_state":"Actual options-entry Music-Labor with eight real side-view rigs; explicit developer-preview level10 unlocks, individual styles, intensity1 fixture, real native stage2 sample/kick timeline. Fresh audible slider defaults remain50%. Rendering under external GPU load is not FPS proof; no human listening verdict."}
	var file := FileAccess.open("res://artifacts/rhythm-dance/native-verification.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"\t"))
	print("NATIVE DANCE COMPARISON: ",JSON.stringify(result))
	await Cleanup.free_scene(game,self)
	quit(1 if failures else 0)
