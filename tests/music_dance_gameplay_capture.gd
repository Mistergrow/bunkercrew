extends SceneTree
## Real foundry gameplay and native mixed audio, recorded with --write-movie.
## The four actors retain physics and the actual idle/expression controller.
const CLEANUP := preload("res://tests/scene_cleanup.gd")
const DANCE := preload("res://scripts/worker_dance_catalog.gd")
const RHYTHM := preload("res://scripts/worker_rhythm_pose.gd")
const OPTIONS := {"environment":"ash_foundry","build_type":"workshop","position":"left"}
const DIRECTORY := "res://artifacts/music-dance-gameplay/render"
const STYLES := {"levin":"levin_air_freeze","mara":"mara_lockstep","ivo":"ivo_backslide","selma":"selma_running_switch"}
var game: Node
var failures := 0
var checks := 0
var rendered_frames := 0
var starting_milliseconds := 0
var capture_count := 0

func _initialize() -> void:
	starting_milliseconds = Time.get_ticks_msec()
	run.call_deferred()

func check(value: bool,label: String) -> void:
	checks += 1
	if value: print("LIVE_GAME_DANCE_CHECK ",label)
	else:
		failures += 1
		push_error(label)

func frame() -> void:
	await process_frame
	rendered_frames += 1
	if is_instance_valid(current_scene): game = current_scene

func wait_for(predicate: Callable,label: String,seconds: float=35.0) -> bool:
	var maximum_frames := int(seconds*60.0)
	for index in maximum_frames:
		if predicate.call(): return true
		if Time.get_ticks_msec()-starting_milliseconds>110000: break
		await frame()
	check(false,"Timed out: "+label)
	return false

func rig(index: int) -> Node:
	return game.players[index].get_node("PixelVisual")

func crew_dancing() -> bool:
	return game.players.all(func(worker):
		var visual: Node = worker.get_node("PixelVisual")
		return visual._safe_idle and visual.rhythm._dance_blend>.95 and visual.pose_skeleton.has("dance_style"))

func capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(DIRECTORY+"/"+name+".png")==OK,"Actual game viewport captures "+name)
	capture_count += 1

