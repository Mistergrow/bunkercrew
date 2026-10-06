extends SceneTree
## Ordinary, paused main menu; authored OGG timing, real mixed PCM and title.
## --capture also records the same scene with Godot's real mixed movie audio.
const CLEANUP := preload("res://tests/scene_cleanup.gd")
const CATALOG := preload("res://scripts/menu_music_catalog.gd")
const OUTPUT := "res://artifacts/menu-rave"
const OPTIONS := {"environment":"ash_foundry","build_type":"workshop","position":"left"}
var game: Node
var output := OUTPUT
var selected_track: Dictionary = {}
var checks := 0
var failures := 0
var rendered_frames := 0
var sampled_frames := 0
var capture_enabled := false
var loop_enabled := false
var captured: Array[Dictionary] = []
var seen_kicks: Dictionary = {}
var maximum_pulse := 0.0
var minimum_pulse := 1.0
var maximum_secondary_pulse := 0.0
var minimum_vertical_offset := INF
var maximum_vertical_offset := -INF
var minimum_horizontal_offset := INF
var maximum_horizontal_offset := -INF
var pcm_frames := 0
var pcm_peak := 0.0
var pcm_energy := 0.0
var pcm_finite := true
var capture_effect: AudioEffectCapture
var music_bus := -1
var effect_index := -1
var menu_player: AudioStreamPlayer
var minimum_clock_step := INF
var maximum_clock_step := 0.0
var maximum_clock_excess := 0.0
var backward_clock_steps := 0
var backward_clock_examples: Array[Dictionary] = []
var kicks_after_wrap: Dictionary = {}

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if ok:
		print("MENU_RAVE_CHECK ",label)
	else:
		failures += 1
		push_error(label)

func frame() -> void:
	await process_frame
	rendered_frames += 1
	if is_instance_valid(current_scene): game = current_scene
	if capture_effect != null:
		var available := capture_effect.get_frames_available()
		if available>0:
			var samples := capture_effect.get_buffer(available)
			for sample: Vector2 in samples:
				pcm_finite = pcm_finite and is_finite(sample.x) and is_finite(sample.y)
				pcm_peak = maxf(pcm_peak,maxf(absf(sample.x),absf(sample.y)))
				pcm_energy += (sample.x*sample.x+sample.y*sample.y)*.5
			pcm_frames += samples.size()

func frames(count: int) -> void:
	for index in count: await frame()

func music_frame() -> Dictionary:
	return game.audio.menu_rhythm_frame()

func wordmark_state() -> Dictionary:
	return game.hud.main_menu_panel.wordmark_state()

func scale_of(state: Dictionary) -> float:
	var value: Variant = state.get("scale",1.0)
	return Vector2(value).x if value is Vector2 else float(value)

func record_capture(name: String, expected_peak: Variant = null) -> bool:
	if not capture_enabled: return true
	await RenderingServer.frame_post_draw
	var state := wordmark_state()
	var rhythm := music_frame()
	if expected_peak is bool:
		var pulse := float(state.get("pulse",0.0))
		if not bool(state.get("active",false)) or not (pulse>.65 if bool(expected_peak) else pulse<.02): return false
	elif expected_peak=="secondary":
		if not bool(state.get("active",false)) or float(state.get("secondary_pulse",0.0))<.65 or float(state.get("horizontal_offset",0.0))<1.5: return false
	check(root.get_texture().get_image().save_png(output+"/"+name+".png")==OK,"Actual menu viewport captures "+name)
	captured.append({"file":name+".png","audio_seconds":rhythm.get("audible_seconds",0.0),"beat":rhythm.get("beat",0),"pulse":state.get("pulse",0.0),"secondary_pulse":state.get("secondary_pulse",0.0),"vertical_offset":state.get("vertical_offset",0.0),"horizontal_offset":state.get("horizontal_offset",0.0),"scale":scale_of(state)})
	return true

func await_pulse(high: bool, name: String) -> bool:
	for index in 300:
		await frame()
		var state := wordmark_state()
		var pulse := float(state.get("pulse",0.0))
		if bool(state.get("active",false)) and (pulse>.65 if high else pulse<.02):
			if await record_capture(name,high): return true
	check(false,"Actual authored drum produces "+("peak" if high else "rest"))
	return false

