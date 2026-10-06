extends SceneTree
## Actual actor contact presentation, purchases, replicated events and UI mixer.
const Catalog := preload("res://scripts/enemy_audio_catalog.gd")
const UpgradeAudio := preload("res://scripts/upgrade_audio.gd")
const Cleanup := preload("res://tests/scene_cleanup.gd")
class ObservedGame extends "res://scripts/game.gd":
	var sound_requests: Array[String] = []
	func sound(kind: String) -> void:
		sound_requests.append(kind)
		super.sound(kind)
class SaveGate extends Node:
	var writable := true
	func vehicle_unlocked() -> bool: return true
	func can_manage() -> bool: return true
	func commit_research() -> bool: return writable
var checks := 0
var failures := 0
var game: ObservedGame
var capture: AudioEffectCapture

func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children(): freeze(child)

func latest_step() -> AudioStreamPlayer2D:
	var selected: AudioStreamPlayer2D = null
	for voice: AudioStreamPlayer2D in game.audio.movement.voices:
		if selected==null or int(voice.get_meta("serial",0))>int(selected.get_meta("serial",0)): selected = voice
	return selected

func latest_upgrade() -> AudioStreamPlayer:
	var selected: AudioStreamPlayer = null
	for voice: AudioStreamPlayer in game.audio.upgrade_audio.voices:
		if selected==null or int(voice.get_meta("serial",0))>int(selected.get_meta("serial",0)): selected = voice
	return selected

