extends SceneTree
## Normal SAN-1 physics, paid tech unlocks and audible native level music.
## Only the automatic enemy spawner is held for the prepared idle dance view.
const Catalog := preload("res://scripts/medic_dance_catalog.gd")
const Cleanup := preload("res://tests/scene_cleanup.gd")
const OUTPUT := "res://artifacts/san-bunker-dance"
const OPTIONS := {"environment":"ash_foundry","build_type":"workshop","position":"left"}
var game: Node
var medic: CharacterBody2D
var checks := 0
var failures := 0
var frames := 0
var captures: Array[Dictionary] = []
var seen: Dictionary = {}
var first_dance_frame := -1
var pcm_frames := 0
var pcm_peak := 0.0
var pcm_squared := 0.0
var pcm_finite := true
var music_bus := -1
var music_effect := -1
var pcm: AudioEffectCapture

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)

func step() -> void:
	await process_frame
	frames += 1
	if pcm != null and pcm.get_frames_available() > 0:
		var buffer := pcm.get_buffer(pcm.get_frames_available())
		pcm_frames += buffer.size()
		for sample: Vector2 in buffer:
			pcm_finite = pcm_finite and sample.is_finite()
			pcm_peak = maxf(pcm_peak,maxf(absf(sample.x),absf(sample.y)))
			pcm_squared += float(sample.x)*float(sample.x)+float(sample.y)*float(sample.y)

func capture(name: String, detail: Dictionary = {}) -> void:
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(OUTPUT + "/" + name + ".png") == OK,"Actual gameplay viewport saves "+name)
	var entry := {"name":name,"frame":frames,"seconds":float(frames)/60.0,"robot_position":medic.global_position,"audible_frame":game.audio.live_music.rhythm_frame().duplicate(true),"dance":medic.rhythm_pose.state()}
	entry.merge(detail)
	captures.append(entry)

