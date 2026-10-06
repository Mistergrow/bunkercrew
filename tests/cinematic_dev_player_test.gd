extends SceneTree
## Native UI, recorded voices and production adapters; no player profile writes.
const Player := preload("res://scripts/cinematic_dev_player.gd")
const Cleanup := preload("res://tests/scene_cleanup.gd")
const OUT := "res://artifacts/cinematic-dev-player-20261004/"
var checks:=0
var failures:=0
var game: Node
var player: CanvasLayer

func _initialize() -> void: _run.call_deferred()

func check(ok: bool,label: String) -> void:
	checks+=1
	print("CINEMATIC PLAYER %s: %s"%["PASS" if ok else "FAIL",label])
	if not ok: failures+=1; push_error(label)

func frames(count: int=3) -> void:
	for _index in count: await process_frame

func key(code: Key) -> void:
	for down: bool in [true,false]:
		var event:=InputEventKey.new()
		event.keycode=code
		event.physical_keycode=code
		event.pressed=down
		Input.parse_input_event(event)
		await process_frame
	await frames()

func action(name: String) -> void:
	for down: bool in [true,false]:
		var event:=InputEventAction.new()
		event.action=name
		event.pressed=down
		Input.parse_input_event(event)
		await process_frame
	await frames()

func wall_time(seconds: float) -> void:
	var until:=Time.get_ticks_usec()+roundi(seconds*1000000)
	while Time.get_ticks_usec()<until: await process_frame

