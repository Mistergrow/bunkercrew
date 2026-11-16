extends "res://tests/visual_review_capture.gd"
## Readability captures on top of the visual-review instrument (same driver,
## same staging primitives, real game). Graphical display only; run through
## tests/threat_read_capture.py, which writes the shot file and measures the
## enemy-vs-background contrast from the A/B frames.
## Stages ("read" stage, method in the shot spec):
## - lineup: every ground and air class in a row at the bunker front, HUD
##   hidden, at a whole-pixel gameplay zoom. Captures three frames of the same
##   instant: team read on, team read and backdrop grade off (the art as it
##   was), and the enemies hidden (the background alone, for the mask).
## - hud_wave: a running mixed wave with the HUD, the camera on the ground
##   in front of the bunker so near enemies, their bars and edge arrows show.
const Action := preload("res://tests/visual_review_stage_action.gd")
const WetMaterials := preload("res://scripts/actor_wet_materials.gd")

func _run_shot() -> void:
	if str(spec.stage) == "read" and has_method("read_" + str(spec.method)):
		await call("read_" + str(spec.method), spec)
		_shot_done = true
		return
	await super._run_shot()

func _enemies() -> Array:
	var result: Array = []
	for enemy in get_nodes_in_group("enemies"):
		if enemy.get("game") == game: result.append(enemy)
	return result

func _set_read(enabled: bool, team_night: float) -> void:
	for enemy in _enemies():
		var wetness: Variant = enemy.get("wetness")
		if wetness == null or not is_instance_valid(wetness): continue
		for item: CanvasItem in wetness._material_items:
			item.set_instance_shader_parameter("team", WetMaterials.TEAM_HOSTILE if enabled else WetMaterials.TEAM_NONE)
	WetMaterials.set_team_night(team_night)
	var grade: Node = game.scenery.get_node_or_null("BackdropGrade") if is_instance_valid(game.get("scenery")) else null
	if grade != null: grade.visible = enabled

func _shoot(name: String) -> void:
	var path := "%s.%s.png" % [str(spec.id), name]
	if await _grab(path): files.append(path)

func read_lineup(shot: Dictionary) -> void:
	await play(1, str(shot.args.environment), {"hud": false})
	if failed(): return
	var bunker = game.scenario_bunker
	var ground := float(bunker.ground_y)
	var cursor := float(bunker.room_right) + 90.0
	var kinds: Array = Array(EnemyCatalog.GROUND_CLASSES)
	var placed: Array = []
	for kind: String in kinds:
		var profile: Dictionary = EnemyCatalog.profile(kind)
		var width := maxf(float((profile.get("hitbox", Vector2(60, 50)) as Vector2).x) * 1.25, 46.0) + 14.0
		var scene := "ground_infantry" if EnemyCatalog.is_human(kind) else "enemy"
		var actor = spawn(scene, Vector2(cursor + width * .5, ground), {"kind": kind, "wave": int(EnemyCatalog.INTRO_WAVES.get(kind, 1))})
		if actor == null: return
		placed.append(actor)
		cursor += width
	var air_cursor := float(bunker.room_right) + 90.0
	for kind: String in AirEnemyCatalog.CLASS_ORDER:
		var profile: Dictionary = AirEnemyCatalog.profile(kind)
		var width := float((profile.get("body_size", Vector2(60, 40)) as Vector2).x) + 30.0
		var actor = spawn("air_enemy", Vector2(air_cursor + width * .5, ground - 190.0), {"kind": kind, "wave": int(AirEnemyCatalog.INTRO_WAVES.get(kind, 1))})
		if actor == null: return
		placed.append(actor)
		air_cursor += width
	await frames(3)
	for actor in placed: actor.set_physics_process(false)
	var right := maxf(cursor, air_cursor)
	var left := float(bunker.room_right) + 60.0
	var zoom := float(shot.args.get("zoom", 2.0))
	var view: Vector2 = root.get_visible_rect().size
	# Whole-pixel gameplay zoom; the camera pans over the lineup in strips.
	var strip := view.x / _grid_zoom(zoom).x
	var count := ceili((right - left) / strip)
	# A per-world survey (threat_read_capture.py --worlds) needs one strip.
	if shot.args.has("strips"): count = mini(count, int(shot.args.strips))
	note("lineup %d ground + %d air classes, %d strips at zoom %.1f" % [kinds.size(), AirEnemyCatalog.CLASS_ORDER.size(), count, zoom])
	await frames(40)
	var night := WetMaterials.team_night
	for index in count:
		camera_at(Vector2(left + strip * (index + .5), ground - 120.0), zoom)
		await frames(2)
		# The four frames of one strip show the same instant: clouds, water,
		# weather and idle motion hold while the read and the actors toggle.
		paused = true
		_set_read(true, night)
		await frames(1)
		await _shoot("s%d.on" % index)
		_set_read(false, night)
		await frames(1)
		await _shoot("s%d.off" % index)
		for actor in placed: actor.visible = false
		_set_read(true, night)
		await frames(1)
		await _shoot("s%d.bg_on" % index)
		_set_read(false, night)
		await frames(1)
		await _shoot("s%d.bg_off" % index)
		for actor in placed: actor.visible = true
		_set_read(true, night)
		paused = false
	extra["strips"] = count

func read_hud_wave(shot: Dictionary) -> void:
	await Action.stage_wave(self, str(shot.args.environment), true, 1)
	if failed(): return
	await frames(60 * int(shot.args.get("seconds", 14)))
	var bunker = game.scenario_bunker
	var zoom := float(shot.args.get("zoom", 2.0))
	var view: Vector2 = root.get_visible_rect().size
	camera_at(Vector2(float(bunker.room_right) + view.x / zoom * .5 - 120.0, float(bunker.ground_y) - 140.0), zoom)
	await frames(3)
	var overlay: Node = game.hud.canvas.get_node_or_null("ThreatOverlay")
	if overlay != null: extra["threat"] = overlay.diagnostics()
	await _shoot("hud")

## Frame time of a four-player late wave in one process and scene: all of
## this pass on, the threat overlay off, everything off (team read cleared,
## backdrop grade and threat overlay hidden), all on again.
func read_perf(shot: Dictionary) -> void:
	await Action.stage_wave(self, str(shot.args.environment), true, 4)
	if failed(): return
	await frames(60 * 6)
	var seconds := float(shot.args.get("seconds", 8.0))
	var overlay: Node = game.hud.canvas.get_node_or_null("ThreatOverlay")
	var results := {}
	for phase: String in ["on", "no_overlay", "off", "on_again"]:
		_set_read(phase != "off", WetMaterials.team_night)
		if overlay != null:
			var shown := phase in ["on", "on_again"]
			overlay.set_process(shown)
			if not shown: overlay.hide()
		results[phase] = await measure(seconds)
		extra["perf_" + phase] = results[phase]
	note("mean ms on %.2f / no overlay %.2f / off %.2f / on %.2f" % [float(results.on.mean_ms), float(results.no_overlay.mean_ms), float(results.off.mean_ms), float(results.on_again.mean_ms)])