func run() -> void:
	if DisplayServer.get_name()=="headless" or "--no-profile-save" not in OS.get_cmdline_user_args() or "--no-upnp" not in OS.get_cmdline_user_args():
		push_error("Use a rendered run with --no-profile-save --no-upnp")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRECTORY))
	root.size = Vector2i(1440,900)
	LocaleText.set_locale("de",false)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.combat_events.persistence_enabled = false
	game.selected_characters.assign(["levin","mara","ivo","selma"])
	game.audio.set_music_style("minimal_techno")
	game.audio.set_music_volume(1.0)
	game.audio.set_music_calibration(0.0)
	game.audio.set_rhythm_motion_reduced(false)
	var profiles := DANCE.defaults()
	for character: String in STYLES: profiles[character].style = STYLES[character]
	game.audio.set_dance_configuration(1.0,profiles)
	game.start_scenario(4,OPTIONS)
	game.rounds.set_process(false)
	game.rounds.running = true
	game.rounds.phase = "attack"
	game.rounds.wave = 10
	game.set_camera_zoom(2.5)
	var colliders: Array[Vector2] = []
	var positions: Array[float] = []
	for index in 4:
		var worker: Node = game.players[index]
		worker.global_position = Vector2(820+index*132,430)
		worker.velocity = Vector2.ZERO
		worker.inventory.clear()
		worker.progression.award_damage(13500.0)
		colliders.append(worker.get_node("CollisionShape2D").shape.size)
		positions.append(worker.global_position.x)
	check(game.started and game.audio.live_music.native_active,"Normal scenario start activates native music for all four actual game workers")
	check(game.players.all(func(worker): return worker.is_physics_processing()),"Actual player physics remains enabled in the recorded scene")
	for index in 90: await frame()
	await capture("01-cinematic-opening")
	check(game.audio.live_music.pending_intensity==3 and game.audio.live_music.pending_bar==8,"Live round state preserves the cinematic opening until the complete phrase boundary")
	if not await wait_for(crew_dancing,"Actual audible kicks begin four distinct learned dances"):
		await finish(); return
	check(int(game.audio.live_music.rhythm_frame().get("kick_count",0))>=5,"All dances respond to actual native bass-drum events")
	check(game.players.all(func(worker): return str(worker.get_node("PixelVisual").pose_skeleton.get("dance_style",""))==str(STYLES[worker.character_id])),"Each real level10 character performs its selected learned side-view choreography")
	await capture("02-four-character-groove")
	var foot_positions := {}
	var floorwork_seen := false
	var maximum_beat_foot_error := 0.0
	var synchronized_actor_frames := 0
	for index in 600:
		await frame()
		if crew_dancing():
			foot_positions[str(rig(0).pose_skeleton.feet)] = true
			var actual: Dictionary = game.audio.live_music.rhythm_frame()
			var beats := float(actual.get("bar",0))*4.0+float(actual.get("beat",0))+float(actual.get("phase",0.0))
			for worker: Node in game.players:
				var visual: Node = worker.get_node("PixelVisual")
				if visual.rhythm._dance_blend<1.0 or visual.rhythm.weight<1.0 or not visual.rhythm._transition_pose.is_empty(): continue
				var expected := RHYTHM.choreography(str(visual.rhythm._movement),beats,worker.character_id,1.0)
				for foot in 2:
					maximum_beat_foot_error = maxf(maximum_beat_foot_error,Vector2(visual.pose_skeleton.feet[foot]).distance_to(expected.feet[foot]))
				synchronized_actor_frames += 1
			if str(rig(0).pose_skeleton.get("dance_stage",""))=="freeze" and not floorwork_seen:
				floorwork_seen = true
				await capture("03-personal-breakdance-freeze")
		if index>=480 and floorwork_seen: break
	check(floorwork_seen and foot_positions.size()>80,"Recorded real beat reaches visible breakdance, varied planted footwork and the personal freeze")
	check(synchronized_actor_frames>=1200 and maximum_beat_foot_error<.0001,"Actual game foot contacts use the identical sample-derived audible drum timeline")
	for index in 4:
		check(absf(game.players[index].global_position.x-positions[index])<.01 and game.players[index].get_node("CollisionShape2D").shape.size==colliders[index],"Dance retains real world position and collision for "+str(game.players[index].character_id))
	Input.action_press("p1_right")
	for index in 24: await frame()
	check(game.players[0].global_position.x-positions[0]>35.0 and rig(0).rhythm.weight==0.0 and not rig(0).pose_skeleton.has("dance_style"),"Actual movement input interrupts the full-body dance and enters normal walking immediately")
	await capture("04-input-interrupts-dance")
	Input.action_release("p1_right")
	if not await wait_for(crew_dancing,"Actual beat resumes dance after released movement",8):
		await finish(); return
	game.hud._toggle_match_pause()
	for index in 12: await frame()
	var paused_samples := int(game.audio.live_music.native_stream.call("mixed_samples"))
	for index in 18: await frame()
	check(paused and game.hud.overlay=="pause" and not game.audio.live_music.rhythm_frame().active and int(game.audio.live_music.native_stream.call("mixed_samples"))==paused_samples,"Normal pause-menu action freezes native music and dance together")
	game.hud._toggle_match_pause()
	for index in 18: await frame()
	game.audio.set_music_volume(0.0)
	for index in 6: await frame()
	check(not game.audio.live_music.rhythm_frame().active and game.players.all(func(worker): return worker.get_node("PixelVisual").rhythm.weight==0.0),"Actual music-volume control stops all audible dance reactions")
	game.audio.set_music_volume(1.0)
	for index in 18: await frame()
	var old_scene_id: int = game.get_instance_id()
	check(game.restart(),"Actual in-game restart starts a complete clean scene reload")
	if not await wait_for(func(): return is_instance_valid(current_scene) and current_scene.get_instance_id()!=old_scene_id and current_scene.started,"Reloaded actual four-player foundry",10):
		await finish(); return
	check(game.players.size()==4 and game.audio.live_music.native_active and game.audio.music_style=="minimal_techno" and game.audio.dance_profiles.levin.style=="levin_air_freeze" and game.combat_events.dance_level("levin")>=10,"Normal game restart retains four identities, live audio, dance settings and earned moves")
	await capture("05-clean-restarted-game")
	var result := {"checks":checks,"failures":failures,"renderer":RenderingServer.get_video_adapter_name(),"viewport":[1440,900],"actual_native_audio":true,"actual_game_start":true,"developer_lab_used":false,"dance_preview_used":false,"player_physics_enabled":true,"characters":STYLES,"prepared_state":"Actual level10 crew; automatic wave spawning held, combat wave10 audio arrangement, ordinary world/actor physics and idle controllers active","frames":rendered_frames,"captures":capture_count,"floorwork_seen":floorwork_seen,"distinct_foot_poses":foot_positions.size(),"maximum_beat_foot_error":maximum_beat_foot_error,"synchronized_actor_frames":synchronized_actor_frames}
	var file := FileAccess.open(DIRECTORY+"/verification.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"\t"))
	file.close()
	print("LIVE GAME DANCE CAPTURE: ",JSON.stringify(result))
	await finish()

func finish() -> void:
	Input.action_release("p1_right")
	paused = false
	if is_instance_valid(game): check(await CLEANUP.free_scene(game,self),"Actual recorded game and its native playback release cleanly")
	quit(0 if failures==0 else 1)
