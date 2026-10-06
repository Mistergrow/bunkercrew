extends SceneTree
## Prepared synthetic input exercises controls. Never opens a physical microphone.
const L := preload("res://scripts/locale_text.gd")
const Cleanup := preload("res://tests/scene_cleanup.gd")
const FakeInput := preload("res://tests/microphone_check_test.gd").FakeInput
const OUTPUT := "res://artifacts/microphone/"
var game
var viewport: SubViewport
var checks := 0
var failures := 0
var screenshots := false
func _initialize() -> void: run.call_deferred()
func check(value: bool,label: String) -> void:
	checks += 1
	print("MIC UI %s: %s" % ["PASS" if value else "FAIL",label])
	if not value:
		failures += 1
		push_error(label)
func frames(count: int=3) -> void:
	for unused in count: await process_frame
func capture(label: String) -> void:
	if not screenshots: return
	await frames()
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	check(image.get_size()==Vector2i(2560,1440) and image.save_png(OUTPUT+label+".png")==OK,label+" native QHD saved")
func widths(panel: Control) -> void:
	var fits := true
	for child in panel.get_children():
		if not child is Button or child.text.is_empty(): continue
		var value: String=child.tr(child.text)
		var extent: float=UiArt.FONT.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,child.get_theme_font_size("font_size")).x
		if extent > child.size.x-32:
			print("BUTTON OVERFLOW ",value,": ",extent," / ",child.size.x-32)
			fits=false
	check(fits,"Localized microphone controls fit their bounds: "+L.current_locale())
