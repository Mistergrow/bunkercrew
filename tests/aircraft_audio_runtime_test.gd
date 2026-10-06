extends SceneTree
## Actual AirMachine instances, cached propulsion loops and captured stereo audio.
const Aircraft := preload("res://scripts/air_machine.gd")
const Catalog := preload("res://scripts/aircraft_audio_catalog.gd")
const Cleanup := preload("res://tests/scene_cleanup.gd")
const OUTPUT := "res://artifacts/audio-air-review/runtime"
var checks:=0
var failures:=0
var game: Node2D
var audio: Node
var motors: Node2D
var capture: AudioEffectCapture
var capture_slot:=-1
var samples:=PackedVector2Array()
var measurements: Dictionary={}
var actors: Array[Node2D]=[]

func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks+=1
	print("AIR AUDIO %s: %s"%["PASS" if ok else "FAIL",label])
	if not ok:
		failures+=1
		push_error(label)
func freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children(): freeze(child)
func stats(frames: PackedVector2Array) -> Dictionary:
	var energy:=Vector2.ZERO
	var peak:=0.0
	for frame: Vector2 in frames:
		energy+=Vector2(frame.x*frame.x,frame.y*frame.y)
		peak=maxf(peak,maxf(absf(frame.x),absf(frame.y)))
	energy/=maxf(1,frames.size())
	return {"frames":frames.size(),"left":energy.x,"right":energy.y,"rms":sqrt((energy.x+energy.y)*.5),"peak":peak}
func add_aircraft(kind: String,point: Vector2) -> Node2D:
	var actor:=Aircraft.new()
	actor.kind=kind
	actor.game=game
	actor.position=point
	actor.set_physics_process(false)
	game.add_child(actor)
	actor.global_position=point # _ready chooses a sky lane; prepare the exact proof source afterward.
	freeze(actor)
	actors.append(actor)
	return actor
func clear_aircraft() -> void:
	motors.stop_effects()
	for actor in actors:
		if is_instance_valid(actor): actor.free()
	actors.clear()
func captured(seconds: float=.45) -> PackedVector2Array:
	# Godot updates native 2D panning on physics ticks and the mixer consumes
	# queued stop/play commands afterward; exclude that transition from ear proof.
	await create_timer(.16).timeout
	capture.clear_buffer()
	await create_timer(seconds).timeout
	return capture.get_buffer(capture.get_frames_available())
func save(path: String,frames: PackedVector2Array) -> void:
	var wav:=AudioStreamWAV.new()
	wav.mix_rate=roundi(AudioServer.get_mix_rate())
	wav.format=AudioStreamWAV.FORMAT_16_BITS
	wav.stereo=true
	var data:=PackedByteArray()
	data.resize(frames.size()*4)
	for index in frames.size():
		data.encode_s16(index*4,roundi(clampf(frames[index].x,-1,1)*32767))
		data.encode_s16(index*4+2,roundi(clampf(frames[index].y,-1,1)*32767))
	wav.data=data
	check(wav.save_to_wav(ProjectSettings.globalize_path(path))==OK,"Captured motor listening file saved")

