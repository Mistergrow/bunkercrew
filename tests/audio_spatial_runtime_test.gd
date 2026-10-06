extends SceneTree
## Real Stereo AudioServer samples: source coordinates, camera-independent ears,
## co-op source admission, pause/mute, bounded pools and lifetime cleanup.
const Audio := preload("res://scripts/audio.gd")
const Cleanup := preload("res://tests/scene_cleanup.gd")
const PropEffects := preload("res://scripts/scenery_prop_effects.gd")
const OUTPUT := "res://artifacts/audio-air-review/runtime"

class Actor extends Node2D:
	var player_id := 1
class Network extends Node:
	var active := false
	var local_player_id := 1
class Phase extends Node:
	var phase := "build"
class Props extends Node2D:
	var game: Node
class World extends Node2D:
	var started := true
	var players: Array[Node2D] = []
	var camera: Camera2D
	var network: Node
	var rounds: Node
	var audio: Node

var checks := 0
var failures := 0
var game: World
var audio: Node
var capture: AudioEffectCapture
var capture_slot := -1
var measurements: Dictionary = {}
var hearing := PackedVector2Array()
var segments: Array[Dictionary] = []

func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks += 1
	print("SPATIAL %s: %s" % ["PASS" if ok else "FAIL",label])
	if not ok:
		failures += 1
		push_error(label)

func stats(frames: PackedVector2Array) -> Dictionary:
	var energy := Vector2.ZERO
	var peak := 0.0
	for sample: Vector2 in frames:
		energy += Vector2(sample.x*sample.x,sample.y*sample.y)
		peak = maxf(peak,maxf(absf(sample.x),absf(sample.y)))
	energy /= maxf(1,frames.size())
	return {"frames":frames.size(),"left":energy.x,"right":energy.y,
		"rms":sqrt((energy.x+energy.y)*.5),"peak":peak}

func stop_world() -> void:
	for voice: AudioStreamPlayer in audio.voices: voice.stop()
	audio.movement.stop_effects()
	if is_instance_valid(audio.get("aircraft_audio")): audio.aircraft_audio.stop_effects()

func record(name: String,kind: String,offset: Vector2,step: bool=false) -> Dictionary:
	stop_world()
	await create_timer(.22).timeout
	audio.acoustics.refresh_listener_position()
	var source: Vector2 = audio.acoustics.listener_position+offset
	capture.clear_buffer()
	audio.cooldowns.clear()
	if step:
		audio._variant_bags["step_metal"]=[0]
		check(audio.play_footstep("metal",source),name+": real contact starts at requested world point")
	else:
		audio._variant_bags[kind]=[0]
		check(audio.play_sound_at(kind,source),name+": real sample starts at requested world point")
	await create_timer(.42).timeout
	var frames:=capture.get_buffer(capture.get_frames_available())
	var result:=stats(frames)
	measurements[name]=result
	segments.append({"name":name,"start_seconds":float(hearing.size())/AudioServer.get_mix_rate(),
		"source":[source.x,source.y],"listener":[audio.acoustics.listener_position.x,audio.acoustics.listener_position.y],
		"camera":[game.camera.position.x,game.camera.position.y],"zoom":game.camera.zoom.x,"measurement":result})
	hearing.append_array(frames)
	var gap:=PackedVector2Array()
	gap.resize(roundi(AudioServer.get_mix_rate()*.14))
	hearing.append_array(gap)
	check(result.frames>AudioServer.get_mix_rate()*.3 and result.rms>.000001,name+": captured audible real stereo mixer frames")
	return result

func save_audio() -> void:
	var bytes:=PackedByteArray()
	bytes.resize(hearing.size()*4)
	for index in hearing.size():
		bytes.encode_s16(index*4,roundi(clampf(hearing[index].x,-1,1)*32767))
		bytes.encode_s16(index*4+2,roundi(clampf(hearing[index].y,-1,1)*32767))
	var wav:=AudioStreamWAV.new()
	wav.mix_rate=roundi(AudioServer.get_mix_rate())
	wav.stereo=true
	wav.format=AudioStreamWAV.FORMAT_16_BITS
	wav.data=bytes
	check(wav.save_to_wav(ProjectSettings.globalize_path(OUTPUT+"/stereo-source-proof.wav"))==OK,"Actual stereo hearing artifact saved")

