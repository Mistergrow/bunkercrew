extends SceneTree

class SoundSpy extends Node:
	var sounds: Array[String] = []
	func sound(kind: String) -> void:
		sounds.append(kind)

var failures := 0
var checks := 0

func _initialize() -> void:
	call_deferred("run_checks")

func check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("PASS ", label)
	else:
		failures += 1
		push_error(label)

func run_checks() -> void:
	InputSetup.install()
	var weather := ShiftWeather.new()
	var spy := SoundSpy.new()
	root.add_child(spy)
	weather.game = spy
	root.add_child(weather)
	weather.set_process(false)
	check(weather.rain.size() + weather.dust.size() <= 150, "Atmosphere respects the particle budget")
	check(weather.rain_surface(400) == 245 and weather.rain_surface(1000) == 430, "Rain stops at the roof or exterior ground")
	check(not weather.is_outdoors(Vector2(400, 340)) and not weather.is_outdoors(Vector2(600, 780)), "Bunker interiors and mine are excluded from precipitation")
	check(not weather.is_outdoors(Vector2(850,390)) and weather.is_outdoors(Vector2(850,270)), "Attached defense gallery remains dry below its sloped roof")
	check(not weather.is_outdoors(Vector2(1100, 70)) and not weather.is_outdoors(Vector2(1100, 431)), "HUD and underground remain outside the weather region")
	check(weather.is_outdoors(Vector2(700, 180)) and weather.is_outdoors(Vector2(1100, 340)), "Sky above the roof and open battle approach receive rain")
	var dry_inside := true
	for step in 600:
		weather._process(1.0 / 60.0)
		for drop in weather.rain:
			var segment: PackedVector2Array = weather.rain_segment(drop)
			if segment.size()!=2 or not weather.is_outdoors(segment[0]) or not weather.is_outdoors(segment[1]):
				dry_inside = false
	check(dry_inside, "Ten seconds of actual particle updates keep every rain segment outside")
	weather._start_lightning()
	check(weather.lightning_wait >= 15 and weather.lightning_wait <= 30, "Lightning events are separated by 15 to 30 seconds")
	var bolt_outside := true
	for point in weather.bolt:
		if not weather.is_outdoors(point) or point.x < 805:
			bolt_outside = false
	check(bolt_outside, "Lightning geometry stays in the distant exterior sky")
	check(weather.lightning_strength() == 1, "Lightning begins with one short flash")
	weather._process(0.11)
	check(weather.lightning_strength() > 0 and weather.lightning_strength() < 0.24, "Flash fades to a dim afterglow after 100 milliseconds")
	weather._process(0.20)
	check(weather.lightning_strength() == 0, "Lightning illumination ends within 280 milliseconds")
	weather._process(1.0)
	check(spy.sounds == ["thunder"], "One delayed thunder sound follows the lightning")
	weather._start_lightning()
	weather.set_reduced_effects(true)
	var stopped_at := weather.elapsed
	weather._process(3.0)
	check(weather.elapsed == stopped_at and weather.lightning_strength() == 0 and spy.sounds.size() == 1, "Reduced effects stop motion and cancel flash and pending thunder")
	weather.set_reduced_effects(false)
	weather._process(0.1)
	check(weather.elapsed > stopped_at, "Normal weather resumes when reduced effects are disabled")
	var key := InputEventKey.new()
	key.physical_keycode = KEY_F3
	check(InputMap.event_is_action(key, "weather_toggle"), "F3 exposes the reduced-weather option through InputMap")
	var audio = load("res://scripts/audio.gd").new()
	root.add_child(audio)
	var thunder: AudioStreamWAV = audio.streams["thunder"]
	check(thunder.format == AudioStreamWAV.FORMAT_16_BITS and thunder.mix_rate == 32000 and is_equal_approx(thunder.get_length(), 1.8), "Thunder is a self-generated 1.8 second, 32 kHz audio asset")
	check(thunder.data.decode_s16(0) == 0, "Thunder starts silently for a soft attack")
	await create_timer(0.06).timeout
	if not await preload("res://tests/scene_cleanup.gd").free_scene(audio,self):
		failures+=1
	weather.queue_free()
	spy.queue_free()
	await process_frame
	print("WEATHER CHECKS: %d passed, %d failed" % [checks-failures, failures])
	quit(0 if failures == 0 else 1)
