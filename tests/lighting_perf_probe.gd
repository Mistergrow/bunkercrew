extends "res://tests/visual_review_capture.gd"
## Attribution probe for the cost of presentation lighting and atmosphere.
## Stages the same late mixed wave as the visual-review perf shots
## (tests/visual_review_stage_action.gd: four players, 1920x1080), then
## measures each variant (one feature switched off) right after a baseline
## window and reports the difference, so the drift of the running wave cancels.
## Needs a graphical display (run it on the isolated one):
##   godot --audio-driver Dummy --fixed-fps 60 --path . --script tests/lighting_perf_probe.gd \
##     -- --no-profile-save --no-upnp [--environment=ash_foundry] [--rounds=3] [--out=<json>]
## Prints per variant: mean wall-clock frame ms, mean render CPU ms (viewport
## render + frame setup), both as the difference to the adjacent baselines,
## plus the average number of enabled and shadow-casting lights.
const WINDOW := 36
const WARM := 6
const VARIANTS := ["no_lights", "no_shadows", "pcf_none", "no_shot_shadows", "no_fixture", "no_combat", "no_fire",
	"no_modulate", "no_contact", "no_lighting_scripts", "no_precipitation", "no_weather_scripts",
	"no_actor_key", "no_room_grades", "shot_shadows_on", "without_pass2"]

var _rows: Dictionary = {}

func _initialize() -> void:
	_probe.call_deferred()

func _lights() -> Array:
	var found: Array = []
	var stack: Array = [game]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is Light2D: found.append(node)
		stack.append_array(node.get_children())
	return found

func _category(light: Light2D) -> String:
	var label := str(light.name)
	if label.begins_with("Fixture") or label.begins_with("Actor"): return "fixture"
	if label.begins_with("Shot"): return "shot"
	if label.begins_with("Blast"): return "blast"
	if label.begins_with("Fire"): return "fire"
	return "other"

func _find(label: String) -> Node:
	return game.find_child(label, true, false)

func _remember(node: Object, property: String) -> Variant:
	var key := StringName("probe_" + property)
	if not node.has_meta(key): node.set_meta(key, node.get(property))
	return node.get_meta(key)

func _apply(variant: String, on: bool) -> void:
	var lights := _lights()
	match variant:
		"no_lights":
			for light: Light2D in lights: light.visible = not on
		"no_shadows", "no_shot_shadows":
			for light: Light2D in lights:
				if variant == "no_shot_shadows" and _category(light) != "shot": continue
				var original: bool = _remember(light, "shadow_enabled")
				light.shadow_enabled = false if on else original
		"pcf_none":
			for light: Light2D in lights:
				var original: int = _remember(light, "shadow_filter")
				light.shadow_filter = Light2D.SHADOW_FILTER_NONE if on else original
		"no_fixture", "no_fire":
			var wanted: String = variant.trim_prefix("no_")
			for light: Light2D in lights:
				if _category(light) == wanted: light.visible = not on
		"no_combat":
			for light: Light2D in lights:
				if _category(light) in ["shot", "blast"]: light.visible = not on
		"no_modulate":
			var modulate := _find("Ambient") as CanvasItem
			if modulate != null: modulate.visible = not on
		"no_contact":
			var shadows := _find("ContactShadows") as CanvasItem
			if shadows != null: shadows.visible = not on
		"no_lighting_scripts":
			# Script work only: the lights keep their last state.
			for label in ["WorldLighting", "ContactShadows"]:
				var node := _find(label)
				if node != null: node.set_process(not on)
		"no_precipitation":
			var layer := _find("Precipitation") as CanvasItem
			if layer != null:
				layer.visible = not on
				layer.set_process(not on)
		"no_actor_key":
			var key := _find("ActorKey") as CanvasItem
			if key != null: key.visible = not on
		"no_room_grades":
			for grade in game.find_children("RoomGrade*", "", true, false):
				(grade as CanvasItem).visible = not on
		"shot_shadows_on":
			# The pass-1 state of the gunfire voices: PCF5 shadows on every one.
			for light: Light2D in lights:
				if _category(light) == "shot": light.shadow_enabled = on
		"without_pass2":
			# Approximates the lighting of pass 1 inside the same running wave:
			# no falling weather, no actor key, no room grades, shadowed gunfire.
			for part: String in ["no_precipitation", "no_actor_key", "no_room_grades", "shot_shadows_on"]: _apply(part, on)
		"no_weather_scripts":
			var sky: Node = game.get("weather")
			if is_instance_valid(sky):
				sky.set_process(not on)
				for child in sky.get_children(): child.set_process(not on)