func run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args() or "--no-upnp" not in OS.get_cmdline_user_args():
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	root.size=Vector2i(1440,900)
	root.audio_listener_enable_2d=true
	game=World.new()
	root.add_child(game)
	current_scene=game
	game.network=Network.new()
	game.add_child(game.network)
	game.rounds=Phase.new()
	game.add_child(game.rounds)
	game.camera=Camera2D.new()
	game.camera.position=Vector2(1200,250) # Deliberately far from the local ears.
	game.add_child(game.camera)
	game.camera.make_current()
	for index in 2:
		var actor:=Actor.new()
		actor.player_id=index+1
		actor.position=Vector2(800+index*700,450)
		game.add_child(actor)
		game.players.append(actor)
	game.network.active=true
	audio=Audio.new()
	game.audio=audio
	game.add_child(audio)
	audio.set_process(false)
	audio.movement.set_process(false)
	if is_instance_valid(audio.get("aircraft_audio")): audio.aircraft_audio.set_process(false)
	check(audio.music_volume==.5 and audio.sfx_volume==.5 and audio.voice_volume==.5,"Saved profiles untouched; every default slider remains fifty percent")
	audio.set_music_volume(0)
	audio.set_voice_volume(0)
	var base_buses:=AudioServer.bus_count
	capture=AudioEffectCapture.new()
	capture.buffer_length=2.0
	var sfx:=AudioServer.get_bus_index("SFX")
	capture_slot=AudioServer.get_bus_effect_count(sfx)
	AudioServer.add_bus_effect(sfx,capture)
	await physics_frame
	await physics_frame
	game.camera.force_update_scroll()
	check(audio.acoustics.spatial_listener.is_current() and audio.acoustics.spatial_listener.global_position==Vector2(800,425),"Native 2D sounds share the exact local head listener used by world panners")
	var props:=Props.new()
	props.game=game
	props.position=Vector2(300,100)
	game.add_child(props)
	var effects:=PropEffects.new()
	effects.props=props
	var prop_hit:=Vector2(440,410)
	effects._hit_sound({"kind":"tree"},prop_hit)
	var wood_voice: AudioStreamPlayer=audio.voices.filter(func(voice): return voice.playing and voice.get_meta("kind","")=="impact_wood")[0]
	check(wood_voice.get_meta("acoustic_source")==prop_hit and audio.acoustics._lanes[audio.voices.find(wood_voice)].target_pan<0,"A real foliage contact keeps its world position and matching ear despite transformed props")
	effects._sound_delay=0
	effects._hit_sound({"kind":"traffic_light"},Vector2(1180,410))
	var metal_voice: AudioStreamPlayer=audio.voices.filter(func(voice): return voice.playing and voice.get_meta("kind","")=="impact_metal")[0]
	check(metal_voice.get_meta("acoustic_source")==Vector2(1180,410) and audio.acoustics._lanes[audio.voices.find(metal_voice)].target_pan>0,"Mechanical scenery contacts are spatial rather than centered or locally transformed twice")
	var prop_serial: int=audio._voice_serial
	effects._sound_delay=0
	effects._hit_sound({"kind":"tree"},Vector2(NAN,0))
	check(audio._voice_serial==prop_serial,"Malformed scenery contact coordinates cannot enter the real audio pool")
	effects.free()
	var left:=await record("shot-left","shot",Vector2(-360,0))
	var center:=await record("shot-center","shot",Vector2.ZERO)
	var right:=await record("shot-right","shot",Vector2(360,0))
	check(left.left>left.right*2 and right.right>right.left*2,"Real gun samples reach the matching ear; pan direction is not reversed")
	check(absf(center.left-center.right)<maxf(center.left,center.right)*.08,"A gun at the local head is centered despite camera look-ahead")
	var foot_center:=await record("step-center-offset-camera","",Vector2.ZERO,true)
	check(absf(foot_center.left-foot_center.right)<maxf(foot_center.left,foot_center.right)*.08,"Own footsteps remain centered when the camera looks away")
	for zoom in [.45,2.5]:
		game.camera.zoom=Vector2.ONE*zoom
		game.camera.position=Vector2(-400 if zoom>.5 else 2400,250)
		game.camera.force_update_scroll()
		await physics_frame
		var foot_left:=await record("step-left-zoom-%.2f"%zoom,"",Vector2(-360,0),true)
		var foot_right:=await record("step-right-zoom-%.2f"%zoom,"",Vector2(360,0),true)
		check(foot_left.left>foot_left.right*1.15 and foot_right.right>foot_right.left*1.15,"Foot contact ears remain correct in both overview and close zoom %.2f"%zoom)
	game.network.local_player_id=2
	audio.acoustics._probe_listener()
	check(audio.acoustics.listener_ids==[2] and audio.acoustics.spatial_listener.global_position==Vector2(1500,425),"A guest's native and filtered voices listen only at its own worker")
	var guest:=await record("guest-step-right","",Vector2(200,0),true)
	check(guest.right>guest.left*1.2,"The guest hears right-side contacts on the right despite remote host/camera positions")
	game.network.active=false
	audio.acoustics._probe_listener()
	check(audio.acoustics.listener_position==Vector2(1150,425) and audio.acoustics.spatial_listener.global_position==Vector2(1150,425),"Shared local co-op uses one mean head position for all source types")
	stop_world()
	audio.cooldowns.clear()
	check(audio.play_sound_at("enemy_shot",Vector2(800,425)) and audio.play_sound_at("enemy_shot",Vector2(1500,425)),"Two separate enemies firing in one frame both receive real voices")
	check(not audio.play_sound_at("enemy_shot",Vector2(1500,425)),"One duplicated source contact remains throttled")
	check(audio.voices.filter(func(voice):return voice.playing and voice.get_meta("kind","")=="enemy_shot").size()==2,"Independent accepted gun sources occupy exactly two fixed lanes")
	stop_world()
	audio.cooldowns.clear()
	for index in 12: audio.play_sound_at("enemy_shot",audio.acoustics.listener_position+Vector2(index*36-210,0))
	var serial_before: int=audio._voice_serial
	check(not audio.play_sound_at("enemy_shot",audio.acoustics.listener_position+Vector2(2200,0)) and audio._voice_serial==serial_before,"A distant enemy cannot steal one of twelve equally important nearby voices")
	check(audio.play_sound_at("reload_rifle_open",audio.acoustics.listener_position),"A higher-priority local weapon action still cuts through the full nearby crowd")
	stop_world()
	audio.cooldowns.clear()
	check(audio.play_sound("alarm") and not audio.play_sound_at("warning",Vector2(800,425)),"Global alert aliases keep their shared duplicate guard")
	stop_world()
	audio.cooldowns.clear()
	for index in 250:
		for voice in audio.voices: voice.stop()
		audio.play_sound_at("impact_stone",Vector2(index*40,400))
	check(audio.cooldowns.size()==audio.MAX_COOLDOWN_KEYS and audio.voices.size()==12 and audio.acoustics._lanes.size()<=12,"Many admitted moving sources exercise cooldown eviction and keep acoustic buses bounded")
	check(not audio.play_sound_at("shot",Vector2(NAN,0)),"Non-finite source coordinates are rejected")
	stop_world()
	paused=true
	audio.acoustics.update(.01)
	capture.clear_buffer()
	check(not audio.play_sound_at("shot",Vector2(800,425)) and not audio.play_footstep("metal",Vector2(800,425)),"Pause prevents new weapons and physical contacts")
	await create_timer(.1).timeout
	check(stats(capture.get_buffer(capture.get_frames_available())).rms<.000001,"Paused world buses produce no contact tail")
	paused=false
	audio.acoustics.update(.01)
	audio.set_sfx_volume(0)
	check(not audio.play_sound_at("explosion",Vector2(800,425)) and not audio.play_footstep("dry",Vector2(800,425)),"The effects mute blocks all world source admission")
	audio.set_sfx_volume(.5)
	save_audio()
	AudioServer.remove_bus_effect(sfx,capture_slot)
	capture=null
	check(await Cleanup.free_scene(game,self),"Scene teardown retires real spatial and music playback handles")
	check(AudioServer.bus_count==base_buses,"No per-source room/filter/panner bus survives teardown")
	var file:=FileAccess.open(OUTPUT+"/stereo-verification.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"mix_rate":AudioServer.get_mix_rate(),"driver":OS.get_cmdline_args(),"prepared_state":"Real cached SFX and steps; two prepared workers, peer-local ears, deliberately offset camera; no music or microphones","segments":segments,"measurements":measurements},"\t"))
	print("AUDIO SPATIAL RUNTIME: %d/%d checks passed"%[checks-failures,checks])
	quit(1 if failures else 0)