func _run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args() or "--no-upnp" not in OS.get_cmdline_user_args(): quit(2); return
	root.size=Vector2i(1440,900)
	var original_locale:=LocaleText.current_locale()
	game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene=game
	await frames(6)
	game.hud._toggle_audio()
	await frames()
	game.hud.options_panel.select_tab(3)
	await frames()
	var options: Control=game.hud.options_panel
	var original_campaign: Dictionary=game.campaign.checkpoint().duplicate(true)
	var original_characters: Array=game.selected_characters.duplicate()
	var original_paused:=paused
	var original_scale:=Engine.time_scale
	var original_audio_processing: bool=game.audio.is_processing()
	var original_volume: Array=[game.audio.music_volume,game.audio.sfx_volume,game.audio.voice_volume]
	var original_buses: Array=[]
	for name: String in ["Master","Music","SFX","Voice"]:
		var index:=AudioServer.get_bus_index(name)
		original_buses.append([AudioServer.get_bus_volume_db(index),AudioServer.get_bus_effect_count(index),AudioServer.is_bus_mute(index)])
	var menu_player: AudioStreamPlayer=game.audio.menu_music.player
	var original_handle:=menu_player.get_stream_playback().get_instance_id() if menu_player.has_stream_playback() else 0
	var original_music_position:=menu_player.get_playback_position()
	var original_live_paused: bool=game.audio.live_music._paused
	options.cinematic_player_button.grab_focus()
	options.cinematic_player_button.pressed.emit()
	await frames()
	player=options.cinematic_player
	player.set_process(false)
	check(is_instance_valid(player) and options.has_modal_subpanel() and game.hud.overlay=="audio" and not options.back_button.visible,"Actual menu-only Options entry opens one contained modal")
	check(player.preview_view.world_2d!=game.get_viewport().world_2d and player.preview_world.preview_game!=game,"Production adapters have their own World2D and inert preview game")
	check(not game.audio.is_processing() and menu_player.stream_paused and game.audio.live_music._paused,"Original music pauses without destroying its decoder")
	await wall_time(.15)
	check(absf(menu_player.get_playback_position()-original_music_position)<.09 and (not menu_player.has_stream_playback() or menu_player.get_stream_playback().get_instance_id()==original_handle),"Opening retains original track position and decoder")
	check(not player.playing and not player.voice.playing and not player.air_flyover.playing and not player.travel_sound.ambient_voice.playing,"Opening remains silent until explicitly played")
	for locale: String in ["de","en"]:
		LocaleText.set_locale(locale,false)
		for id: String in Player.SCENES:
			player.select_scene(id)
			for definition: Dictionary in CharacterCatalog.CHARACTERS:
				player.character_id=str(definition.id)
				player._refresh_context(true)
				player.seek(2.25)
				var expected: Dictionary=AirRaidIntroCatalog.line(player.character_id) if id=="air_raid" else preload("res://scripts/travel_cinematic_catalog.gd").context(str(Player.DESTINATIONS[id]),player.character_id,[player.character_id]).dialogue
				check(player.context.dialogue.locale==locale and player.context.dialogue.speaker_id==expected.speaker_id and player.preview_world.subtitle_text()==expected.text,"%s/%s/%s selected-language recording and subtitle"%[locale,id,player.character_id])
				check(not player.playing and not player.voice.playing and not player.preview_world.air_panel.voice.playing and not player.preview_world.air_panel.flyover.playing,"%s/%s/%s seeking never starts any audio"%[locale,id,player.character_id])
	check(player.scene_choice.item_count==4 and player.character_choice.item_count==8 and player.environment_choice.item_count==13,"All four scenes, eight figures and thirteen backgrounds are available")
	player.select_scene("signal")
	player.character_id="mara"
	player._refresh_context(true)
	var voice_at: float=player._voice_at()
	player.seek(voice_at+.15)
	var starts: int=player.voice_starts
	var voice_bus:=AudioServer.get_bus_index("Voice")
	var capture:=AudioEffectCapture.new()
	capture.buffer_length=1.0
	var effect_index:=AudioServer.get_bus_effect_count(voice_bus)
	AudioServer.add_bus_effect(voice_bus,capture)
	var master_muted:=AudioServer.is_bus_mute(0)
	AudioServer.set_bus_mute(0,true)
	player.set_playing(true)
	await wall_time(.05)
	check(player.voice.playing and player.voice_starts==starts+1 and player.voice.bus==&"Voice" and player.travel_sound.ambient_voice.bus==&"SFX","Resume uses real recording at selected offset through Voice/SFX buses")
	capture.clear_buffer()
	await wall_time(.12)
	var samples:=capture.get_buffer(capture.get_frames_available())
	var energy:=0.0
	for sample: Vector2 in samples: energy+=sample.length_squared()
	var rms:=sqrt(energy/maxf(1.0,float(samples.size())*2.0))
	check(rms>.00005 and player.voice.get_playback_position()>.15,"Recording reaches native mixer (RMS %.6f)"%rms)
	player.set_playing(false)
	var paused_position: float=player.voice.get_playback_position()
	await wall_time(.12)
	check(player.voice.stream_paused and absf(player.voice.get_playback_position()-paused_position)<.04,"Pause freezes genuine voice without replay")
	player.set_playing(true)
	check(player.voice_starts==starts+1 and not player.voice.stream_paused,"Resume continues same decoder exactly once")
	AudioServer.remove_bus_effect(voice_bus,effect_index)
	AudioServer.set_bus_mute(0,master_muted)
	player.set_playing(false)
	for rate: float in Player.SPEEDS:
		player.seek(.2)
		player.set_speed(rate)
		player.set_playing(true)
		player.advance(.1)
		check(is_equal_approx(player.elapsed,.2+.1*rate) and is_equal_approx(player.voice.pitch_scale,rate) and is_equal_approx(player.travel_sound.ambient_voice.pitch_scale,rate),"%.2fx animation and audio share exact speed"%rate)
	check(not player.set_speed(NAN) and not player.set_speed(3.0) and not player.select_scene("unknown"),"Invalid and nonfinite configuration is rejected")
	player.seek(NAN)
	check(is_finite(player.elapsed),"Nonfinite seek cannot corrupt timeline")
	player.set_speed(1.0)
	player.select_scene("storm")
	player.restart()
	for step: float in [.25,.25,.25,.25,.2]: player.advance(step)
	var cues: int=player.travel_sound.cues_played
	check(cues>=2 and player.voice.playing,"Natural traversal starts storm impact cues and selected voice")
	for value: float in [1.2,1.25,2.0,3.0,1.2,4.0]: player.seek(value)
	check(player.travel_sound.cues_played==cues and not player.travel_sound.ambient_voice.playing and player.travel_sound.cue_voices.all(func(cue):return not cue.playing),"Repeated slider movement remains silent and never replays oneshots")
	player.seek(2.0)
	player.set_playing(true)
	player.advance(.1)
	check(player.travel_sound.cues_played==cues and player.travel_sound.ambient_voice.playing,"Resume after cue keeps consumed oneshots and restarts bed at offset")
	player.set_muted(true)
	check(player.voice.volume_db==-80.0 and not player.travel_sound.ambient_voice.playing,"Mute silences only owned preview players")
	player.advance(.1)
	player.set_muted(false)
	player.advance(.1)
	check(player.voice.volume_db==0.0 and player.travel_sound.ambient_voice.playing,"Unmute restores scene sound without changing global buses")
	player.seek(2.75)
	player.subtitle_button.toggled.emit(false)
	check(player.preview_world.subtitle_text().is_empty() and not player.preview_world.travel_caption.visible,"Subtitle switch only affects preview")
	player.subtitle_button.toggled.emit(true)
	player.select_scene("air_raid")
	player.restart()
	player.advance(.2)
	check(player.air_flyover.playing and player.air_flyover.stream.loop_mode==AudioStreamWAV.LOOP_FORWARD and not player.travel_sound.ambient_voice.playing,"Air preview reuses looping flyover and stops roadside ambience")
	player.seek(7.99)
	player.set_playing(true)
	player.advance(.2)
	check(not player.playing and not player.voice.playing and not player.air_flyover.playing and not player.travel_sound.ambient_voice.playing and player.elapsed==8.0,"Natural end stops every owned sound at exact final frame")
	player.timeline.grab_focus()
	await key(KEY_TAB)
	check(player.shell.is_ancestor_of(root.gui_get_focus_owner()),"Tab focus stays inside modal")
	await action("ui_down")
	check(player.shell.is_ancestor_of(root.gui_get_focus_owner()),"Controller direction stays inside modal")
	player.scene_choice.get_popup().popup()
	await key(KEY_ESCAPE)
	check(is_instance_valid(options.cinematic_player) and not player.scene_choice.get_popup().visible,"Back first closes native selector popup")
	for code: Key in [KEY_F7,KEY_F1,KEY_F5,KEY_SPACE,KEY_N,KEY_P]: await key(code)
	check(is_instance_valid(options.cinematic_player) and game.hud.overlay=="audio" and not game.started and not is_instance_valid(game.hud.social_panel),"Global shortcuts cannot modify hidden game or open second modal")
	check(game.campaign.checkpoint()==original_campaign and game.selected_characters==original_characters and game.audio.music_volume==original_volume[0] and game.audio.sfx_volume==original_volume[1] and game.audio.voice_volume==original_volume[2] and paused==original_paused and Engine.time_scale==original_scale,"Campaign, chosen crew, gains, pause and engine speed stay unchanged")
	var buses_unchanged:=true
	for index in original_buses.size():
		var bus_index:=AudioServer.get_bus_index(["Master","Music","SFX","Voice"][index])
		buses_unchanged=buses_unchanged and original_buses[index]==[AudioServer.get_bus_volume_db(bus_index),AudioServer.get_bus_effect_count(bus_index),AudioServer.is_bus_mute(bus_index)]
	check(buses_unchanged,"Bus faders, effect chains and mute states remain unchanged")
	var owned_voice: WeakRef=weakref(player.voice)
	var owned_world: WeakRef=weakref(player.preview_world)
	var owned_sound: WeakRef=weakref(player.travel_sound)
	await key(KEY_F4)
	check(not is_instance_valid(options.cinematic_player) and options.back_button.visible and root.gui_get_focus_owner()==options.cinematic_player_button,"F4 closes preview and restores exact Options opener")
	check(owned_voice.get_ref()==null and owned_world.get_ref()==null and owned_sound.get_ref()==null,"Every owned world and audio player is freed")
	check(game.audio.is_processing()==original_audio_processing and game.audio.live_music._paused==original_live_paused and not menu_player.stream_paused and menu_player.get_stream_playback().get_instance_id()==original_handle,"Source music resumes without decoder replacement")
	for command: String in ["ui_cancel","pause"]:
		options._open_cinematic_player()
		await frames()
		await action(command)
		check(not is_instance_valid(options.cinematic_player) and game.hud.overlay=="audio","%s closes preview via actual input action"%command)
	options._open_cinematic_player()
	await frames()
	player=options.cinematic_player
	player.close()
	player.close()
	await frames()
	check(not options.has_modal_subpanel(),"Repeated close is idempotent")
	options._open_cinematic_player()
	await frames()
	player=options.cinematic_player
	var during_teardown: WeakRef=weakref(player)
	game.hud._close_audio()
	await frames()
	check(during_teardown.get_ref()==null and game.audio.is_processing()==original_audio_processing,"Parent Options teardown closes root-parented preview")
	# Respect another tool's pre-existing disabled processing and music pause.
	game.audio.set_process(false)
	game.audio.live_music.set_paused(true)
	menu_player.stream_paused=true
	player=Player.new()
	player.show_for_game(game)
	root.add_child(player)
	await frames()
	player.close()
	await frames()
	check(not game.audio.is_processing() and game.audio.live_music._paused and menu_player.stream_paused,"Closing preserves pre-existing paused music and disabled Audio processing")
	game.audio.live_music.set_paused(false)
	check(game.audio.live_music.start_preview("ash_foundry",71),"Real native Music source prepares independent stream-pause fixture")
	await wall_time(.06)
	game.audio.live_music.player.stream_paused=true
	player=Player.new()
	player.show_for_game(game)
	root.add_child(player)
	await frames()
	player.close()
	await frames()
	check(not game.audio.live_music._paused and game.audio.live_music.player.stream_paused,"Independent raw stream pause and native clock pause both restore exactly")
	game.audio.live_music.end_session()
	game.audio.live_music.set_paused(original_live_paused)
	menu_player.stream_paused=false
	game.audio.set_process(original_audio_processing)
	check(await Cleanup.free_scene(game,self),"Source scene releases cleanly")
	player=Player.new()
	root.add_child(player)
	await frames()
	check(player.context.id=="signal" and not player.playing,"Standalone preview works without source game")
	player.close()
	await frames()
	LocaleText.set_locale(original_locale,false)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	FileAccess.open(OUT+"test-result.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"prepared_state":"Actual menu Options, no match. Deliberately controlled scene clocks; eight DE/EN identity fixtures preview-only, never unlocked. Actual Voice mixer original gains, temporary restored Master mute. No network/profile/save writes."},"\t"))
	print("CINEMATIC PLAYER: %d/%d checks passed"%[checks-failures,checks])
	quit(1 if failures else 0)