func await_secondary() -> bool:
	for index in 360:
		await frame()
		var state := wordmark_state()
		if bool(state.get("active",false)) and float(state.get("secondary_pulse",0.0))>.65 and float(state.get("horizontal_offset",0.0))>1.5:
			if await record_capture("04-menu-second-tone","secondary"): return true
	check(false,"Actual audible beat reaches the rightward sway during its second bass tone")
	return false

func _read_menu_player() -> AudioStreamPlayer:
	var menu: Variant = game.audio.get("menu_music")
	if menu is Node: return menu.get("player") as AudioStreamPlayer
	return null

func run() -> void:
	capture_enabled = "--capture" in OS.get_cmdline_user_args()
	loop_enabled = "--loop" in OS.get_cmdline_user_args()
	if "--no-profile-save" not in OS.get_cmdline_user_args() or "--no-upnp" not in OS.get_cmdline_user_args() or (capture_enabled and DisplayServer.get_name()=="headless"):
		push_error("Use --no-profile-save --no-upnp; --capture also needs a graphical display")
		quit(2)
		return
	var requested_track := "nachtschicht"
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--track="): requested_track = argument.trim_prefix("--track=")
		if argument.begins_with("--output="): output = argument.trim_prefix("--output=")
	CATALOG.reset_rotation()
	for index in CATALOG.TRACK_COUNT:
		if str(CATALOG.selected_track().id) == requested_track: break
		CATALOG.advance_after_match()
	selected_track = CATALOG.selected_track()
	if str(selected_track.id) != requested_track:
		push_error("Unknown prepared menu track: " + requested_track)
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	root.size = Vector2i(1440,900)
	LocaleText.set_locale("de",false)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.combat_events.persistence_enabled = false
	game.audio.set_music_volume(1.0)
	game.audio.set_rhythm_motion_reduced(false)
	music_bus = AudioServer.get_bus_index("Music")
	capture_effect = AudioEffectCapture.new()
	capture_effect.buffer_length = 8.0
	effect_index = AudioServer.get_bus_effect_count(music_bus)
	AudioServer.add_bus_effect(music_bus,capture_effect)
	await frames(12)
	menu_player = _read_menu_player()
	check(not game.started and paused and game.hud.overlay=="menu","The ordinary main scene remains paused in its actual main menu")
	check(is_instance_valid(menu_player) and menu_player.playing and bool(music_frame().get("active",false)),"Dedicated menu music starts automatically without the music lab")
	check(str(music_frame().get("track_id","")) == requested_track and is_equal_approx(float(music_frame().get("bpm",0.0)),float(selected_track.bpm)),"The title uses the selected recorded minimal-techno timeline and its actual tempo")
	var playback_id := menu_player.get_stream_playback().get_instance_id() if is_instance_valid(menu_player) and menu_player.has_stream_playback() else 0
	await await_pulse(true,"01-menu-kick")
	var high := wordmark_state()
	check(scale_of(high)>1.02 and scale_of(high)<=1.041,"Actual kick visibly expands only the title within its existing menu clearance")
	await await_pulse(false,"02-menu-rest")
	var low := wordmark_state()
	check(scale_of(low)<1.001,"The title returns to its original scale between audible kicks")
	var original_center := Vector2(345,162.5)
	var high_center: Vector2 = high.get("center",Vector2.ZERO)
	var low_center: Vector2 = low.get("center",Vector2.ZERO)
	check(absf(high_center.x-original_center.x)<=2.3 and absf(low_center.x-original_center.x)<=2.3 and absf(high_center.y-original_center.y)<.001 and absf(low_center.y-original_center.y)<.001,"Actual audible beat moves only the title left and right while its vertical center remains fixed")
	var rest_rect: Rect2 = low.get("rect",Rect2())
	check(absf(rest_rect.position.x-98.0)<3.0 and absf(rest_rect.position.y-133.0)<.6 and rest_rect.size.distance_to(Vector2(494,59))<.6,"Title between kicks retains the original dimensions and menu clearance")
	await await_secondary()
	check(is_zero_approx(float(wordmark_state().get("vertical_offset",0.0))) and float(wordmark_state().get("horizontal_offset",0.0))>1.5 and float(music_frame().get("secondary_pulse",0.0))>.5,"The actual recorded second bass tone accompanies the rightward sway without vertical bouncing")
	var minimum_seconds := float(selected_track.seconds) + 3.0 if loop_enabled else (15.0 if capture_enabled else 3.0)
	var timeout := Time.get_ticks_msec()+70000
	var last_seconds := float(music_frame().get("audible_seconds",0.0))
	var last_microseconds := Time.get_ticks_usec()
	while float(music_frame().get("audible_seconds",0.0))<minimum_seconds and Time.get_ticks_msec()<timeout:
		await frame()
		sampled_frames += 1
		var state := wordmark_state()
		var rhythm := music_frame()
		var current_seconds := float(rhythm.get("audible_seconds",0.0))
		var current_microseconds := Time.get_ticks_usec()
		var step := current_seconds-last_seconds
		var real_delta := float(current_microseconds-last_microseconds)/1000000.0
		minimum_clock_step = minf(minimum_clock_step,step)
		maximum_clock_step = maxf(maximum_clock_step,step)
		maximum_clock_excess = maxf(maximum_clock_excess,step-maxf(.25,real_delta*1.5+.05))
		if step < -.00001:
			backward_clock_steps += 1
			if backward_clock_examples.size()<8: backward_clock_examples.append({"from":last_seconds,"to":current_seconds,"step":step,"decoder_loops":rhythm.get("decoder_loops",0)})
		last_seconds = current_seconds
		last_microseconds = current_microseconds
		var pulse := float(state.get("pulse",0.0))
		maximum_pulse = maxf(maximum_pulse,pulse)
		minimum_pulse = minf(minimum_pulse,pulse)
		maximum_secondary_pulse = maxf(maximum_secondary_pulse,float(state.get("secondary_pulse",0.0)))
		minimum_vertical_offset = minf(minimum_vertical_offset,float(state.get("vertical_offset",0.0)))
		maximum_vertical_offset = maxf(maximum_vertical_offset,float(state.get("vertical_offset",0.0)))
		minimum_horizontal_offset = minf(minimum_horizontal_offset,float(state.get("horizontal_offset",0.0)))
		maximum_horizontal_offset = maxf(maximum_horizontal_offset,float(state.get("horizontal_offset",0.0)))
		if pulse>.3:
			seen_kicks[str(rhythm.get("kick_timestamp",-1.0))] = true
			if current_seconds>=float(selected_track.seconds): kicks_after_wrap[str(rhythm.get("kick_timestamp",-1.0))] = true
	check(float(music_frame().get("audible_seconds",0.0))>=minimum_seconds,"Actual decoder advances while the main-menu world remains paused")
	check(seen_kicks.size()>=4 and maximum_pulse>.65 and minimum_pulse<.05,"Repeated audible kicks reach visible peaks and rests")
	check(maximum_secondary_pulse>.65 and is_zero_approx(minimum_vertical_offset) and is_zero_approx(maximum_vertical_offset),"Recorded real music keeps the entire title sway horizontal")
	check(minimum_horizontal_offset<-1.5 and maximum_horizontal_offset>1.5 and minimum_horizontal_offset>=-2.3 and maximum_horizontal_offset<=2.3,"The actual audible beat moves the title smoothly left and right without moving any controls")
	check(backward_clock_steps==0 and maximum_clock_excess<.001,"Actual decoder preserves a monotonic audible clock with bounded jumps across real frame hitches")
	if loop_enabled:
		check(int(music_frame().get("decoder_loops",0))>=1 and menu_player.get_stream_playback().get_instance_id()==playback_id,"The actual complete OGG loop keeps the same decoder and authored drum transport")
		check(kicks_after_wrap.size()>=4,"The same title responds to distinct real authored kicks after the loop wraps")
	check(pcm_frames>22050 and pcm_finite and pcm_peak>.01 and pcm_peak<1.0 and pcm_energy/maxf(float(pcm_frames),1.0)>.00001,"Actual Music-bus PCM is finite, audible and below digital clipping")
	var before_seconds := float(music_frame().get("audible_seconds",0.0))
	var panel: Node = game.hud.main_menu_panel
	panel.preview_next.pressed.emit()
	await frames(10)
	check(float(music_frame().get("audible_seconds",0.0))>=before_seconds and menu_player.get_stream_playback().get_instance_id()==playback_id,"Browsing the level preview preserves the same playing track and transport")
	game.hud._toggle_audio()
	await frames(6)
	game.hud.options_panel.select_tab(4)
	for button: Node in game.hud.options_panel.pages[4].get_children():
		if button is Button and button.tooltip_text=="English": button.pressed.emit()
	await frames(10)
	check(LocaleText.current_locale()=="en" and menu_player.get_stream_playback().get_instance_id()==playback_id,"Changing menu language keeps the same real decoder")
	LocaleText.set_locale("de",false)
	game.hud._close_audio()
	await frames(6)
	game.hud._toggle_help()
	await frames(12)
	check(game.hud.overlay=="help" and bool(music_frame().get("active",false)) and menu_player.get_stream_playback().get_instance_id()==playback_id,"Help keeps menu music playing continuously")
	game.hud._toggle_help()
	await frames(12)
	game.hud._toggle_audio()
	await frames(12)
	check(game.hud.overlay=="audio" and bool(music_frame().get("active",false)) and menu_player.get_stream_playback().get_instance_id()==playback_id,"Options keeps menu music playing continuously")
	game.hud._toggle_audio()
	await frames(12)
	game.audio.set_music_volume(0.0)
	await frames(8)
	var muted := wordmark_state()
	check(not bool(music_frame().get("active",false)) and not bool(muted.get("active",false)) and is_equal_approx(scale_of(muted),1.0) and is_zero_approx(float(muted.get("vertical_offset",0.0))) and is_zero_approx(float(muted.get("horizontal_offset",0.0))),"Muting actual music stops title beat reactions and restores its original transform")
	check(menu_player.get_stream_playback().get_instance_id()==playback_id,"Local mute preserves the menu transport rather than resetting the song")
	game.audio.set_music_volume(1.0)
	game.audio.set_rhythm_motion_reduced(true)
	await frames(8)
	check(bool(music_frame().get("active",false)) and bool(wordmark_state().get("reduced",false)) and is_equal_approx(scale_of(wordmark_state()),1.0) and is_zero_approx(float(wordmark_state().get("vertical_offset",0.0))) and is_zero_approx(float(wordmark_state().get("horizontal_offset",0.0))),"Reduced movement retains audible music without title scaling or movement")
	await record_capture("03-reduced-menu")
	game.audio.set_rhythm_motion_reduced(false)
	await frames(8)
	game.start_scenario(1,OPTIONS)
	game.rounds.set_process(false)
	await frames(35)
	check(game.started and game.audio.live_music.session_active and not bool(music_frame().get("active",false)),"Normal scenario start hands music from the menu into actual level audio")
	check(not menu_player.playing and not menu_player.has_stream_playback(),"Menu transport stops completely when gameplay begins")
	AudioServer.remove_bus_effect(music_bus,effect_index)
	capture_effect = null
	paused = false
	check(await CLEANUP.free_scene(game,self),"Actual main menu, level and audio playback release cleanly")
	var result := {"checks":checks,"failures":failures,"actual_main_scene":true,"music_lab_used":false,"injected_rhythm_used":false,"menu_world_paused":true,"prepared_track":requested_track,"title":selected_track.title,"seconds":selected_track.seconds,"viewport":[1440,900],"bpm":selected_track.bpm,"frames":rendered_frames,"sampled_title_frames":sampled_frames,"unique_authored_kicks":seen_kicks.size(),"minimum_pulse":minimum_pulse,"maximum_pulse":maximum_pulse,"maximum_secondary_pulse":maximum_secondary_pulse,"minimum_vertical_offset":minimum_vertical_offset,"maximum_vertical_offset":maximum_vertical_offset,"minimum_horizontal_offset":minimum_horizontal_offset,"maximum_horizontal_offset":maximum_horizontal_offset,"continuous_loop_checked":loop_enabled,"clock":{"minimum_step":minimum_clock_step,"maximum_step":maximum_clock_step,"maximum_hitch_adjusted_excess":maximum_clock_excess,"backward_steps":backward_clock_steps,"backward_examples":backward_clock_examples,"unique_kicks_after_wrap":kicks_after_wrap.size()},"pcm":{"frames":pcm_frames,"finite":pcm_finite,"peak":pcm_peak,"rms":sqrt(pcm_energy/maxf(float(pcm_frames),1.0))},"captures":captured,"rendered":capture_enabled}
	var result_name := "/render-verification.json" if capture_enabled else ("/loop-verification.json" if loop_enabled else "/gameplay-verification.json")
	var file := FileAccess.open(output+result_name,FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"\t"))
	file.close()
	print("MENU RAVE GAMEPLAY: ",JSON.stringify(result))
	quit(0 if failures==0 else 1)