func run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args():
		quit(2)
		return
	screenshots="--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name()!="headless"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	root.size=Vector2i(1440,900)
	root.content_scale_size=Vector2i(1440,900)
	if screenshots:
		viewport=SubViewport.new()
		viewport.size=Vector2i(2560,1440)
		viewport.size_2d_override=Vector2i(1600,900)
		viewport.size_2d_override_stretch=true
		viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
		viewport.world_2d=World2D.new()
		root.add_child(viewport)
	L.set_locale("de",false)
	game=load("res://scenes/main.tscn").instantiate()
	if screenshots: viewport.add_child(game)
	else: root.add_child(game)
	await frames()
	game.combat_events.persistence_enabled=false
	game.audio.set_music_volume(0)
	game.voice.set_enabled(false)
	check(not game.microphone.capturing,"Real main scene starts with microphone off")
	var original=game.microphone
	game.microphone=FakeInput.new()
	game.add_child(game.microphone)
	game.microphone.set_process(false)
	game.microphone.samples_ready.connect(game.voice._samples)
	original.queue_free()
	game.hud._toggle_audio()
	await frames()
	var open_button: Button
	for button in game.hud.buttons:
		if button.text=="MIKROFON & SPRACHCHAT": open_button=button
	check(is_instance_valid(open_button),"F4 exposes visible microphone navigation")
	await capture("de-audio-settings")
	open_button.pressed.emit()
	await frames()
	var panel=game.hud.microphone_panel
	check(is_instance_valid(panel) and game.hud.overlay=="microphone" and not game.microphone.capturing,"Opening panel never activates capture")
	check(not panel.activate_button.disabled and panel.record_button.disabled and panel.playback_button.disabled,"Inactive controls expose deliberate activation")
	widths(panel)
	await capture("de-microphone-off")
	panel.device_select.item_selected.emit(1)
	check(game.microphone.selected_device=="Test microphone" and not game.microphone.capturing,"Selecting a device leaves capture off")
	panel.activate_button.pressed.emit()
	await frames()
	check(game.microphone.capturing and game.microphone.active_owner=="check","Activation button acquires local exclusive input")
	panel.gain_slider.value=1.5
	check(game.microphone.input_gain==1.5,"Gain slider controls backend")
	var input := PackedVector2Array()
	input.resize(800)
	input.fill(Vector2(.16,.16))
	game.microphone._consume_frames(input)
	var panel_id: int=panel.get_instance_id()
	L.set_locale("en",false)
	await frames()
	check(panel.get_instance_id()==panel_id and game.microphone.capturing and game.microphone.selected_device=="Test microphone","Live locale switching preserves selected device and active check")
	widths(panel)
	check(panel.activate_button.text=="Turn microphone off","Active English button uses complete catalog")
	await capture("en-microphone-level")
	panel.record_button.pressed.emit()
	game.microphone._consume_frames(input)
	panel.record_stop_button.pressed.emit()
	await frames()
	check(not game.microphone.recording and game.microphone.recorded_seconds>0 and not panel.playback_button.disabled,"Record and stop buttons make a bounded sample available")
	panel.playback_button.pressed.emit()
	check(game.microphone.playing and not game.microphone.capturing,"Playback button disables actual input")
	var playback_ref: WeakRef=weakref(game.microphone._playback.get_stream_playback())
	game.microphone.stop_playback()
	panel.voice_toggle.set_pressed(true)
	check(game.voice.enabled,"Voice checkbox controls the shared voice backend")
	panel.partner_slider.value=.35
	panel.mute_toggle.set_pressed(true)
	check(is_equal_approx(game.voice.output_volume,.35) and game.voice.remote_muted,"Partner volume and mute affect voice backend")
	panel.activate_button.pressed.emit()
	game.microphone._consume_frames(PackedVector2Array([Vector2(1,1)]))
	L.set_locale("de",false)
	await capture("de-microphone-clipping")
	game.hud._toggle_audio()
	check(not game.microphone.capturing and game.microphone._samples.is_empty() and not game.microphone.playing,"F4 exit immediately stops and erases local test")
	await frames()
	check(game.hud.overlay=="audio" and not is_instance_valid(game.hud.microphone_panel),"F4 returns to audio settings")
	game.hud._open_microphone()
	await frames()
	panel=game.hud.microphone_panel
	panel.activate_button.pressed.emit()
	game.microphone.hardware=PackedStringArray(["Default"])
	game.microphone._refresh_devices()
	await frames()
	check(not game.microphone.capturing and panel.device_select.item_count==1,"Hotplug updates real device menu and closes input")
	L.set_locale("en",false)
	await capture("en-microphone-device-change")
	game.hud._close_microphone()
	await frames()
	game.start_scenario(2,{"environment":"sector07","position":"left","build_type":"bastion"})
	game.rounds.running=false
	game.rounds.set_process(false)
	for worker in game.players: worker.set_physics_process(false)
	game.network.set_process(false)
	game.voice.set_process(false)
	game.network.active=true
	game.network.state="playing"
	game.network.is_host=true
	game.network.peer_connected=true
	game.voice.enabled=true
	game.voice.speaking=true
	game.voice.remote_speaking=true
	game.hud.overlay=""
	paused=false
	await frames()
	await capture("en-voice-indicators")
	game.network.state="lobby"
	game.network.room_code="XXXX-XXXX-XXXX-XXXX-XXXX"
	game.hud.overlay="network"
	await frames()
	var code_width: float=UiArt.FONT.get_string_size(game.network.room_code,HORIZONTAL_ALIGNMENT_LEFT,-1,24).x
	check(game.network.room_code.length()==24 and code_width<720,"Maximum 24-character direct code fits before copy control")
	await capture("en-long-direct-code")
	game.hud._toggle_audio()
	await frames()
	check(game.hud.overlay=="audio" and game.hud.audio_return_overlay=="network","F4 settings remain open in an active lobby")
	game.hud._open_microphone()
	await frames()
	check(game.hud.overlay=="microphone" and not game.microphone.capturing,"Lobby microphone panel opens without input or connection reset")
	game.hud._close_microphone()
	game.hud._close_audio()
	await frames()
	check(game.hud.overlay=="network" and game.network.active,"Closing settings returns to the same online lobby")
	game.network.active=false
	game.voice.set_enabled(false)
	game.voice.set_remote_muted(false)
	game.voice.set_output_volume(1)
	paused=false
	await Cleanup.free_scene(game,self)
	var deadline:=Time.get_ticks_msec()+3000
	while playback_ref.get_ref()!=null and Time.get_ticks_msec()<deadline: await process_frame
	L.set_locale("de",false)
	print("Microphone UI: %d/%d checks passed" % [checks-failures,checks])
	quit(1 if failures else 0)
