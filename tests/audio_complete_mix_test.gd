extends SceneTree
## Captures the actual game buses at unchanged fifty-percent preferences.
## Scene simulation is held: real source controllers, cached playback and dialogue run.
const Cleanup:=preload("res://tests/scene_cleanup.gd")
const OUTPUT:="res://artifacts/audio-air-review/runtime"
var game: Node2D
var audio: Node
var checks:=0
var failures:=0
var taps: Dictionary={}
var tap_slots: Dictionary={}
var measurements: Dictionary={}

func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks+=1
	print("COMPLETE MIX %s: %s"%["PASS" if ok else "FAIL",label])
	if not ok:
		failures+=1
		push_error(label)
func freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children(): freeze(child)
func stats(frames: PackedVector2Array,gain: float=1.0) -> Dictionary:
	var power:=0.0
	var peak:=0.0
	var finite:=true
	for sample: Vector2 in frames:
		sample*=gain
		finite=finite and sample.is_finite()
		power+=sample.length_squared()
		peak=maxf(peak,maxf(absf(sample.x),absf(sample.y)))
	var rms:=sqrt(power/maxf(1,frames.size()*2))
	return {"frames":frames.size(),"rms":rms,"rms_db":linear_to_db(maxf(.00000001,rms)),"peak":peak,"finite":finite}
func save(frames: PackedVector2Array) -> void:
	var wav:=AudioStreamWAV.new()
	wav.format=AudioStreamWAV.FORMAT_16_BITS
	wav.stereo=true
	wav.mix_rate=roundi(AudioServer.get_mix_rate())
	var data:=PackedByteArray()
	data.resize(frames.size()*4)
	for index in frames.size():
		data.encode_s16(index*4,roundi(clampf(frames[index].x,-1,1)*32767))
		data.encode_s16(index*4+2,roundi(clampf(frames[index].y,-1,1)*32767))
	wav.data=data
	check(wav.save_to_wav(ProjectSettings.globalize_path(OUTPUT+"/default-50pct-full-mix.wav"))==OK,"Real Master stereo mix saved without offline normalization")
func emit(kind: String,offset: Vector2) -> void:
	check(audio.play_sound_at(kind,audio.acoustics.listener_position+offset),"Actual event admitted: "+kind)
