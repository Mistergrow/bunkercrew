extends SceneTree
## Ordinary Gewitterpass match, native audio and four fully occupied cargo grips.
const Cleanup := preload("res://tests/scene_cleanup.gd")
const Rhythm := preload("res://scripts/worker_rhythm_pose.gd")
const Defaults := preload("res://scripts/audio_defaults.gd")
const DIRECTORY := "res://artifacts/carry-head-nod"
const OPTIONS := {"environment":"mountain_pass","build_type":"workshop","position":"left"}
const CHARACTERS := ["mara","branko","ivo","selma"]
const MATERIALS := ["ore","concrete","steel","ammo"]
var game: Node
var checks := 0
var failures := 0
var frames := 0
var capture_count := 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool,label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)

func frame() -> void:
	await process_frame
	frames += 1

func capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(DIRECTORY+"/"+name+".png")==OK,"Real gameplay viewport saves "+name)
	capture_count += 1

func ready_to_nod() -> bool:
	return game.players.all(func(worker):
		var rig: WorkerVisual = worker.get_node("PixelVisual")
		return rig._safe_carry_idle and rig.rhythm.weight>1.49 and rig.pose_skeleton.has("head_pivot"))

func _run() -> void:
	if DisplayServer.get_name()=="headless" or "--no-profile-save" not in OS.get_cmdline_user_args() or "--no-upnp" not in OS.get_cmdline_user_args():
		push_error("Carry head-nod capture requires graphics, --no-profile-save and --no-upnp")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRECTORY))
	root.size = Vector2i(1440,900)
	LocaleText.set_locale("de",false)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.combat_events.persistence_enabled = false
	game.selected_characters.assign(CHARACTERS)
	game.audio.set_music_style("minimal_techno")
	game.audio.set_music_volume(0.5)
	game.audio.set_music_calibration(0.0)
	game.audio.set_rhythm_motion_reduced(false)
	game.audio.set_dance_configuration(Defaults.DANCE_INTENSITY,Defaults.dance_profiles())
	game.start_scenario(4,OPTIONS)
	# Keep ordinary actors/world/physics/audio active; only automatic enemies
	# are held so waiting crew can safely show a quiet, head-only carry reaction.
	game.rounds.set_process(false)
	game.rounds.running = true
	game.rounds.phase = "attack"
	game.rounds.wave = 10
	game.set_camera_zoom(2.5)
	var colliders: Array[Vector2] = []
	var initial_positions: Array[Vector2] = []
	var capacities: Array[int] = []
	for index in 4:
		var worker: Node = game.players[index]
		worker.global_position = Vector2(660+index*78,430)
		worker.velocity = Vector2.ZERO
		worker.facing = 1.0 if index%2==0 else -1.0
		worker.inventory.clear()
		var full := int(worker.capacity())
		check(worker.add_item(str(MATERIALS[index]),full)==full,"Normal inventory API fills "+str(worker.character_id)+" to its actual capacity")
		capacities.append(full)
		colliders.append(worker.get_node("CollisionShape2D").shape.size)
		initial_positions.append(worker.global_position)
	check(game.started and game.audio.live_music.native_active and game.audio.live_music.environment_id=="mountain_pass","Normal Gewitterpass start uses the original native Höhenlicht score")
	check(game.players.all(func(worker): return worker.is_physics_processing()),"All recorded game workers retain ordinary authoritative physics")
	var heard := false
	for index in 3000:
		await frame()
		if int(game.audio.live_music.intensity)>=2 and int(game.audio.live_music.rhythm_frame().get("kick_count",0))>=5 and ready_to_nod():
			heard = true
			break
	check(heard,"Actual original cinematic score reaches the audible attack kicks and safe loaded idle poses")
	if not heard:
		check(await Cleanup.free_scene(game,self),"Timed-out capture releases normally")
		quit(1)
		return
	var recording_start_frame := frames
	var minimum_angles: Array[float] = [INF,INF,INF,INF]
	var maximum_angles: Array[float] = [-INF,-INF,-INF,-INF]
	var maximum_grip_error := 0.0
	var maximum_collider_error := 0.0
	var full_carry_frames := 0
	var head_only_frames := 0
	var kick_counts := {}
	var captured_close_dip := false
	var captured_close_rest := false
	var captured_standard := false
	var close_zoom := Vector2.ZERO
	var standard_zoom := Vector2.ZERO
	for index in 960:
		await frame()
		if index==480: game.set_camera_zoom(1.25)
		var state: Dictionary = game.audio.live_music.rhythm_frame()
		kick_counts[int(state.get("kick_count",0))] = true
		var first: WorkerVisual = game.players[0].get_node("PixelVisual")
		var age := float(state.get("audible_seconds",0.0))-float(state.get("last_kick_seconds",-1.0))
		var envelope := Rhythm.head_nod_envelope(age,float(first.rhythm._beat_period))
		for actor_index in 4:
			var worker: Node = game.players[actor_index]
			var rig: WorkerVisual = worker.get_node("PixelVisual")
			var pose: Dictionary = rig.pose_skeleton
			if worker.carried_count()==worker.capacity(): full_carry_frames += 1
			if rig._safe_carry_idle and not pose.has("dance_style") and pose.has("cargo"):
				head_only_frames += 1
			if not pose.has("cargo"):
				maximum_grip_error = INF
				continue
			var cargo: Vector2 = pose.cargo
			maximum_grip_error = maxf(maximum_grip_error,Vector2(pose.hands[0]).distance_to(cargo+Vector2(-7,0)))
			maximum_grip_error = maxf(maximum_grip_error,Vector2(pose.hands[1]).distance_to(cargo+Vector2(5,3)))
			maximum_collider_error = maxf(maximum_collider_error,Vector2(worker.get_node("CollisionShape2D").shape.size).distance_to(colliders[actor_index]))
			minimum_angles[actor_index] = minf(minimum_angles[actor_index],float(pose.head_tilt))
			maximum_angles[actor_index] = maxf(maximum_angles[actor_index],float(pose.head_tilt))
		if index<480 and envelope>.98 and not captured_close_dip:
			await capture("01-full-load-heard-kick")
			captured_close_dip = true
			close_zoom = game.camera.zoom
		elif index<480 and captured_close_dip and age/float(first.rhythm._beat_period)>.85 and not captured_close_rest:
			await capture("02-full-load-rest")
			captured_close_rest = true
		elif index>570 and envelope>.98 and not captured_standard:
			await capture("03-standard-game-view")
			captured_standard = true
			standard_zoom = game.camera.zoom
	check(captured_close_dip and captured_close_rest and captured_standard,"Actual game rendering captures heard dip, resting return and standard gameplay view")
	check(full_carry_frames==960*4 and head_only_frames==960*4,"All four fully loaded game actors nod without dancing their cargo grips")
	check(maximum_grip_error<.00001 and maximum_collider_error==0.0,"Recorded loaded head motion preserves exact hand/cargo contacts and collision shapes")
	check(kick_counts.size()>25,"The recorded ordinary gameplay follows actual repeated native bass-drum events")
	for index in 4:
		check(maximum_angles[index]-minimum_angles[index]>.12,str(CHARACTERS[index])+" has visible heard head travel with full "+str(MATERIALS[index])+" load")
		check(absf(game.players[index].global_position.x-initial_positions[index].x)<.01,"Head nod never moves the real loaded "+str(CHARACTERS[index]))
	check(not game.audio.calibration_active and not game.has_meta("dance_preview"),"Capture runs ordinary gameplay with no lab, cosmetic preview or injected rhythm frames")
	var result := {"checks":checks,"failures":failures,"actual_native_audio":true,"actual_main_scene":true,"environment":"mountain_pass","track":"Höhenlicht","bpm":game.audio.live_music.clock.bpm,"characters":CHARACTERS,"materials":MATERIALS,"capacities":capacities,"facing":[1,-1,1,-1],"music_volume":game.audio.music_volume,"music_bus_db":AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music")),"dance_intensity":game.audio.dance_intensity,"music_intensity":game.audio.live_music.intensity,"minimum_head_tilt":minimum_angles,"maximum_head_tilt":maximum_angles,"maximum_grip_error":maximum_grip_error,"maximum_collider_error":maximum_collider_error,"head_only_actor_frames":head_only_frames,"full_load_actor_frames":full_carry_frames,"actual_kicks":kick_counts.size(),"capture_count":capture_count,"capture_start_frame":recording_start_frame,"capture_start_seconds":float(recording_start_frame)/60.0,"capture_duration_seconds":16.0,"close_camera_zoom":[close_zoom.x,close_zoom.y],"standard_camera_zoom":[standard_zoom.x,standard_zoom.y],"prepared_state":"Actual normal Gewitterpass MainScene, four original workers at full capacity via add_item, alternating facing; automatic enemy waves held at attack/wave10, original cinematic music intro allowed to finish; all world/actor physics, HUD and audible music active; first close camera then standard1.25 view"}
	print("CARRY CAPTURE VALIDATED: ",JSON.stringify(result))
	# Retire the native source while the owning ordinary scene still has main
	# loop updates, then use the shared resource-aware scene cleanup.
	game.audio.live_music.end_session()
	for index in 4: await frame()
	print("CARRY CAPTURE CLEANUP BEGIN")
	check(await Cleanup.free_scene(game,self),"Recorded ordinary game releases native playback and real workers cleanly")
	print("CARRY CAPTURE CLEANUP END")
	result.checks = checks
	result.failures = failures
	var file := FileAccess.open(DIRECTORY+"/render-verification.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"\t"))
	file.close()
	print("CARRY HEAD NOD CAPTURE: ",JSON.stringify(result))
	quit(1 if failures else 0)