func run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args() or "--no-upnp" not in OS.get_cmdline_user_args():
		push_error("Use --no-profile-save --no-upnp and isolated XDG_DATA_HOME")
		quit(1)
		return
	game = ObservedGame.new()
	root.add_child(game)
	current_scene = game
	game.start(1)
	for frame in 4: await process_frame
	freeze(game)
	game.audio.set_music_volume(0)
	game.audio.set_sfx_volume(1)
	var center: Vector2 = game.camera.get_screen_center_position()
	var movement = game.audio.movement
	check(movement.enemy_streams.size()==32,"Eight families have four separate material banks")
	var total := 0
	for key: String in movement.enemy_streams:
		for stream: AudioStreamWAV in movement.enemy_streams[key]:
			total += 1
			check(stream.mix_rate==48000 and not stream.stereo and stream.get_length()>=.26,"Contact loads as real 48 kHz mono WAV")
	check(total==160,"All 160 generated enemy contacts load")
	for kind: String in EnemyCatalog.GROUND_CLASSES:
		if EnemyCatalog.is_vehicle(kind):
			check(Catalog.contact_key(kind,"dry").is_empty(),"Wheeled vehicles have no walking-bank assignment")
			continue
		var enemy = game._entity("enemy",center,{"kind":kind,"wave":1})
		freeze(enemy)
		for surface: String in Catalog.SURFACES:
			movement.stop_effects()
			var contact_before: int = movement.steps_played
			enemy.wetness._present_footstep(game.weather.surface_effects,game.weather,center,1.0,{"kind":surface,"point":center,"supported":true})
			var expected := Catalog.contact_key(kind,surface)
			var selected := latest_step()
			check(movement.steps_played==contact_before+1 and selected.get_meta("kind")==expected and selected.stream in movement.enemy_streams[expected],kind+" routes its actual actor contact to "+surface)
			check(selected.pitch_scale==1.0 and not bool(selected.get_meta("player")),"Authored enemy timbre is preserved without generic heavy pitch shift")
		enemy.queue_free()
	for family: String in Catalog.FAMILIES:
		var used: Dictionary = {}
		var previous: AudioStream = null
		var no_repeat := true
		for index in 15:
			movement.stop_effects()
			var enemy_kind := ""
			for kind: String in Catalog.CLASS_FAMILIES:
				if Catalog.CLASS_FAMILIES[kind]==family:
					enemy_kind = kind
					break
			game.audio.play_footstep("dry",center,1,false,false,enemy_kind)
			var stream := latest_step().stream
			no_repeat = no_repeat and stream!=previous
			previous = stream
			used[stream.get_instance_id()] = true
		check(no_repeat and used.size()==5,family+" shuffles all five variants without adjacent repeats")
	movement.stop_effects()
	for index in 4: game.audio.play_footstep("metal",center,1,false,true)
	check(not game.audio.play_footstep("metal",center,1,false,false,"colossus"),"Enemy cannot steal any of four protected player footsteps")
	movement.stop_effects()
	check(not game.audio.play_footstep("dry",center+Vector2(1200,0),1,false,false,"runner"),"Distant enemy contacts are culled")
	paused = true
	check(not game.audio.play_footstep("dry",center,1,false,false,"runner"),"World contacts remain silent during research pause")
	var gate := SaveGate.new()
	game.add_child(gate)
	game.expedition = gate
	game.upgrades.points = 100
	game.sound_requests.clear()
	var before: int = game.audio.upgrade_audio.sounds_played
	check(not game.upgrades.purchase("harness") and not game.upgrades.purchase("unknown"),"Invalid/prerequisite-blocked purchases fail")
	check(game.audio.upgrade_audio.sounds_played==before and game.sound_requests.is_empty(),"Failed purchases emit no success cue")
	var effect_bus := AudioServer.get_bus_index("SFX")
	capture = AudioEffectCapture.new()
	capture.buffer_length = 2.0
	var capture_index := AudioServer.get_bus_effect_count(effect_bus)
	AudioServer.add_bus_effect(effect_bus,capture)
	var ids := ["bunker_workshop","weapon_handling","boots","convoy_armor"]
	for branch in 4:
		game.audio.upgrade_audio.stop_effects()
		game.audio.upgrade_audio.last_played = -10000
		capture.clear_buffer()
		check(game.upgrades.purchase(ids[branch]),"Real paused purchase succeeds for branch %d"%branch)
		var kind: String = UpgradeAudio.KINDS[branch]
		var selected := latest_upgrade()
		check(game.sound_requests.back()==kind and selected.get_meta("kind")==kind and selected.stream in game.audio.upgrade_audio.streams[kind],"Purchase emits the correct branch recording")
		check(selected.bus=="SFX" and selected.can_process(),"UI confirmation bypasses the paused acoustic room")
		await create_timer(.24,true,false,true).timeout
		var frames := capture.get_buffer(capture.get_frames_available())
		var energy := 0.0
		for frame: Vector2 in frames: energy += frame.length_squared()
		check(frames.size()>100 and energy/maxf(1,frames.size())>.00001,"Actual paused mixer contains audible branch confirmation")
		if branch==0 and frames.size()>0:
			var recording := AudioStreamWAV.new()
			recording.mix_rate = int(AudioServer.get_mix_rate())
			recording.format = AudioStreamWAV.FORMAT_16_BITS
			recording.stereo = true
			var bytes := PackedByteArray()
			bytes.resize(frames.size()*4)
			for index in frames.size():
				bytes.encode_s16(index*4,roundi(clampf(frames[index].x,-1,1)*32767))
				bytes.encode_s16(index*4+2,roundi(clampf(frames[index].y,-1,1)*32767))
			recording.data = bytes
			recording.save_to_wav("res://artifacts/enemy-tech-audio/paused-base-upgrade.wav")
	game.audio.upgrade_audio.last_played = -10000
	game.network._receive_events([{"category":"sound","payload":{"kind":"tech_upgrade_weapons"}}])
	check(latest_upgrade().get_meta("kind")=="tech_upgrade_weapons","Existing co-op sound event dispatches the same paused UI cue")
	before = game.audio.upgrade_audio.sounds_played
	var points: int = game.upgrades.points
	gate.writable = false
	check(not game.upgrades.purchase("harness") and game.upgrades.points==points and not game.upgrades.has_upgrade("harness"),"Failed research persistence rolls back purchase")
	check(game.audio.upgrade_audio.sounds_played==before,"Save failure produces no confirmation")
	gate.writable = true
	game.audio.set_sfx_volume(0)
	check(not game.audio.play_sound("tech_upgrade_crew") and not latest_upgrade().playing,"SFX mute stops active UI audio and rejects new confirmations")
	check(game.upgrades.purchase("harness") and game.audio.upgrade_audio.sounds_played==before,"Muted successful research changes state without sounding")
	game.audio.set_sfx_volume(1)
	for branch in 4:
		var used: Dictionary = {}
		var previous: AudioStream = null
		var no_repeat := true
		for index in 9:
			game.audio.upgrade_audio.last_played = -10000
			game.audio.play_sound(UpgradeAudio.KINDS[branch])
			var stream := latest_upgrade().stream
			no_repeat = no_repeat and stream!=previous
			previous = stream
			used[stream.get_instance_id()] = true
		check(no_repeat and used.size()==3,"Research branch rotates all three authored variants")
	check(game.audio.upgrade_audio.voices.size()==2 and movement.voices.size()==4 and game.audio.voices.size()==12,"Research and enemy activity preserve bounded independent voice pools")
	AudioServer.remove_bus_effect(effect_bus,capture_index)
	paused = false
	check(await Cleanup.free_scene(game,self),"Active new playback handles release during scene teardown")
	print("ENEMY TECH AUDIO: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