func run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args() or "--no-upnp" not in OS.get_cmdline_user_args(): quit(1); return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	root.size=Vector2i(1440,900)
	root.audio_listener_enable_2d=true
	game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene=game
	game.start_scenario(2,{"environment":"ash_foundry","position":"left","build_type":"bastion"})
	game.rounds.running=false
	game.rounds.phase="attack"
	await physics_frame
	freeze(game)
	audio=game.audio
	game.dialogue.reset()
	game.air_raid_intro.skip()
	for player in game.find_children("*","AudioStreamPlayer",true,false): player.stop()
	for player in game.find_children("*","AudioStreamPlayer2D",true,false): player.stop()
	audio.set_live_music_enabled(false)
	audio.set_environment("ash_foundry")
	audio.set_music_volume(.5)
	audio.set_voice_volume(.5)
	audio.set_sfx_volume(.5)
	game.players[0].global_position=Vector2(1750,430)
	game.players[1].global_position=Vector2(1810,430)
	game.camera.global_position=Vector2(1500,300)
	game.camera.zoom=Vector2.ONE
	game.camera.force_update_scroll()
	audio.acoustics._probe_listener()
	var stations: Array[Node2D]=[]
	for station in get_nodes_in_group("stations"):
		if station.get("game")!=game or str(station.kind) not in ["mixer","furnace"]: continue
		station.global_position=Vector2(1720 if station.kind=="mixer" else 1840,430)
		station.input_amount=station.input_cost(station.input_kind())
		station.output_amount=0
		station._process(.01)
		stations.append(station)
	check(stations.size()==2 and stations.all(func(station):return station.working),"Actual paid-ready mixer and furnace batches enter work through their normal state logic")
	audio.machinery_audio._process(1.0)
	check(audio.machinery_audio.voices.filter(func(voice):return voice.playing).size()==2,"Working batches supply exactly two real spatial workshop loops")
	var plane:=preload("res://scripts/air_machine.gd").new()
	plane.kind="gunship"
	plane.game=game
	plane.set_physics_process(false)
	game.add_child(plane)
	plane.global_position=Vector2(2070,260)
	plane.flight_velocity=Vector2(-80,0)
	freeze(plane)
	audio.aircraft_audio._process(1.0)
	audio._process(4.0)
	audio.music_player.play(18.0) # Existing combat recording, a phrase with its full beat.
	var limiter: AudioEffectHardLimiter=AudioServer.get_bus_effect(AudioServer.get_bus_index("Master"),0)
	var output_pre_gain:=db_to_linear(limiter.pre_gain_db)
	check(AudioServer.get_bus_volume_db(0)==0.0 and absf(limiter.pre_gain_db-6.0199986)<.0001,"Shipped Master boost is preserved before the limiter and no gain follows its ceiling")
	for bus: String in ["Music","Voice","SFX","Master"]:
		var index:=AudioServer.get_bus_index(bus)
		var capture:=AudioEffectCapture.new()
		capture.buffer_length=12.0
		taps[bus]=capture
		tap_slots[bus]=AudioServer.get_bus_effect_count(index)
		AudioServer.add_bus_effect(index,capture)
	await create_timer(.25).timeout
	# Isolated source meter uses the same controllers/bus path as the combined take.
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Music"),true)
	for effect in taps.values(): effect.clear_buffer()
	await create_timer(.5).timeout
	measurements["workshop_and_air_bed"]=stats(taps.SFX.get_buffer(taps.SFX.get_frames_available()),.5*output_pre_gain)
	check(measurements.workshop_and_air_bed.rms>.00001,"Workshop/air bed is present in the actual effects mix")
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Music"),false)
	for effect in taps.values(): effect.clear_buffer()
	var events: Array[Dictionary]=[
		{"time":.35,"kind":"shot","offset":Vector2(-30,0)},
		{"time":.65,"kind":"impact_metal","offset":Vector2(210,0)},
		{"time":1.1,"kind":"reload_rifle_open","offset":Vector2(-20,0)},
		{"time":1.45,"kind":"reload_rifle_load","offset":Vector2(-20,0)},
		{"time":1.9,"kind":"reload_rifle_close","offset":Vector2(-20,0)},
		{"time":2.5,"kind":"air_tracer","offset":Vector2(290,-145)},
		{"time":2.85,"kind":"impact_core","offset":Vector2(160,0)},
		{"time":3.2,"kind":"shotgun","offset":Vector2(-30,0)},
		{"time":3.7,"kind":"impact_stone","offset":Vector2(240,0)},
		{"time":4.1,"kind":"air_lock","offset":Vector2(-390,-160)},
		{"time":4.55,"kind":"air_rocket","offset":Vector2(-390,-160)},
		{"time":5.0,"kind":"explosion","offset":Vector2(-180,0)},
		{"time":5.7,"kind":"medical_heal","offset":Vector2(20,0)},
		{"time":6.3,"kind":"medical_revive","offset":Vector2(20,0)},
		{"time":7.1,"kind":"cannon","offset":Vector2(-30,0)},
		{"time":7.5,"kind":"air_crash","offset":Vector2(390,-160)},
	]
	var start:=Time.get_ticks_usec()
	var last:=start
	var spoke:=false
	var next_step:=.2
	var minimum_score: float=audio._score_level
	while Time.get_ticks_usec()-start<8500000:
		var now:=Time.get_ticks_usec()
		var elapsed:=float(now-start)/1000000.0
		var delta:=float(now-last)/1000000.0
		while not events.is_empty() and events[0].time<=elapsed:
			var event: Dictionary=events.pop_front()
			emit(event.kind,event.offset)
		if elapsed>=next_step:
			audio.play_footstep("metal",audio.acoustics.listener_position+Vector2(-30,25),1,false,true,"","mara")
			next_step+=.55
		if elapsed>=2.0 and not spoke:
			check(game.dialogue.enqueue("warning_air","san"),"An unchanged real recorded SAN line enters the normal dialogue player")
			spoke=true
		game.dialogue.advance(delta)
		audio._process(delta)
		audio.aircraft_audio._process(delta)
		audio.machinery_audio._process(delta)
		minimum_score=minf(minimum_score,audio._score_level)
		last=now
		await create_timer(.01).timeout
	var master:=PackedVector2Array()
	for bus: String in taps:
		var frames: PackedVector2Array=taps[bus].get_buffer(taps[bus].get_frames_available())
		var gain:=db_to_linear(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(bus)))
		if bus!="Master": gain*=output_pre_gain
		measurements[bus]=stats(frames,gain)
		if bus=="Master": master=frames
		check(measurements[bus].finite and measurements[bus].rms>.00001,bus+": actual mixed output is finite and audible")
	check(master.size()>AudioServer.get_mix_rate()*8.0 and measurements.Master.peak<=db_to_linear(-1)+.002,"Complete default mix reaches Master with the existing minus-one-decibel ceiling")
	check(measurements.Master.rms<=float(measurements.Music.rms+measurements.Voice.rms+measurements.SFX.rms)*1.03,"Actual Master energy is accounted for by its three source buses, including the fixed shared pre-gain")
	check(measurements.workshop_and_air_bed.rms<measurements.Music.rms*.5,"Quiet engine/workshop bed remains beneath the music instead of masking actions")
	check(minimum_score< -10 and measurements.Voice.rms>measurements.Music.rms*.75,"Normal dialogue/reload ducking protects unchanged recorded speech")
	check(audio.music_volume==.5 and audio.sfx_volume==.5 and audio.voice_volume==.5,"Every preference remains exactly fifty percent after the full source mix")
	save(master)
	for station in stations: station.working=false
	audio.machinery_audio._process(.01)
	check(audio.machinery_audio.voices.all(func(voice):return not voice.playing),"Finished batches stop their work loop on the next local presentation update")
	var removed_station: Node2D=stations[0]
	removed_station.input_amount=removed_station.input_cost(removed_station.input_kind())
	removed_station._process(.01)
	audio.machinery_audio._process(.2)
	check(removed_station in audio.machinery_audio._sources,"A normal second paid-ready batch occupies a reused workshop lane")
	removed_station.queue_free()
	await process_frame
	await physics_frame
	audio.machinery_audio._process(.2)
	check(not is_instance_valid(removed_station) and audio.machinery_audio.voices.all(func(voice):return not voice.playing),"A truly freed working station clears before typed candidate lookup and never leaves its motor running")
	for bus: String in taps: AudioServer.remove_bus_effect(AudioServer.get_bus_index(bus),int(tap_slots[bus]))
	taps.clear()
	check(await Cleanup.free_scene(game,self),"Full real source scene retires without a playback leak")
	var file:=FileAccess.open(OUTPUT+"/complete-mix-verification.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"measurements":measurements,"minimum_score_db":minimum_score,"default_sliders":[.5,.5,.5],"music_mix_trim_db":-7.172146296835499,"voice_mix_trim_db":-.9151498112135024,"master_pre_gain_db":linear_to_db(output_pre_gain),"master_fader_db":0.0,"stem_meter":"Source-bus capture times its fixed bus gain and shared output pre-gain; nominal contribution before shared limiting. Master capture is final output with zero post-limiter fader gain.","prepared_state":"Actual Aschewerk, two workers, normal paid-ready workshop state transition; held batch/flight simulation for exact placements, four source controllers and real recorded SAN dialog; combat music at18s; no microphones/online/public services"},"\t"))
	print("COMPLETE AUDIO MIX: %d/%d checks passed"%[checks-failures,checks])
	quit(1 if failures else 0)