func run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args() or "--no-upnp" not in OS.get_cmdline_user_args(): quit(1); return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	root.size=Vector2i(1440,900)
	root.audio_listener_enable_2d=true
	game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene=game
	game.start_scenario(1,{"environment":"ash_foundry","position":"left","build_type":"bastion"})
	game.rounds.running=false
	await physics_frame
	freeze(game)
	if is_instance_valid(game.dialogue): game.dialogue.reset()
	audio=game.audio
	audio.set_live_music_enabled(false)
	audio.set_music_volume(0)
	audio.set_voice_volume(0)
	audio.set_sfx_volume(.5)
	audio.movement.stop_effects()
	for voice in audio.voices: voice.stop()
	game.players[0].global_position=Vector2(1800,430)
	game.camera.global_position=Vector2(800,150)
	game.camera.zoom=Vector2.ONE
	game.camera.force_update_scroll()
	audio.acoustics._probe_listener()
	motors=audio.aircraft_audio
	var base_buses:=AudioServer.bus_count
	check(motors.voices.size()==4 and motors.streams.size()==6,"Six engine families are cached once behind exactly four spatial motor voices")
	for family: String in Catalog.PROPULSION:
		var stream: AudioStreamWAV=motors.streams.get(family)
		check(stream!=null and not stream.stereo and stream.mix_rate==48000 and stream.loop_mode==AudioStreamWAV.LOOP_FORWARD and absf(stream.get_length()-8.0)<.0001,"%s real mono eight-second source loops without baked pan"%family)
	var sfx:=AudioServer.get_bus_index("SFX")
	capture=AudioEffectCapture.new()
	capture.buffer_length=3.0
	capture_slot=AudioServer.get_bus_effect_count(sfx)
	AudioServer.add_bus_effect(sfx,capture)
	var families:={"rotor":"gunship","propeller":"patrol_plane","tiltrotor":"tiltrotor","jet":"interceptor","airship":"shield_airship","vtol":"sky_fortress"}
	for family: String in families:
		clear_aircraft()
		var actor:=add_aircraft(families[family],audio.acoustics.listener_position+Vector2(-360,-140))
		motors._process(1.0)
		await physics_frame
		var left:=await captured()
		var left_stats:=stats(left)
		check(left_stats.rms>.000003 and left_stats.left>left_stats.right*1.3,family+": actual aircraft motor reaches the left ear from left world source")
		actor.global_position.x+=720
		actor.flight_velocity=Vector2(160,0)
		motors._process(1.0)
		await physics_frame
		var right:=await captured()
		var right_stats:=stats(right)
		check(right_stats.rms>.000003 and right_stats.right>right_stats.left*1.3,family+": same motor follows the aircraft to the right ear")
		measurements[family]={"left":left_stats,"right":right_stats,"source_profile":Catalog.profile_for(families[family])}
		samples.append_array(left)
		samples.append_array(right)
	clear_aircraft()
	for index in AirEnemyCatalog.CLASS_ORDER.size():
		add_aircraft(AirEnemyCatalog.CLASS_ORDER[index],audio.acoustics.listener_position+Vector2(-250+index*55,-140))
	motors._process(1.0)
	check(motors.diagnostics().sources.size()==4 and motors.voices.filter(func(voice):return voice.playing).size()==4,"Twelve actual aircraft retain four nearest motors and never grow decoder count")
	var first: Node2D=motors._lanes[0].source
	first.dead=true
	motors._process(.01)
	check(not motors.voices[0].playing and motors._lanes[0].source==null,"Destroyed aircraft stop before their node is freed, without replaying a loop")
	motors._process(.2)
	check(motors.diagnostics().sources.size()==4,"A free motor lane admits the next live aircraft after the bounded probe")
	var removed: Node2D=motors._lanes[0].source
	actors.erase(removed)
	removed.queue_free()
	await process_frame
	await physics_frame
	motors._process(.2)
	check(not is_instance_valid(removed) and motors.diagnostics().sources.size()==4,"A truly freed assigned aircraft is removed safely before typed candidate lookup and its lane is reused")
	for actor in actors: actor.global_position.x+=10000
	motors._process(.2)
	check(motors.voices.all(func(voice):return not voice.playing),"Aircraft beyond each family hearing range do not retain a decoder")
	actors[0].global_position=audio.acoustics.listener_position+Vector2(100,-100)
	actors[0].dead=false
	motors._process(.2)
	await physics_frame
	paused=true
	audio.acoustics.update(.01)
	var paused_audio:=await captured(.1)
	check(stats(paused_audio).rms<.000001,"Paused aircraft and room return produce silence in the real mixer")
	paused=false
	audio.acoustics.update(.01)
	audio.set_sfx_volume(0)
	check(motors.voices.all(func(voice):return not voice.playing),"Effects mute immediately stops all aircraft loops")
	audio.set_sfx_volume(.5)
	motors._process(1.0)
	await physics_frame
	var resumed:=await captured(.2)
	check(stats(resumed).rms>.000003,"Unmuting restores the current live aircraft with a smooth motor gain")
	save(OUTPUT+"/aircraft-engine-stereo.wav",samples)
	clear_aircraft()
	AudioServer.remove_bus_effect(sfx,capture_slot)
	capture=null
	check(await Cleanup.free_scene(game,self),"Actual air scene and loop playbacks release cleanly")
	check(AudioServer.bus_count==base_buses,"Aircraft room routing leaves no private audio buses after cleanup")
	var file:=FileAccess.open(OUTPUT+"/aircraft-verification.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"mix_rate":AudioServer.get_mix_rate(),"prepared_state":"Actual game/12 AirMachine profiles; flight simulation held for exact listener/source placement; source pool and real Dummy mixer running; no microphones or public connections","measurements":measurements},"\t"))
	print("AIRCRAFT AUDIO RUNTIME: %d/%d checks passed"%[checks-failures,checks])
	quit(1 if failures else 0)
