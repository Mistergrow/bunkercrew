extends SceneTree
## Exercise the actual extension through AudioStreamPlayer's real mixer path.
## A deliberately disabled backend is covered by live_music_test.gd separately.
const Runtime := preload("res://scripts/live_music.gd")
const Themes := preload("res://scripts/music_theme_catalog.gd")
var checks := 0
var failures := 0
var heard_beats := 0
var heard_accents := 0

func _initialize() -> void:
	run.call_deferred()

func check(value: bool,label: String) -> void:
	checks+=1
	if not value:
		failures+=1
		push_error(label)

func run() -> void:
	check(ClassDB.class_exists("TesselStream"),"The installed native stream registers without a script dependency")
	if not ClassDB.class_exists("TesselStream"):
		quit(1)
		return
	var runtime := Runtime.new()
	runtime.publish_shader_pulse=false
	root.add_child(runtime)
	runtime.beat.connect(func(_a: int,_b: int,_s: float) -> void: heard_beats+=1)
	runtime.accent.connect(func(_a: int,_s: float) -> void: heard_accents+=1)
	check(runtime.begin_session("ash_foundry",81731),"Aschewerk starts the native live synthesis backend")
	check(runtime.native_active and runtime.player.playing,"AudioStreamPlayer owns an active native playback")
	var mix_bus := AudioServer.get_bus_index(runtime.player.bus)
	var capture := AudioEffectCapture.new()
	capture.buffer_length=2.0
	var capture_index := AudioServer.get_bus_effect_count(mix_bus)
	AudioServer.add_bus_effect(mix_bus,capture)
	var metadata := runtime.native_metadata()
	check(int(metadata.get("seed",0))==runtime.theme_seed and float(metadata.get("bpm",0.0))==float(Themes.theme("ash_foundry").bpm),"The native engine receives the deterministic foundry theme")
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec()-start < 1500:
		runtime.tick(1.0/144.0,true)
		await create_timer(1.0/144.0).timeout
	check(int(runtime.native_stream.call("mixed_samples"))>0,"Sample counter advances inside Godot's audio mixer")
	check(runtime.rhythm_frame().active and runtime.clock.audible_seconds>0.0,"The presentation clock follows the audible native output")
	check(heard_beats>=2,"Native output drives actual audible beat notifications")
	check(heard_accents>=1,"Actual synth transients dispatch native accent events")
	check(runtime.clock.pending_count()<64,"The native event queue stays bounded under ordinary playback")
	var recorded := capture.get_buffer(capture.get_frames_available())
	var energy := 0.0
	var finite_pcm := true
	for sample: Vector2 in recorded:
		energy+=sample.length_squared()
		finite_pcm=finite_pcm and sample.is_finite()
	check(recorded.size()>1000 and finite_pcm and energy/maxf(recorded.size(),1)>.000001,"The real Godot mixer contains finite audible native stereo PCM, rather than only an advancing sample counter")
	AudioServer.remove_bus_effect(mix_bus,capture_index)
	runtime.update_game_state({"phase":"attack","wave":15,"enemy_count":22,"core_ratio":1.0,"boss":false,"running":true})
	var state := runtime.get_music_state()
	check(int(state.intensity)==3 and int(state.target_bar)%8==0,"Live gameplay schedules its intensity on the next full phrase")
	var guest := Runtime.new()
	guest.publish_shader_pulse=false
	root.add_child(guest)
	guest.begin_session("ash_foundry",81731)
	guest.apply_music_state(state)
	var guest_deadline := Time.get_ticks_msec()+1000
	while int(guest.native_stream.call("mixed_samples"))==0 and Time.get_ticks_msec()<guest_deadline:
		await create_timer(0.02).timeout
	guest.tick(0.05,true)
	check(guest.native_active and guest.theme_seed==runtime.theme_seed,"A guest independently opens the same native theme")
	check(guest.pending_bar==runtime.pending_bar and guest.pending_intensity==runtime.pending_intensity,"A guest schedules the exact host arrangement boundary")
	check(absf(float(guest.native_stream.call("mixed_samples"))-float(state.mixed_samples))<48000.0,"A joining guest starts near the replicated sample timeline (%d vs %d)"%[guest.native_stream.call("mixed_samples"),state.mixed_samples])
	check(guest._remote_session,"First authoritative music snapshot aligns an already-created guest session")
	runtime.set_music_enabled(false)
	runtime.tick(1.0/60.0,false)
	check(not runtime.rhythm_frame().active and runtime.rhythm_frame().beat_pulse==0.0,"Muting the Music bus immediately clears native-driven motion")
	var before_pause := int(runtime.native_stream.call("mixed_samples"))
	runtime.set_paused(true)
	await create_timer(0.10).timeout
	runtime.tick(0.1,true)
	check(not runtime.rhythm_frame().active,"Paused native playback stops all visible rhythm presentation")
	check(int(runtime.native_stream.call("mixed_samples"))-before_pause<8192,"Pause prevents continued music timeline advancement after buffered audio")
	runtime.set_paused(false)
	runtime.set_music_enabled(true)
	await create_timer(0.1).timeout
	runtime.tick(0.1,true)
	check(runtime.native_stream.call("mixed_samples")>before_pause,"Resuming playback continues the same session sample clock")
	var before_fallback := runtime.get_music_state()
	runtime.set_live_enabled(false)
	check(not runtime.native_active and runtime.session_active,"Disabling live synthesis preserves the logical running musical session")
	runtime.tick(1.25,true)
	var during_fallback := runtime.get_music_state()
	check(during_fallback.mixed_samples>before_fallback.mixed_samples+during_fallback.mix_rate and not runtime.rhythm_frame().active,"Recorded fallback advances the shared timeline without driving a fabricated dance clock")
	runtime.set_live_enabled(true)
	var restored_deadline := Time.get_ticks_msec()+1000
	while int(runtime.native_stream.call("mixed_samples"))==0 and Time.get_ticks_msec()<restored_deadline:
		await create_timer(0.02).timeout
	runtime.tick(0.02,true)
	check(runtime.native_active and absf(float(runtime.native_stream.call("mixed_samples"))-float(during_fallback.mixed_samples))<48000.0,"Re-enabling live synthesis resumes the running arrangement instead of restarting its opening")
	check(runtime.pending_bar==during_fallback.target_bar and runtime.command_serial==during_fallback.command_serial,"Fallback changes preserve the authoritative future phrase and musical command serial")
	runtime.start_preview("radar_highlands",42,120.0,2)
	var preview_deadline:=Time.get_ticks_msec()+1000
	while int(runtime.native_stream.call("mixed_samples"))==0 and Time.get_ticks_msec()<preview_deadline:
		await create_timer(0.02).timeout
	runtime.tick(0.05,true)
	check(float(runtime.native_stream.call("bpm"))==120.0 and runtime.clock.bpm==120.0,"Isolated preview tempo configures both synth and visual clock")
	check(int(runtime.native_metadata().get("intensity",-1))==2,"An isolated preview starts with its actual chosen native arrangement, without an eight-bar wait")
	var preview_seed:=runtime.theme_seed
	runtime.set_preview_intensity(3)
	preview_deadline=Time.get_ticks_msec()+1000
	while int(runtime.native_stream.call("mixed_samples"))==0 and Time.get_ticks_msec()<preview_deadline:
		await create_timer(0.02).timeout
	runtime.tick(0.05,true)
	check(runtime.theme_seed==preview_seed and int(runtime.native_metadata().get("intensity",-1))==3,"Changing lab intensity compares the same seed in the selected native arrangement")
	runtime.start_preview("ash_foundry",90211,-1.0,3,"minimal_techno")
	preview_deadline=Time.get_ticks_msec()+1000
	while int(runtime.native_stream.call("mixed_samples"))==0 and Time.get_ticks_msec()<preview_deadline:
		await create_timer(0.02).timeout
	runtime.tick(0.05,true)
	runtime.update_game_state({"phase":"salvage","running":true})
	var release_state := runtime.get_music_state()
	check(release_state.current_intensity==3 and release_state.intensity==0 and release_state.target_bar>0,"Host snapshots distinguish the currently audible combat bank from a future quiet phrase")
	guest.begin_session("ash_foundry",90211)
	guest.apply_music_state(release_state)
	preview_deadline=Time.get_ticks_msec()+1000
	while int(guest.native_stream.call("mixed_samples"))==0 and Time.get_ticks_msec()<preview_deadline:
		await create_timer(0.02).timeout
	guest.tick(0.05,true)
	check(int(guest.native_metadata().get("intensity",-1))==3 and guest.pending_intensity==0,"A joining guest starts in the actual host combat bank while preserving its later quiet transition")
	check(guest.rhythm_frame().intensity==3,"The cached presentation frame reports the actual native bank before its future transition")
	await preload("res://tests/scene_cleanup.gd").free_scene(runtime,self)
	await preload("res://tests/scene_cleanup.gd").free_scene(guest,self)
	print("LIVE MUSIC NATIVE: %d/%d checks passed"%[checks-failures,checks])
	quit(1 if failures else 0)