func _run() -> void:
	if DisplayServer.get_name() == "headless" or "--no-profile-save" not in OS.get_cmdline_user_args() or "--no-upnp" not in OS.get_cmdline_user_args():
		push_error("SAN-1 dance capture requires graphics, --no-profile-save and --no-upnp")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	root.size = Vector2i(1440,900)
	LocaleText.set_locale("de",false)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.combat_events.persistence_enabled = false
	game.audio.set_music_style("minimal_techno")
	game.audio.set_music_volume(0.5)
	game.audio.set_music_calibration(0.0)
	game.audio.set_rhythm_motion_reduced(false)
	game.start_scenario(1,OPTIONS)
	game.rounds.set_process(false)
	game.rounds.running = true
	game.rounds.phase = "attack"
	game.rounds.wave = 20
	medic = game.medic
	if not is_instance_valid(medic) or not medic.has_method("dance_level"):
		push_error("Main scene did not instantiate the production SAN-1 dance script")
		quit(1)
		return
	game.players[0].global_position = medic._home() + Vector2(100,0)
	game.players[0].since_hit = 99.0
	game.players[0].velocity = Vector2.ZERO
	game.set_camera_zoom(2.5)
	check(medic.has_method("dance_allowed") and medic.has_method("dance_level"),"Normal game owns the production SAN-1 dance integration")
	check(medic.is_physics_processing(),"SAN-1 keeps normal medical/navigation physics throughout the recording")
	check(medic.dance_level() == 0 and not medic.dance_allowed(),"Unresearched SAN-1 retains its usual standby pose")
	game.upgrades.add_points(100)
	for id: String in ["bunker_dance","bunker_dance_2","bunker_dance_3","bunker_dance_4","bunker_dance_5"]:
		check(game.upgrades.purchase(id),"Real shared research purchase unlocks "+id)
	check(medic.dance_level() == 5,"Five paid software levels unlock the full robot repertoire")
	if medic.dance_level() != 5:
		quit(1)
		return
	check(not game.upgrades.has_upgrade("medic_logistics") and not game.upgrades.has_upgrade("medic_collection"),"Idle fixture has no unlocked unattended logistics job")
	check(game.audio.live_music.native_active and game.audio.live_music.environment_id == "ash_foundry","Normal level session plays the native Aschewerk minimal-techno score")
	music_bus = AudioServer.get_bus_index("Music")
	pcm = AudioEffectCapture.new()
	pcm.buffer_length = 0.5
	AudioServer.add_bus_effect(music_bus,pcm)
	music_effect = AudioServer.get_bus_effect_count(music_bus)-1
	var home: Vector2 = medic._home()
	var maximum_idle_drift := 0.0
	var collider: CollisionShape2D = medic.get_child(0)
	var initial_shape: Vector2 = collider.shape.size
	var initial_mask := medic.collision_mask
	var kick_counts: Dictionary = {}
	for tick in 9000:
		await step()
		var rhythm: Dictionary = game.audio.live_music.rhythm_frame()
		kick_counts[int(rhythm.get("kick_count",0))] = true
		if not medic.rhythm_pose.is_active():
			continue
		if first_dance_frame < 0: first_dance_frame = frames
		maximum_idle_drift = maxf(maximum_idle_drift,medic.global_position.distance_to(home))
		var style: String = medic.rhythm_pose.style
		var pose: Dictionary = medic.rhythm_pose.pose
		if not seen.has(style) and medic.rhythm_pose._previous_pose.is_empty() and float(pose.get("head_drop",0.0)) > 2.5:
			seen[style] = true
			await capture("move-%d-%s" % [Catalog.required_level(style),style],{"label":Catalog.label(style)})
		if seen.size() == 5 and frames-first_dance_frame > 60*38:
			break
	check(seen.size() == 5,"All five researched moves render in normal native-musical phrases")
	check(maximum_idle_drift < 10.1,"Complete robot dance remains at the real standby station")
	check(collider.shape.size == initial_shape and medic.collision_mask == initial_mask,"Dance retains normal collision dimensions and masks")
	check(medic.medical_supplies == MedicalCatalog.MAX_CHARGES and medic.logistics_cargo.is_empty(),"Idle dance spends no medical charge and invents no cargo")
	check(kick_counts.size() > 40,"Repertoire follows many genuine native audible kick events")
	game.audio.set_rhythm_motion_reduced(true)
	for tick in 8: await step()
	check(not medic.rhythm_pose.is_active(),"Reduced-motion preference immediately restores normal SAN-1 art")
	await capture("06-reduced-motion")
	game.audio.set_rhythm_motion_reduced(false)
	for tick in 160:
		await step()
		if medic.rhythm_pose.is_active(): break
	check(medic.rhythm_pose.is_active(),"Normal motion resumes only after newly heard kicks")
	game.audio.set_music_volume(0.0)
	for tick in 8: await step()
	check(not medic.rhythm_pose.is_active(),"Muted music immediately stops the robot dance")
	game.audio.set_music_volume(0.5)
	for tick in 160:
		await step()
		if medic.rhythm_pose.is_active(): break
	var player: Node = game.players[0]
	player.invulnerability = 0.0
	player.take_damage(12.0)
	for tick in 12: await step()
	check(is_instance_valid(medic.target) and medic.target == player and not medic.rhythm_pose.is_active(),"Real player injury interrupts dancing for the actual medical mission")
	# Frame both sides of the actual task. The ordinary follow camera would
	# otherwise leave the small robot outside the frame as the patient moves.
	game.player_camera.set_process(false)
	game.camera.zoom = Vector2.ONE*1.6
	game.camera.position = medic.global_position.lerp(player.global_position,0.5)+Vector2(0,-90)
	game.camera.force_update_scroll()
	await capture("07-new-medical-task",{"patient_hp":player.hp,"status":medic.status_label,"expression":medic.expression.kind})
	check(medic.expression.kind == "alert","New medical mission shows a brief pixel alert cue")
	# Patient/terrain are deliberately prepared; the robot uses the real route
	# planner and no injected cosmetic expression or path failure flag.
	player.global_position = home + Vector2(300,0)
	var barrier: Node = game.add_terrain(Rect2(home.x+145,home.y-220,35,220))
	var blocked := false
	for tick in 600:
		await step()
		if medic.expression.kind == "search":
			blocked = true
			break
	check(blocked and not medic.rhythm_pose.is_active(),"Real blocked medical route produces a search cue without idle dancing")
	for tick in 8: await step()
	game.camera.position = medic.global_position.lerp(player.global_position,0.5)+Vector2(0,-90)
	game.camera.force_update_scroll()
	await capture("08-blocked-route",{"status":medic.status_label,"expression":medic.expression.kind})
	for tick in 100: await step()
	check(not medic.rhythm_pose.is_active() and medic.expression.kind.is_empty(),"Blocked task stays prioritized after its brief search cue expires")
	barrier.queue_free()
	check(pcm_finite and pcm_frames > 48000 and pcm_peak > 0.001 and pcm_peak <= 1.0,"Captured Music bus contains finite audible native stereo PCM")
	var report := {"checks":checks,"failures":failures,"actual_main_scene":true,"actual_native_audio":game.audio.live_music.native_active,"music_environment":"ash_foundry","actual_physics":medic.is_physics_processing(),"prepared_state":"Solo Aschewerk; normal SAN-1; only enemy spawner held; wave20 for research; 100 prepared tech points spent through actual purchase API; no logistics unlocked; camera zoom2.5 for dances and1.6 centered between actual robot/patient for task cues; real medical damage and terrain barrier after idle repertoire","injected_rhythm":false,"injected_robot_motion":false,"capture_start_seconds":float(maxi(first_dance_frame,0))/60.0,"seen_moves":seen.keys(),"maximum_idle_drift":maximum_idle_drift,"actual_music_pcm_frames":pcm_frames,"actual_music_pcm_peak":pcm_peak,"actual_music_pcm_rms":sqrt(pcm_squared/maxf(float(pcm_frames)*2,1)),"captures":captures}
	AudioServer.remove_bus_effect(music_bus,music_effect)
	check(await Cleanup.free_scene(game,self),"Native gameplay preview releases scene and audio cleanly")
	report.checks = checks
	report.failures = failures
	var file := FileAccess.open(OUTPUT+"/render-verification.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	print("SAN DANCE CAPTURE: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
