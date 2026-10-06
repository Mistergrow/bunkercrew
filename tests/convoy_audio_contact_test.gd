extends SceneTree
## Actual imported positional voices: progress, joining, mute and pause contacts.
const ConvoyAudio := preload("res://scripts/convoy_audio.gd")
const VehicleArt := preload("res://scripts/convoy_vehicle_art.gd")
const Cleanup := preload("res://tests/scene_cleanup.gd")
var checks := 0
var failures := 0

class Audition extends ConvoyAudio:
	var heard: Array[String] = []
	func play_effect(kind: String) -> bool:
		var played := super.play_effect(kind)
		if played: heard.append(kind)
		return played

class Seat extends Node2D:
	var occupant: Node2D

class Truck extends Node2D:
	var velocity := Vector2.ZERO
	var top_speed := 125.0
	var acceleration := 190.0
	var fuel := 12.0
	var destroyed := false
	var facing := 1.0
	var seats: Array[Node2D] = []
	var driver_seat: Node2D
	var journey_state := {"phase":"repair", "event_serial":0, "events":[], "repair_step":"none", "repair_work":0.0, "repair_operator":1, "phase_time":0.0}
	func service_point() -> Vector2: return global_position + Vector2(-65 * facing, -20)

func _initialize() -> void: _run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	print("CONVOY CONTACT %s: %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1
		push_error(label)

func fixture() -> Truck:
	var truck := Truck.new()
	truck.driver_seat = Seat.new()
	truck.add_child(truck.driver_seat)
	root.add_child(truck)
	var sound := Audition.new()
	sound.name = "Sound"
	truck.add_child(sound)
	sound.set_process(false)
	return truck

func observe(truck: Truck, step: String, work: float) -> void:
	truck.journey_state.repair_step = step
	truck.journey_state.repair_work = work
	truck.get_node("Sound")._process(1.0 / 60.0)

func reset_voices(sound: Audition) -> void:
	sound.stop_effects()
	sound._effect_cooldown.clear()

func _run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args():
		push_error("Use -- --no-profile-save --no-upnp")
		quit(2)
		return
	var sfx := AudioServer.get_bus_index("SFX")
	check(sfx >= 0, "project audio layout supplies the positional SFX bus")
	if sfx < 0:
		quit(1)
		return
	var original_mute := AudioServer.is_bus_mute(sfx)
	AudioServer.set_bus_mute(sfx, false)
	var truck := fixture()
	var sound := truck.get_node("Sound") as Audition
	check(sound.effects.size() == 19, "all new contact roles load through imported WAV resources")
	for step in ["fit", "lower"]:
		reset_voices(sound)
		var before := sound.heard.count(step + "_contact")
		observe(truck, step, 0.0)
		observe(truck, step, .1)
		check(sound.heard.has(step), step + ": held work begins movement foley")
		observe(truck, step, .91)
		check(sound.heard.count(step + "_contact") == before, step + ": no impact during tire travel or hydraulic descent")
		observe(truck, step, .95)
		check(sound.heard.count(step + "_contact") == before + 1, step + ": actual seating or ground arrival emits one impact")
		for voice in sound.effect_voices:
			if str(voice.get_meta("kind", "")) == step + "_contact":
				check(voice.position.is_equal_approx(Vector2(-65,-20)), step + ": impact comes from the service axle")
		reset_voices(sound)
		for unused in 90: observe(truck, step, 1.0)
		check(sound.heard.count(step + "_contact") == before + 1, step + ": repeated snapshots never replay settled contact")
		observe(truck, "none", 0.0)
		observe(truck, step, .96)
		observe(truck, step, 1.0)
		check(sound.heard.count(step + "_contact") == before + 1, step + ": joining a completed contact establishes a silent baseline")
		observe(truck, "none", 0.0)
		observe(truck, step, 0.0)
		AudioServer.set_bus_mute(sfx, true)
		observe(truck, step, .98)
		AudioServer.set_bus_mute(sfx, false)
		observe(truck, step, 1.0)
		check(sound.heard.count(step + "_contact") == before + 1, step + ": unmuting does not replay a contact completed while muted")
		observe(truck, "none", 0.0)
		observe(truck, step, 0.0)
		truck.journey_state.repair_operator = 0
		observe(truck, step, .98)
		check(sound.heard.count(step + "_contact") == before + 1, step + ": unattended progress cannot manufacture repair sound")
		truck.journey_state.repair_operator = 1
		observe(truck, "none", 0.0)
	truck.facing = -1
	reset_voices(sound)
	observe(truck, "fit", 0.0)
	observe(truck, "fit", .96)
	for voice in sound.effect_voices:
		if str(voice.get_meta("kind", "")) == "fit_contact":
			check(voice.position.is_equal_approx(Vector2(65,-20)), "mirrored truck keeps contact sound on its actual rear axle")
	var heard := sound.heard.size()
	paused = true
	check(not sound.play_effect("lower_contact"), "pause prevents new repair contact playback")
	paused = false
	check(sound.heard.size() == heard, "paused input never adds a voice")
	check(sound.effect_voices.size() == 4, "new contacts retain the fixed four-voice budget")
	reset_voices(sound)
	truck.journey_state.phase_time = 0.0
	observe(truck, "jack", 0.0)
	var pump_start := Time.get_ticks_usec()
	var pump_count := sound.heard.count("jack")
	var repeats := 0
	var maximum_error := 0.0
	while Time.get_ticks_usec() - pump_start < 1300000:
		var elapsed := float(Time.get_ticks_usec() - pump_start) / 1000000.0
		truck.journey_state.phase_time = elapsed
		observe(truck, "jack", elapsed / 4.0)
		var now_count := sound.heard.count("jack")
		if now_count > pump_count:
			# Initial work starts the movement sound; following pulses must
			# arrive at the physically lowest authored lever grip.
			if elapsed > .3:
				repeats += 1
				var grip := VehicleArt.jack_grip(truck, {"working":true, "phase_time":elapsed})
				maximum_error = maxf(maximum_error, absf(grip.y - (-1.5)))
			pump_count = now_count
		await create_timer(.008, true, false, true).timeout
	check(repeats >= 2, "real-time advancing jack work emits repeated loaded strokes")
	check(maximum_error < .15, "jack accents occur at the authored lowest grip rather than its raised return")
	AudioServer.set_bus_mute(sfx, original_mute)
	await Cleanup.free_scene(truck, self)
	print("CONVOY AUDIO CONTACTS: %d passed, %d failed" % [checks-failures, failures])
	quit(1 if failures else 0)
