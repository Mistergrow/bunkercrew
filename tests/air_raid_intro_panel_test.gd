extends SceneTree
## Real intro signals, native controls and AudioServer mix; no GPU or profiles.
const Catalog := preload("res://scripts/air_raid_intro_catalog.gd")
const Cleanup := preload("res://tests/scene_cleanup.gd")
var game: Node
var panel: Control
var intro: Node
var checks := 0
var failures := 0
var capture: AudioEffectCapture

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	print("PASS " if value else "FAIL ",label)
	if not value:
		failures += 1
		push_error(label)

func frames(count: int=3) -> void:
	for frame in count: await process_frame

func key(code: Key) -> void:
	for down in [true,false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = down
		Input.parse_input_event(event)
		await process_frame
	await frames()

func wall_time(seconds: float) -> void:
	var until := Time.get_ticks_usec()+roundi(seconds*1000000)
	while Time.get_ticks_usec()<until: await process_frame

func sample() -> float:
	await wall_time(.16)
	capture.clear_buffer()
	await wall_time(.45)
	var data := capture.get_buffer(capture.get_frames_available())
	var energy := 0.0
	for frame in data: energy += frame.length_squared()
	return sqrt(energy/maxf(1.0,float(data.size())*2.0))

func begin(character: String, locale: String) -> void:
	# Explicit identity fixture: production selection still runs through the
	# roster/menu. This suite verifies its selected worker is used exclusively.
	LocaleText.set_locale(locale,false)
	game.players[0].character_id = character
	game.selected_characters[0] = character
	game.campaign.air_raid_intro_seen = false
	intro.seen = false
	game.hud.overlay = ""
	paused = false
	var roster := EnemyCatalog.wave_roster(7,Balance.WAVE_COUNTS[6],true)
	var index := roster.find("scout_drone")
	check(intro.before_spawn(7,index,roster.size()),"%s/%s enters via actual controller signal"%[locale,character])
	await frames()

func run() -> void:
	if not "--no-profile-save" in OS.get_cmdline_user_args():
		push_error("Run with --no-profile-save")
		quit(1)
		return
	root.size = Vector2i(1440,900)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.start_scenario(1,{"environment":"ash_foundry","build_type":"bastion","position":"left"})
	game.rounds.set_process(false)
	game.set_process(false)
	game.story.set_process(false)
	game.dialogue.set_process(false)
	game.dialogue.reset()
	game.rounds.wave = 7
	game.flak_station.unlock()
	var worker: Node = game.players[0]
	worker.inventory = {"steel":3,"concrete":2,"ammo":1}
	for transfer in 6: game.flak_station.interact(worker,Balance.TRANSFER_TIME)
	game.flak_station.interact(worker,3.0)
	game.rounds.phase = "build"
	game.rounds.begin_warning()
	game.rounds._begin_attack()
	intro = game.air_raid_intro
	intro.set_process(false)
	panel = game.hud.air_raid_panel
	# Capture before Master output, which stays muted throughout this test.
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"),true)
	game.audio.set_voice_volume(1.0)
	var bus := AudioServer.get_bus_index("Voice")
	var effect_index := AudioServer.get_bus_effect_count(bus)
	capture = AudioEffectCapture.new()
	capture.buffer_length = 2.0
	AudioServer.add_bus_effect(bus,capture)
	await frames()
	var flyover_exists := ResourceLoader.exists("res://assets/audio/air_raid_flyover_v1.wav")
	check(flyover_exists or "--allow-missing-flyover" in OS.get_cmdline_user_args(),"Generated flyover is available as an imported game sound")
	for character: String in ["mara","branko","ivo","nora","levin","selma","oskar","rika"]:
		for locale: String in ["de","en"]:
			await begin(character,locale)
			var expected := Catalog.line(character)
			check(panel.visible and paused and panel.dialogue.speaker_id==expected.speaker_id and panel.dialogue.portrait_id==expected.portrait_id and panel.caption_label.text==expected.text and panel.speaker_label.text==expected.speaker_name,"%s/%s shows only selected identity and matching subtitle"%[locale,character])
			check(not panel.voice.playing and not panel.skip_button.visible,"%s/%s starts with timed voice delay and input grace"%[locale,character])
			intro.advance(1.3)
			await frames()
			check(panel.voice.playing and not panel.voice.stream_paused and panel.voice.can_process() and panel.voice.stream.resource_path==expected.voice_path and game.audio._dialogue_sources.air_intro,"%s/%s starts its own recording while the world remains paused"%[locale,character])
			if character in ["mara","oskar"]:
				var before: float = panel.voice.get_playback_position()
				var energy := await sample()
				check(energy>.002 and panel.voice.get_playback_position()>before+.3,"%s voice reaches the real audio mixer and advances during pause (RMS %.5f)"%[locale,energy])
			if flyover_exists:
				check(panel.flyover.playing and panel.flyover.can_process() and panel.flyover.stream.loop_mode==AudioStreamWAV.LOOP_FORWARD and panel.flyover.stream.loop_end>0,"%s/%s flyover is a finite-source loop that plays during pause"%[locale,character])
			# This is the native button's production signal connection. Actual
			# physical mouse hit testing belongs to the separate GPU preview.
			panel.skip_button.pressed.emit()
			await frames()
			check(not intro.active and not panel.visible and not panel.voice.playing and not panel.flyover.playing and not game.audio._dialogue_sources.air_intro and not paused,"%s/%s native skip callback stops only intro audio and releases pause"%[locale,character])
	await begin("ivo","de")
	intro.advance(1.3)
	await frames()
	game.audio.set_dialogue_active(true,"story")
	game.dialogue._ducked = true
	game.dialogue._set_ducked(false)
	check(game.audio._dialogue_active and game.audio._dialogue_sources.air_intro and not game.audio._dialogue_sources.story,"Pausing ordinary story speech cannot release the intro music duck")
	game.audio.set_dialogue_active(true,"story")
	LocaleText.set_locale("en",false)
	await frames()
	var english := Catalog.line("ivo")
	check(panel.dialogue.locale=="en" and panel.caption_label.text==english.text and panel.voice.stream.resource_path==english.voice_path and panel.voice.playing and not panel.voice.stream_paused,"Locale switch replaces subtitle and recording with the same selected English speaker")
	var reduced: bool = game.weather.reduced_effects
	await key(KEY_F3)
	check(game.weather.reduced_effects!=reduced and panel._reduced==game.weather.reduced_effects and intro.active and paused,"F3 changes intro effects without releasing the world pause")
	await key(KEY_F11)
	check(intro.active and paused and game.hud.overlay=="air_raid_intro","F11 display shortcut does not skip or open a gameplay menu")
	for code: Key in [KEY_F2,KEY_F4,KEY_F5,KEY_T,KEY_P,KEY_F1,KEY_N]: await key(code)
	check(intro.active and paused and game.player_count==1 and game.hud.overlay=="air_raid_intro" and not is_instance_valid(game.hud.options_panel),"HUD shortcuts cannot open options, join, restart or alter the active intro")
	intro.elapsed = 7.0
	panel._process(0)
	LocaleText.set_locale("de",false)
	check(intro.duration<=12.0,"External late locale switch grants bounded reading time, at most twelve seconds")
	intro.elapsed = float(intro.duration)-.1
	panel._process(0)
	LocaleText.set_locale("en",false)
	check(intro.duration==12.0 and panel.dialogue.locale=="en","Repeated late locale switches cannot extend presentation beyond the hard cap")
	panel.skip_button.pressed.emit()
	await frames()
	check(game.audio._dialogue_active and game.audio._dialogue_sources.story and not game.audio._dialogue_sources.air_intro,"Intro end retains another active owner's music duck")
	game.audio.set_dialogue_active(false,"story")
	await begin("selma","en")
	intro.advance(1.3)
	await frames()
	game.audio.set_voice_volume(0.0)
	check(panel.caption_label.visible and not panel.caption_label.text.is_empty() and panel.voice.playing,"Muted voice keeps selected speaker and readable subtitle")
	intro.advance(8.0)
	await frames()
	check(not panel.voice.playing and not panel.flyover.playing and not game.audio._dialogue_active and not panel.visible and not paused,"Automatic end also clears both intro audio streams and its duck")
	game.audio.set_voice_volume(1.0)
	await begin("nora","de")
	intro.advance(1.3)
	await frames()
	var voice_ref: WeakRef = weakref(panel.voice)
	var flyover_ref: WeakRef = weakref(panel.flyover)
	AudioServer.remove_bus_effect(bus,effect_index)
	check(await Cleanup.free_scene(game,self),"Exiting an active intro releases real scene/audio playback cleanly")
	check(voice_ref.get_ref()==null and flyover_ref.get_ref()==null,"No intro voice or looping flyover survives scene teardown")
	LocaleText.set_locale("de",false)
	print("AIR RAID INTRO PANEL: %d/%d checks passed"%[checks-failures,checks])
	quit(0 if failures==0 else 1)
