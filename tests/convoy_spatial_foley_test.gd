extends SceneTree
## Actual imported foley through native stereo mixer, with mirrored real axle.
const Cleanup := preload("res://tests/scene_cleanup.gd")
const OUTPUT := "res://artifacts/convoy-experience-20261004/crew"
var checks := 0
var failures := 0
var evidence: Dictionary = {}
var game
var truck
var sound
var capture: AudioEffectCapture

func _initialize() -> void: _run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error(label)

func freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children(): freeze(child)

func wait_seconds(seconds: float) -> void:
	var deadline:=Time.get_ticks_usec()+roundi(seconds*1000000)
	while Time.get_ticks_usec()<deadline: await create_timer(.008,true,false,true).timeout

func stereo(data: PackedVector2Array) -> Dictionary:
	var left:=0.0
	var right:=0.0
	var finite:=true
	var peak:=0.0
	for value in data:
		left+=value.x*value.x
		right+=value.y*value.y
		peak=maxf(peak,maxf(absf(value.x),absf(value.y)))
		finite=finite and value.is_finite()
	return {"frames":data.size(),"left_rms":sqrt(left/maxi(1,data.size())),"right_rms":sqrt(right/maxi(1,data.size())),"peak":peak,"finite":finite}

func foley(kind: String, side: float) -> Dictionary:
	truck.facing=side
	sound.stop_effects()
	sound._effect_cooldown.clear()
	await wait_seconds(.1)
	capture.clear_buffer()
	check(sound.play_effect(kind),"Actual imported "+kind+" enters bounded spatial mixer")
	var voice: AudioStreamPlayer2D=sound.effect_voices.filter(func(source):return source.playing and source.get_meta("kind","")==kind)[0]
	var at:=voice.global_position
	if kind in ["jack","tire_puncture"]: check(at.is_equal_approx(truck.service_point()),"Actual rear-wheel emitter follows mirrored physical axle")
	else: check(signf(at.x-truck.global_position.x)==side,"Actual door emitter comes from cab side")
	await wait_seconds(.6)
	var metrics:=stereo(capture.get_buffer(capture.get_frames_available()))
	metrics.emitter=[at.x,at.y]
	check(metrics.frames>10000 and metrics.finite and metrics.peak>0 and metrics.peak<.5,"Actual spatial PCM has finite signal and headroom")
	return metrics

func _run() -> void:
	if AudioServer.get_driver_name()!="Dummy" or "--no-profile-save" not in OS.get_cmdline_user_args() or "--no-upnp" not in OS.get_cmdline_user_args(): quit(2); return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	root.size=Vector2i(1920,1080)
	game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene=game
	game.start_scenario(1,{"environment":"ash_foundry","position":"left","build_type":"bastion"})
	game.audio.persistence_enabled=false
	await process_frame
	freeze(game)
	game.audio.menu_music.stop()
	game.audio.live_music.end_session()
	for deck in game.audio.music_players: deck.stop()
	for voice in game.audio.voices: voice.stop()
	game.audio.movement.stop_effects()
	game.audio.upgrade_audio.stop_effects()
	game.dialogue.reset()
	if game.audio.acoustics!=null:
		game.audio.acoustics.release()
		game.audio.acoustics=null
	game.camera.position=Vector2(1910,430)
	game.camera.zoom=Vector2.ONE*4
	game.camera.reset_smoothing()
	game.camera.force_update_scroll()
	truck=load("res://scenes/convoy_vehicle.tscn").instantiate()
	truck.game=game
	game.add_child(truck)
	truck.configure_trip(Vector2(1910,430),Vector2(740,3700),{"hp":600,"fuel":12,"cargo":{}})
	freeze(truck)
	sound=truck.get_node("DieselEngine")
	var bus:=AudioServer.get_bus_index("SFX")
	var capture_index:=AudioServer.get_bus_effect_count(bus)
	capture=AudioEffectCapture.new()
	capture.buffer_length=2
	AudioServer.add_bus_effect(bus,capture)
	check(game.audio.music_volume==.5 and game.audio.sfx_volume==.5 and game.audio.voice_volume==.5,"Common fifty-percent settings and audible foley gains stay unchanged")
	var left:=await foley("jack",1)
	var right:=await foley("jack",-1)
	check(left.left_rms>left.right_rms*1.02 and right.right_rms>right.left_rms*1.02,"Actual stereo energy follows rear wheel from left to right when chassis is mirrored")
	var left_door:=await foley("door_open",-1)
	var right_door:=await foley("door_open",1)
	check(left_door.left_rms>left_door.right_rms*1.02 and right_door.right_rms>right_door.left_rms*1.02,"Actual door stereo energy comes from front cab on both orientations")
	var puncture:=await foley("tire_puncture",1)
	check(puncture.left_rms>puncture.right_rms*1.02,"Actual pressure rupture is localized beside flat rear wheel")
	var used: int=sound.effects_played
	AudioServer.set_bus_mute(bus,true)
	check(not sound.play_effect("fit") and sound.effects_played==used,"Muted SFX rejects new axle foley without replay")
	AudioServer.set_bus_mute(bus,false)
	paused=true
	check(not sound.play_effect("fit"),"Pause rejects tool sounds even with spatial emitter")
	paused=false
	AudioServer.remove_bus_effect(bus,capture_index)
	evidence={"jack_left":left,"jack_right":right,"door_left":left_door,"door_right":right_door,"puncture":puncture,"source_budget":sound.effect_voices.size()}
	check(await Cleanup.free_scene(game,self),"Spatial recordings and actual vehicle release without leaked nodes")
	FileAccess.open(OUTPUT+"/spatial-foley.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"passed":checks-failures,"failures":failures,"evidence":evidence,"fixture":"Actual main audio buses with original fifty-percent defaults. Prepared stationary real truck and camera zoom4; other sound sources stopped. Imported jack, door and puncture go through Godot Dummy stereo mixer and runtime bounded foley voices. Added capture exists only in this isolated test process; bus layout files and profiles untouched."},"\t"))
	print("CONVOY SPATIAL FOLEY: %d/%d passed"%[checks-failures,checks])
	quit(1 if failures else 0)