func _window() -> Dictionary:
	var viewport := root.get_viewport_rid()
	var wall := 0.0
	var render := 0.0
	var enabled := 0.0
	var shadowed := 0.0
	for warm in WARM: await RenderingServer.frame_post_draw
	var previous := Time.get_ticks_usec()
	for index in WINDOW:
		await frames(1)
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		wall += float(now - previous) / 1000.0
		previous = now
		render += RenderingServer.viewport_get_measured_render_time_cpu(viewport) + RenderingServer.get_frame_setup_time_cpu()
		for light: Light2D in _lights():
			if light.enabled and light.is_visible_in_tree():
				enabled += 1.0
				if light.shadow_enabled: shadowed += 1.0
	return {"wall": wall / WINDOW, "render": render / WINDOW, "lights": enabled / WINDOW, "shadowed": shadowed / WINDOW}

func _probe() -> void:
	var arguments := OS.get_cmdline_user_args()
	if "--no-profile-save" not in arguments or "--no-upnp" not in arguments or DisplayServer.get_name() == "headless":
		push_error("lighting_perf_probe needs a graphical display and --no-profile-save --no-upnp")
		quit(2)
		return
	var environment := _argument("--environment=")
	if environment.is_empty(): environment = "ash_foundry"
	var rounds := int(_argument("--rounds=")) if not _argument("--rounds=").is_empty() else 3
	AudioServer.set_bus_mute(0, true)
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1920, 1080)
	spec = {"id": "perf.wave_night.gpu", "seed": 7001 + absi("perf.wave_night.gpu".hash()) % 100000, "args": {"environment": environment}, "size": [1920, 1080]}
	if ResourceLoader.exists("res://scripts/ui_motion.gd"):
		var motion: Variant = load("res://scripts/ui_motion.gd")
		if motion != null and motion.has_method("force"): motion.call("force", false)
		if motion != null and motion.has_method("set_manual_clock"): motion.call("set_manual_clock", -1.0)
	park_pointer()
	await frames(3)
	await STAGES.action._wave(self, spec)
	if failed():
		print("PROBE FAIL ", failure)
		quit(1)
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	print("PROBE adapter ", RenderingServer.get_video_adapter_name(), " environment ", environment)
	var base_rows: Array = []
	for variant: String in VARIANTS: _rows[variant] = []
	for round_index in rounds:
		for variant: String in VARIANTS:
			var base := await _window()
			_apply(variant, true)
			var row := await _window()
			_apply(variant, false)
			base_rows.append(base)
			_rows[variant].append({"wall": row.wall - base.wall, "render": row.render - base.render, "lights": row.lights, "shadowed": row.shadowed})
	var summary := {}
	var mean := func(rows: Array, key: String) -> float:
		var total := 0.0
		for row: Dictionary in rows: total += float(row[key])
		return snappedf(total / maxf(1.0, rows.size()), 0.01)
	summary["base"] = {"wall": mean.call(base_rows, "wall"), "render": mean.call(base_rows, "render"), "lights": mean.call(base_rows, "lights"), "shadowed": mean.call(base_rows, "shadowed")}
	print("PROBE %-20s wall %6.2f ms   render %6.2f ms   lights %5.2f  shadowed %5.2f" % ["base (absolute)", summary.base.wall, summary.base.render, summary.base.lights, summary.base.shadowed])
	for variant: String in VARIANTS:
		var rows: Array = _rows[variant]
		summary[variant] = {"wall": mean.call(rows, "wall"), "render": mean.call(rows, "render"), "lights": mean.call(rows, "lights"), "shadowed": mean.call(rows, "shadowed")}
		print("PROBE %-20s wall %+6.2f ms   render %+6.2f ms   lights %5.2f  shadowed %5.2f" % [variant, summary[variant].wall, summary[variant].render, summary[variant].lights, summary[variant].shadowed])
	var out := _argument("--out=")
	if not out.is_empty():
		var file := FileAccess.open(out, FileAccess.WRITE)
		file.store_string(JSON.stringify({"adapter": RenderingServer.get_video_adapter_name(), "environment": environment, "rounds": rounds, "summary": summary, "rows": _rows, "base_rows": base_rows}, "\t"))
		file.close()
	await _close()
	quit(0)
