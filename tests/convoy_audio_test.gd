extends SceneTree
## Real imported truck voices through the Godot mixer; isolated Dummy audio.
const ConvoyAudio := preload("res://scripts/convoy_audio.gd")
const Vehicle := preload("res://scripts/convoy_vehicle.gd")
const Journey := preload("res://scripts/convoy_journey.gd")
const Cleanup := preload("res://tests/scene_cleanup.gd")
const OUTPUT := "res://artifacts/convoy-drive/audio"
var checks := 0
var failures := 0
var game: Node
var audio: Node
var truck: Node2D
var sound: AudioStreamPlayer2D
var capture: AudioEffectCapture
var recorded := PackedVector2Array()
var sections: Dictionary = {}

class AudioFixture extends Node2D:
	var velocity := Vector2.ZERO
	var top_speed := 125.0
	var acceleration := 190.0
	var fuel := 12.0
	var destroyed := false
	var driver_seat: Node2D
	var seats: Array[Node2D] = []
	var journey_state := {"phase":"boarding", "event_serial":0, "events":[], "repair_step":"none", "repair_work":0.0, "repair_operator":0}

class FixtureSeat extends Node2D:
	var occupant: Node2D

func _initialize() -> void: _run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	print("CONVOY AUDIO %s: %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1
		push_error(label)

func freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children(): freeze(child)

func wait_seconds(seconds: float) -> void:
	var deadline := Time.get_ticks_usec() + roundi(seconds * 1000000)
	while Time.get_ticks_usec() < deadline:
		await create_timer(.008, true, false, true).timeout

func stats(data: PackedVector2Array) -> Dictionary:
	var power := 0.0
	var peak := 0.0
	var finite := true
	for value in data:
		power += value.length_squared()
		peak = maxf(peak, maxf(absf(value.x), absf(value.y)))
		finite = finite and value.is_finite()
	return {"frames":data.size(), "rms":sqrt(power / maxf(1.0, data.size() * 2.0)), "peak":peak, "finite":finite}

func observe(frames := 60) -> void:
	for unused in frames: sound._process(1.0 / 60.0)

func event(kind: String) -> void:
	truck.journey_state.event_serial += 1
	truck.journey_state.events.append({"serial":truck.journey_state.event_serial, "kind":kind, "quality":"normal"})
	if truck.journey_state.events.size() > 16: truck.journey_state.events.pop_front()
	sound._process(1.0 / 60.0)

func stop_foley() -> void:
	for voice in sound.effect_voices: voice.stop()
	sound._effect_cooldown.clear()

func count_kind(kind: String) -> int:
	var count := 0
	for voice in sound.effect_voices:
		if voice.playing and str(voice.get_meta("kind", "")) == kind: count += 1
	return count

func segment(label: String, seconds: float) -> Dictionary:
	await wait_seconds(.12)
	capture.clear_buffer()
	await wait_seconds(seconds)
	var metrics := stats(capture.get_buffer(capture.get_frames_available()))
	sections[label] = metrics
	print("PCM ", label, " ", metrics)
	return metrics

func demo_stage(label: String, seconds: float) -> void:
	capture.clear_buffer()
	var began := Time.get_ticks_usec()
	var deadline := began + roundi(seconds * 1000000)
	var step := "remove" if label == "remove" else label
	var working := ConvoyAudio.WORK_EFFECTS.has(step)
	if working:
		truck.journey_state.repair_step = step
		truck.journey_state.repair_operator = 1
		truck.journey_state.repair_work = 0.0
	while Time.get_ticks_usec() < deadline:
		if working: truck.journey_state.repair_work = clampf(float(Time.get_ticks_usec() - began) / (seconds * 1000000), 0, 1)
		sound._process(1.0 / 60.0)
		await create_timer(1.0 / 60.0, true, false, true).timeout
	var data := capture.get_buffer(capture.get_frames_available())
	sections["demo: " + label] = stats(data)
	recorded.append_array(data)
	if working: truck.journey_state.repair_operator = 0

func _run() -> void:
	if AudioServer.get_driver_name() != "Dummy" or "--no-profile-save" not in OS.get_cmdline_user_args() or "--no-upnp" not in OS.get_cmdline_user_args():
		push_error("Run isolated with --audio-driver Dummy -- --no-profile-save --no-upnp")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	audio = game.audio
	game.start_scenario(1, {"environment":"ash_foundry", "position":"left", "build_type":"bastion"})
	game.rounds.running = false
	await process_frame
	freeze(game)
	audio.menu_music.stop()
	audio.live_music.end_session()
	for deck in audio.music_players: deck.stop()
	for voice in audio.voices: voice.stop()
	audio.movement.stop_effects()
	audio.upgrade_audio.stop_effects()
	game.dialogue.reset()
	if audio.acoustics != null:
		audio.acoustics.release()
		audio.acoustics = null
	paused = false
	game.camera.position = Vector2(720, 430)
	game.camera.reset_smoothing()
	var master := AudioServer.get_bus_index("Master")
	var capture_index := AudioServer.get_bus_effect_count(master)
	capture = AudioEffectCapture.new()
	capture.buffer_length = 20
	AudioServer.add_bus_effect(master, capture)
	truck = AudioFixture.new()
	truck.position = game.camera.get_screen_center_position()
	game.add_child(truck)
	var seat := FixtureSeat.new()
	truck.add_child(seat)
	truck.driver_seat = seat
	truck.seats.append(seat)
	sound = ConvoyAudio.new()
	truck.add_child(sound)
	sound.set_process(false)
	check(sound.layers.size() == 4 and sound.effect_voices.size() == 4 and sound.effects.size() == 19, "four loops and four fixed effect voices load nineteen imported foley roles including axle and ground contact")
	for kind: String in sound.layers:
		var layer: AudioStreamPlayer2D = sound.layers[kind]
		var loop_recording: AudioStreamWAV = layer.stream
		check(layer.bus == "SFX" and layer.process_mode == Node.PROCESS_MODE_PAUSABLE and layer.max_distance == 1100 and layer.panning_strength > 0 and layer.max_polyphony == 1, kind + ": bounded spatial SFX routing and explicit pause behavior")
		check(loop_recording != null and loop_recording.mix_rate == 48000 and not loop_recording.stereo and loop_recording.loop_mode == AudioStreamWAV.LOOP_FORWARD and loop_recording.loop_begin == 0 and loop_recording.loop_end == 384000, kind + ": exact imported eight-second mono loop")
	check(audio.music_volume == .5 and audio.sfx_volume == .5 and audio.voice_volume == .5, "existing fifty-percent defaults remain unchanged")
	truck.journey_state.event_serial = 3
	truck.journey_state.events = [{"serial":3, "kind":"breakdown", "quality":"normal"}]
	observe()
	check(sound.effects_played == 0 and not sound.playing, "first replica snapshot silently baselines old events and boarding keeps engine off")
	truck.journey_state.phase = "starting"
	event("engine_start")
	check(count_kind("start") == 1, "new replicated engine_start plays its real starter once")
	var serial: int = sound.effects_played
	observe()
	check(sound.effects_played == serial, "reapplying a snapshot never duplicates its starter")
	stop_foley()
	observe()
	var idle := await segment("stationary idle", .42)
	check(sound.playing and not sound.layers.torque.playing and not sound.layers.road.playing and not sound.layers.clatter.playing, "stationary engine idles with no tire, loaded engine or cargo clatter")
	check(idle.finite and idle.frames > 12000 and idle.rms > .0002 and idle.peak < .20, "actual stationary diesel reaches the master mixer with finite headroom")
	truck.journey_state.phase = "driving"
	truck.velocity.x = 125
	observe(120)
	stop_foley()
	var moving := await segment("loaded rolling", .42)
	check(sound.layers.values().all(func(v): return v.playing), "speed activates torque, road and body layers independently")
	check(moving.finite and moving.rms > idle.rms * 1.05 and moving.peak < .20, "actual loaded driving is stronger than idle and keeps mixed headroom")
	var full_pitch: float = sound.layers.torque.pitch_scale
	truck.velocity.x = 35
	observe(120)
	check(sound.layers.torque.pitch_scale < full_pitch - .15, "replicated slowing changes actual layer pitch smoothly")
	stop_foley()
	sound._last_gear = 1
	sound._last_speed = 35
	serial = sound.effects_played
	for rate in [.285, .305, .30, .29, .31, .28]:
		truck.velocity.x = 125 * rate
		sound._process(1.0 / 60.0)
	check(sound.effects_played == serial, "velocity jitter inside a gear hysteresis band produces no repeated shifts")
	truck.velocity.x = 0
	truck.journey_state.phase = "repair"
	event("breakdown")
	check(count_kind("tire_puncture") == 1, "new replicated breakdown uses rubber rupture and pressure release")
	observe(120)
	stop_foley()
	var stopped := await segment("engine off after breakdown", .23)
	check(sound.layers.values().all(func(v): return not v.playing) and stopped.rms < .000001, "stationary roadside repair has no phantom running or rolling layers")
	for pair in [["bolt","bolt_success"],["tool_miss","tool_miss"],["repair_complete","repair_done"]]:
		stop_foley()
		event(pair[0])
		check(count_kind(pair[1]) == 1, pair[0] + ": real repair event selects its distinct mechanical recording")
	for step: String in ["jack", "remove", "fit", "lower"]:
		stop_foley()
		truck.journey_state.repair_step = step
		truck.journey_state.repair_work = 0.0
		truck.journey_state.repair_operator = 0
		serial = sound.effects_played
		event(step)
		check(sound.effects_played == serial, step + ": entering a requested work stage without action stays silent")
		truck.journey_state.repair_operator = 1
		truck.journey_state.repair_work = .03
		sound._process(.02)
		check(count_kind(ConvoyAudio.WORK_EFFECTS[step]) == 1, step + ": actual progress starts the matching mechanical recording")
	stop_foley()
	truck.journey_state.repair_step = "remove"
	truck.journey_state.repair_operator = 1
	truck.journey_state.repair_work = 0.0
	sound._process(.01)
	serial = sound.effects_played
	for index in 100:
		truck.journey_state.repair_work = index * .001
		sound._process(.01)
	check(sound.effects_played > serial, "slow high-FPS repair work accumulates enough travel for real ratchet foley")
	stop_foley()
	serial = sound.effects_played
	for unused in 120: sound._process(.01)
	check(sound.effects_played == serial, "a held progress cursor without work never manufactures wrench sounds")
	truck.journey_state.solo_assist = true
	truck.journey_state.repair_operator = 0
	stop_foley()
	truck.journey_state.repair_step = "jack"
	truck.journey_state.repair_work = 0.0
	sound._process(.01)
	truck.journey_state.repair_work = .02
	sound._process(.02)
	check(count_kind("jack") == 1, "solo assistance makes foley only when its real mechanical work advances")
	truck.journey_state.solo_assist = false
	stop_foley()
	for kind in ["caution","start","repair_done","tire_puncture"]: sound.play_effect(kind)
	check(sound.effect_voices.all(func(v): return v.playing), "effect concurrency stays within its fixed four voices")
	check(not sound.play_effect("gear") and count_kind("tire_puncture") == 1 and count_kind("repair_done") == 1, "minor gear sound cannot steal active safety or completed repair feedback")
	stop_foley()
	check(sound.play_effect("door") and count_kind("door_close") == 1 and not sound.play_effect("door"), "legacy door alias remains supported with per-role anti-spam")
	stop_foley()
	paused = true
	check(not sound.can_process() and sound.layers.values().all(func(v): return not v.can_process()) and not sound.play_effect("jack"), "pause disables every convoy source and rejects new effect playback")
	await wait_seconds(.12)
	capture.clear_buffer()
	await wait_seconds(.18)
	check(stats(capture.get_buffer(capture.get_frames_available())).rms < .000001, "paused actual mixer emits no convoy PCM")
	paused = false
	audio.set_sfx_volume(0)
	serial = sound.effects_played
	event("jack")
	truck.journey_state.phase = "driving"
	truck.velocity.x = 125
	observe()
	check(sound.effects_played == serial and sound.layers.values().all(func(v): return not v.playing) and not sound.play_effect("start"), "muted SFX stops every loop, consumes snapshots and rejects new effects")
	var muted := await segment("muted driving", .20)
	check(muted.rms < .000001, "actual muted effects bus emits no moving vehicle PCM")
	audio.set_sfx_volume(.5)
	observe()
	check(sound.effects_played == serial, "unmute restores current running state without replaying old repair events")
	var restored := await segment("restored driving", .24)
	check(restored.rms > .0002 and restored.peak < .20, "unmuted imported layers return through the unchanged effects bus")
	truck.destroyed = true
	observe(120)
	stop_foley()
	check(sound.layers.values().all(func(v): return not v.playing), "destroyed truck fades and releases every running layer")
	truck.destroyed = false
	truck.journey_state.phase = "boarding"
	truck.velocity = Vector2.ZERO
	truck.journey_state.event_serial = 0
	truck.journey_state.events = []
	observe()
	serial = sound.effects_played
	event("boarding")
	check(sound.effects_played == serial + 1 and count_kind("door_close") == 1, "reset trip rebaselines its serial then accepts a new event")
	stop_foley()
	truck.journey_state.phase = "reboarding"
	observe(120)
	check(sound.layers.values().all(func(v): return not v.playing), "reboarding remains engine-off until its real new engine_start")
	truck.journey_state.phase = "boarding"
	var live_vehicle := Vehicle.new()
	live_vehicle.game = game
	game.add_child(live_vehicle)
	live_vehicle.set_process(false)
	live_vehicle.set_physics_process(false)
	var actual_audio: AudioStreamPlayer2D = live_vehicle.get_node("DieselEngine")
	actual_audio.set_process(false)
	check(actual_audio.get_script() == ConvoyAudio and actual_audio.layers.size() == 4 and actual_audio.effects.size() == 19, "real gameplay vehicle instantiates layered presentation without catalog or default changes")
	actual_audio._process(.016)
	Journey.change_phase(live_vehicle.journey_state, "driving", "engine_start")
	actual_audio._process(.016)
	check(actual_audio.effect_voices.any(func(v): return v.playing and v.get_meta("kind", "") == "start"), "real ConvoyJourney start event reaches the real gameplay vehicle's audio")
	Journey.begin_breakdown(live_vehicle.journey_state)
	actual_audio._process(.016)
	check(actual_audio.effect_voices.any(func(v): return v.playing and v.get_meta("kind", "") == "tire_puncture") and not actual_audio.effect_voices.any(func(v): return v.playing and v.get_meta("kind", "") == "jack"), "real Panne plus jack-stage event sounds only the tire until service actually begins")
	Journey.service(live_vehicle.journey_state, .05, false, true, 1)
	actual_audio._process(.016)
	check(actual_audio.effect_voices.any(func(v): return v.playing and v.get_meta("kind", "") == "jack"), "real held service work drives the gameplay vehicle's jack foley")
	live_vehicle.queue_free()
	await process_frame
	check(not is_instance_valid(actual_audio), "actual vehicle teardown releases its child audio players")
	# Audible showcase uses the same sources and actual mixer at normal wall time.
	truck.journey_state.repair_step = "none"
	truck.journey_state.repair_work = 0.0
	truck.journey_state.phase = "boarding"
	observe(120)
	stop_foley()
	event("boarding")
	await demo_stage("door closed", .8)
	event("departure")
	await demo_stage("departure caution", .9)
	truck.journey_state.phase = "starting"
	event("engine_start")
	await demo_stage("starter and idle", 2.5)
	truck.journey_state.phase = "driving"
	for speed in [20,45,80,125]:
		truck.velocity.x = speed
		await demo_stage("accelerate " + str(speed), .8)
	await demo_stage("rolling", 1.4)
	truck.velocity.x = 0
	truck.journey_state.phase = "repair"
	event("breakdown")
	await demo_stage("puncture", 1.9)
	for pair in [["jack",1.2],["remove",.9],["fit",.85],["bolt",.5],["tool_miss",.5],["lower",1.0],["repair_complete",1.5]]:
		event(pair[0])
		await demo_stage(pair[0], pair[1])
	var demo_stats := stats(recorded)
	check(demo_stats.finite and demo_stats.rms > .0002 and demo_stats.peak < .20, "normal-speed actual mixer demo contains finite audible trip and repair PCM")
	var recording := AudioStreamWAV.new()
	recording.format = AudioStreamWAV.FORMAT_16_BITS
	recording.stereo = true
	recording.mix_rate = roundi(AudioServer.get_mix_rate())
	var pcm := PackedByteArray()
	pcm.resize(recorded.size() * 4)
	for index in recorded.size():
		pcm.encode_s16(index * 4, roundi(clampf(recorded[index].x, -1, 1) * 32767))
		pcm.encode_s16(index * 4 + 2, roundi(clampf(recorded[index].y, -1, 1) * 32767))
	recording.data = pcm
	check(recording.save_to_wav(OUTPUT + "/runtime-demo.wav") == OK, "native Godot mixer demo saved as stereo PCM")
	sound.stop_effects()
	AudioServer.remove_bus_effect(master, capture_index)
	check(await Cleanup.free_scene(game, self), "main scene, layered voices and capture resources release cleanly")
	var report := FileAccess.open(OUTPUT + "/verification.json", FileAccess.WRITE)
	report.store_string(JSON.stringify({"checks":checks,"failures":failures,"sections":sections,"prepared_state":"Actual main-scene audio buses and camera; other sources stopped; real imported convoy runtime on a controlled replica-state fixture plus actual gameplay vehicle lifecycle. Dummy driver, fixed fifty-percent settings, no saved profiles, no microphone or network.","demo_rate":recording.mix_rate,"demo_seconds":float(recorded.size()) / recording.mix_rate,"user_profiles_modified":false}, "\t") + "\n")
	report.close()
	print("CONVOY AUDIO: %d/%d checks passed" % [checks - failures, checks])
	quit(1 if failures else 0)
