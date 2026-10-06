extends SceneTree
## Scenario replacement keeps Audio but frees its former player nodes.
const Cleanup := preload("res://tests/scene_cleanup.gd")
var checks := 0
var failures := 0

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

func run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args():
		quit(1)
		return
	var game: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene=game
	var audio: Node=game.audio
	audio.set_sfx_volume(.65)
	audio.set_music_volume(0)
	audio.set_voice_volume(0)
	audio.set_process(false)
	var count_before:=AudioServer.bus_count
	check(audio.acoustics._listeners.is_empty() and game.players.is_empty(), "Main menu correctly starts without legacy players or audio listeners")
	game.start_scenario(1,{"environment":"ash_foundry","position":"left","build_type":"bastion"})
	check(audio.play_sound_at("impact_core",Vector2(980,400)), "The first real world sound is allowed before the timed acoustic tick")
	check(audio.acoustics._listeners.size()==1 and audio.acoustics._listeners[0]==game.players[0], "First world sound immediately fills the initially empty listener cache")
	audio.acoustics._probe_listener()
	var original: Array=audio.acoustics._listeners.duplicate()
	check(not original.is_empty(),"Audio initially caches the actual original worker")
	game.started=false # Expedition world replacement re-arms the scenario constructor.
	game.start_scenario(2,{"environment":"mountain_pass","position":"left","build_type":"bastion"})
	freeze(game)
	await process_frame
	await physics_frame
	check(original.all(func(actor):return not is_instance_valid(actor)),"Starting a scenario actually releases the original player nodes")
	check(audio.acoustics._listeners.any(func(actor):return not is_instance_valid(actor)),"Fixture holds stale listeners before the next timed acoustic probe")
	check(audio.play_sound_at("explosion",Vector2(980,400)),"A world sound safely refreshes stale listeners immediately after replacement")
	check(audio.acoustics._listeners.size()==2 and audio.acoustics._listeners.all(func(actor):return is_instance_valid(actor) and actor in game.players),"Only the new two-worker scene supplies the refreshed listeners")
	check(audio.voices.any(func(voice):return voice.get_meta("kind","")=="explosion" and voice.get_meta("acoustic_source",Vector2.ZERO)==Vector2(980,400)),"Refresh preserves the actual source position")
	check(await Cleanup.free_scene(game,self),"Replacement scenario and native playback release cleanly")
	check(AudioServer.bus_count==count_before,"Immediate replacement sound leaves no private buses after teardown")
	print("AUDIO LISTENER REBUILD: %d/%d checks passed" % [checks-failures,checks])
	quit(1 if failures else 0)
