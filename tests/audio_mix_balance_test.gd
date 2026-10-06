extends SceneTree
## Real Dummy mixer taps: music, nearby weapon actions, battle bed and final output.
const OUTPUT := "res://artifacts/audio-remix"
const CLEANUP := preload("res://tests/scene_cleanup.gd")
var game: Node2D
var audio: Node
var checks := 0
var failures := 0
var taps: Dictionary = {}
var results: Dictionary = {}

func _initialize() -> void: run.call_deferred()
func check(value: bool, label: String) -> void:
	checks += 1
	print("MIX %s: %s" % ["PASS" if value else "FAIL",label])
	if not value:
		failures += 1
		push_error(label)

func freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children(): freeze(child)

func tap(title: String, destination: String, at: int=-1) -> void:
	AudioServer.add_bus(at)
	var index := AudioServer.bus_count-1 if at<0 else at
	AudioServer.set_bus_name(index,title)
	AudioServer.set_bus_send(index,destination)
	var effect := AudioEffectCapture.new()
	effect.buffer_length = 6.0
	AudioServer.add_bus_effect(index,effect)
	taps[title] = effect

func emit(kind: String, point: Vector2, action: bool, legacy: bool) -> void:
	audio.cooldowns.clear()
	audio._variant_bags[kind] = [0]
	if not audio.play_sound_at(kind,point):
		check(false,"A scheduled battle sound was rejected: "+kind)
		return
	var selected: AudioStreamPlayer = null
	for voice in audio.voices:
		if int(voice.get_meta("serial",0)) == audio._voice_serial: selected = voice
	if legacy and action:
		selected.volume_db = -14.0 if kind=="cannon" else -7.0
	# These transparent taps keep the room return, effects slider and final limiter.
	AudioServer.set_bus_send(AudioServer.get_bus_index(selected.bus),"MixActions" if action else "MixBattle")

func stats(samples: PackedVector2Array, gain: float=1.0, start: float=0.0, end: float=99.0) -> Dictionary:
	var power := 0.0
	var peak := 0.0
	var count := 0
	var rate := AudioServer.get_mix_rate()
	for index in range(mini(samples.size(),int(start*rate)),mini(samples.size(),int(end*rate))):
		var value := samples[index]*gain
		power += value.length_squared()
		peak = maxf(peak,maxf(absf(value.x),absf(value.y)))
		count += 1
	return {"rms":sqrt(power/maxf(1,count*2)),"peak":peak,"frames":count}

func save(path: String, samples: PackedVector2Array) -> void:
	var stream := AudioStreamWAV.new()
	stream.mix_rate = roundi(AudioServer.get_mix_rate())
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.stereo = true
	var bytes := PackedByteArray()
	bytes.resize(samples.size()*4)
	for index in samples.size():
		bytes.encode_s16(index*4,roundi(clampf(samples[index].x,-1,1)*32767))
		bytes.encode_s16(index*4+2,roundi(clampf(samples[index].y,-1,1)*32767))
	stream.data = bytes
	check(stream.save_to_wav(ProjectSettings.globalize_path(path))==OK,"Mixer WAV saved: "+path.get_file())

func record(legacy: bool) -> void:
	var name := "previous-gain" if legacy else "rebalanced"
	for voice in audio.voices: voice.stop()
	audio._handling_duck_left=0.0
	audio._handling_duck_target=0.0
	audio._handling_duck_db=0.0
	audio._score_level=-7.0
	audio.music_blend=1.0
	audio._last_blend=-1.0
	audio._process(.01)
	audio.music_player.play(4.0)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"),linear_to_db(.45)+(0.0 if legacy else audio.MUSIC_MIX_TRIM_DB))
	await create_timer(.15).timeout
	for effect in taps.values(): effect.clear_buffer()
	var master_capture: AudioEffectCapture = AudioServer.get_bus_effect(0,AudioServer.get_bus_effect_count(0)-1)
	master_capture.clear_buffer()
	var events: Array = []
	for index in 16: events.append({"at":.05+index*.16,"kind":"enemy_shot","action":false})
	for index in 7: events.append({"at":.12+index*.37,"kind":"impact_metal","action":false})
	for at in [.46,1.42,2.30]: events.append({"at":at,"kind":"explosion","action":false})
	for at in [.16,.38,.59]: events.append({"at":at,"kind":"cannon","action":true})
	for phase in [{"at":.88,"kind":"open"},{"at":1.384,"kind":"load"},{"at":1.93,"kind":"close"}]:
		events.append({"at":phase.at,"kind":"reload_cannon_"+phase.kind,"action":true})
	events.sort_custom(func(a,b): return a.at<b.at)
	var start := Time.get_ticks_usec()
	var last := start
	var minimum_score := -7.0
	while float(Time.get_ticks_usec()-start)/1000000.0<2.9:
		var now := Time.get_ticks_usec()
		var elapsed := float(now-start)/1000000.0
		while not events.is_empty() and events[0].at<=elapsed:
			var event: Dictionary = events.pop_front()
			var origin: Vector2 = Vector2(1390,388) if not event.action else game.turret.handling_sound_position()
			if legacy and event.kind=="cannon": origin=game.turret.global_position
			emit(event.kind,origin,event.action,legacy)
		if legacy:
			audio._handling_duck_left=0.0
			audio._handling_duck_db=0.0
			audio._handling_duck_target=0.0
		audio._process(float(now-last)/1000000.0)
		minimum_score=minf(minimum_score,audio._score_level)
		last=now
		await create_timer(.01).timeout
	var captured := {}
	for title in taps: captured[title]=taps[title].get_buffer(taps[title].get_frames_available())
	var master := master_capture.get_buffer(master_capture.get_frames_available())
	var music := stats(captured.MixMusic,1.0,.88,2.26)
	var action := stats(captured.MixActions,.65,.88,2.26)
	var battle := stats(captured.MixBattle,.65,.88,2.26)
	var ratio := linear_to_db(action.rms/maxf(.0000001,music.rms))
	print("MEASURE ",name," score=",minimum_score," source=",game.turret.handling_sound_position()," listener=",audio.acoustics.listener_position," duck=",audio._handling_duck_target)
	results[name]={"music":music,"action":action,"battle":battle,"master":stats(master),"action_music_db":ratio,"minimum_score_db":minimum_score}
	save(OUTPUT+"/battle-"+name+".wav",master)
	check(master.size()>AudioServer.get_mix_rate()*2.7,"Captured a complete real combat mix")
	check(results[name].master.peak<.93,"Final limiter leaves headroom in the overlapping battle")
	if not legacy:
		check(ratio>6.0,"Reload band RMS exceeds music by at least six decibels during combat")
		check(minimum_score< -9.0,"Nearby reloads briefly duck the music")

func run() -> void:
	if AudioServer.get_driver_name()!="Dummy": quit(1); return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene=game
	game.start(1)
	# This A/B fixture compares the same recording and gain settings. Native
	# synthesis has its own real-mixer integration test and must not replace it.
	game.audio.set_live_music_enabled(false)
	game.rounds.running=false
	game.rounds.phase="attack"
	await physics_frame
	freeze(game)
	audio=game.audio
	audio.settings_path="user://audio_mix_balance_test.cfg"
	audio.persistence_enabled=true
	audio.set_music_volume(.45)
	audio.set_sfx_volume(.65)
	game.players[0].position=Vector2(1011,430)
	game.turret.position=Vector2(1040,430)
	game.turret.aim_angle=0.0
	audio.movement.stop_effects()
	for voice in audio.voices: voice.stop()
	audio.acoustics.release()
	audio.acoustics=preload("res://scripts/environment_acoustics.gd").new()
	audio.acoustics.setup(audio)
	audio.acoustics._ensure_room()
	tap("MixMusic","Master",1)
	AudioServer.set_bus_send(AudioServer.get_bus_index("Music"),"MixMusic")
	tap("MixActions",audio.acoustics.room_bus)
	tap("MixBattle",audio.acoustics.room_bus)
	var master_capture := AudioEffectCapture.new()
	master_capture.buffer_length=6.0
	AudioServer.add_bus_effect(0,master_capture)
	await physics_frame
	await record(true)
	await record(false)
	check(results.rebalanced.action_music_db-results["previous-gain"].action_music_db>12.0,"Music/reload separation improves by more than twelve decibels using identical source recordings")
	check(audio.music_volume==.45 and audio.sfx_volume==.65,"Internal balance preserves the user's slider values")
	audio.save_settings()
	var settings := ConfigFile.new()
	settings.load(audio.settings_path)
	check(settings.get_value("audio","music")==.45,"Saving does not bake the internal music trim into preferences")
	for voice in audio.voices: voice.stop()
	for index in 12:
		audio.cooldowns.clear()
		audio.play_sound("explosion")
	audio.cooldowns.clear()
	check(audio.play_sound("reload_rifle_close"),"Reload feedback can enter a saturated combat pool")
	var reload_serial: int = audio._voice_serial
	for index in 24:
		audio.cooldowns.clear()
		audio.play_sound("explosion")
	check(audio.voices.any(func(voice):return voice.playing and int(voice.get_meta("serial",0))==reload_serial),"Repeated lower-priority explosions cannot immediately evict the reload cue")
	audio._process(.1)
	var duck_left: float = audio._handling_duck_left
	paused=true
	audio._process(.5)
	check(audio._handling_duck_left==duck_left,"Pause freezes the short weapon-duck timer")
	paused=false
	audio._process(1.0)
	check(audio._handling_duck_db==0.0 and audio._handling_duck_left==0.0,"Music returns to its normal mix after the short handling cue")
	audio.cooldowns.clear()
	audio.play_sound_at("reload_rifle_open",Vector2(5000,400))
	check(audio._handling_duck_left==0.0,"A distant other player's reload cannot duck local music")
	game.join_coop()
	game.network.active=true
	game.network.local_player_id=2
	audio.acoustics._probe_listener()
	check(audio.acoustics.listener_ids==[2],"Online audio selects the local guest rather than the host")
	game.network.active=false
	audio.set_sfx_volume(0)
	check(not audio.play_sound("reload_cannon_open") and audio.voices.all(func(voice):return not voice.playing),"Effects slider still fully mutes weapon actions")
	AudioServer.remove_bus_effect(0,AudioServer.get_bus_effect_count(0)-1)
	AudioServer.set_bus_send(AudioServer.get_bus_index("Music"),"Master")
	for title in ["MixActions","MixBattle","MixMusic"]:
		AudioServer.remove_bus(AudioServer.get_bus_index(title))
	check(await CLEANUP.free_scene(game,self),"Instrumented playback and scene resources release")
	var file := FileAccess.open(OUTPUT+"/mix-measurements.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed":checks-failures,"failed":failures,"mixes":results,"measurement":"Real AudioEffectCapture. Weapon/battle taps precede the common room return; their RMS includes the actual 0.65 effects gain. Music is measured after its bus gain. The previous-gain control uses the new recordings with previous gains and floor-origin cannon, isolating balance changes. No subjective hearing assessment."},"\t")+"\n")
	file.close()
	print("AUDIO MIX: %d/%d passed" % [checks-failures,checks])
	quit(1 if failures else 0)
