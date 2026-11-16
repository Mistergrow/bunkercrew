extends SceneTree
## Visual-review instrument: renders a fixed, seeded shot list of the real game
## (actual main scene, real window stretch path) so the same shots can be
## rendered again after every presentation pass and compared like for like.
##
## Do not start this script by hand; tools/visual_review.py lists the shots,
## batches them into bounded processes and writes index.json / index.html.
##   --list=<file>            write the catalog-derived shot list and quit
##   --shots=<file>           JSON array of shot specs to render in this process
##   --out=<absolute folder>  destination for images and results.jsonl
## Every game state is staged through the paths the project galleries use:
## start_scenario with catalog options, game._entity, round and HUD calls and
## real input actions. Nothing is written to the profile (--no-profile-save).
const Cleanup := preload("res://tests/scene_cleanup.gd")
const ShotList := preload("res://tests/visual_review_shots.gd")
const STAGES := {
	"ui": preload("res://tests/visual_review_stage_ui.gd"),
	"world": preload("res://tests/visual_review_stage_world.gd"),
	"action": preload("res://tests/visual_review_stage_action.gd"),
}
const SHOT_WALL_SECONDS := 150.0
const PARK := Vector2(8, 8)

## Time stamps at the very start or end of the frame's process and physics
## passes (lowest / highest priority in the whole tree), so measure() can split
## a slow frame into physics, every _process callback, and drawing/rendering.
class FrameStamp extends Node:
	var stamps := {}
	var tag := ""
	func _process(_delta: float) -> void: stamps[tag + "process"] = Time.get_ticks_usec()
	func _physics_process(_delta: float) -> void:
		if not stamps.has(tag + "physics_first"): stamps[tag + "physics_first"] = Time.get_ticks_usec()
		stamps[tag + "physics"] = Time.get_ticks_usec()

var game
var out_dir := ""
var spec: Dictionary = {}
var notes: Array[String] = []
var failure := ""
var files: Array[String] = []
var times: Array[float] = []
var extra: Dictionary = {}
var _sequence_start := -1
var _held: Dictionary = {}
var _aim_world: Variant = null
## Optional pointer target re-read every simulated frame (a player tracking a
## moving machine with the mouse); returns a world Vector2 or null.
var _aim_source := Callable()
## Optional staging step run before every simulated frame (a player's trigger
## finger reacting to the world).
var _frame_hook := Callable()
var _shot_done := false
var _results: FileAccess
var _motion_clock: Variant = null
var _track: Node2D = null
var _track_offset := Vector2.ZERO
var _track_zoom := 4.0

func _tick() -> void:
	if _motion_clock != null: _motion_clock.call("set_manual_clock", float(Engine.get_process_frames()) / 60.0)

func _initialize() -> void:
	_main.call_deferred()

func _argument(prefix: String) -> String:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with(prefix): return argument.trim_prefix(prefix)
	return ""

# ---------------------------------------------------------------- primitives
func frames(count: int = 1) -> void:
	for index in count:
		if _frame_hook.is_valid(): _frame_hook.call()
		if _aim_source.is_valid():
			var target: Variant = _aim_source.call()
			if target is Vector2: _aim_world = target
		if _aim_world != null: _warp()
		if _track != null:
			if is_instance_valid(_track): _place_camera(_track.global_position + _track_offset, _track_zoom)
			else: _track = null
		await process_frame

func note(text: String) -> void:
	notes.append(text)
	print("VR NOTE ", text)

func fail(text: String) -> void:
	if failure.is_empty(): failure = text
	print("VR FAIL ", text)

func failed() -> bool:
	return not failure.is_empty()

## True when the object offers the member; otherwise the shot fails with a
## message naming the missing staging path instead of a script error.
func need(object: Variant, member: String) -> bool:
	if object == null or (object is Object and not is_instance_valid(object)):
		fail("staging object for '%s' is missing" % member)
		return false
	if object.has_method(member) or member in object: return true
	fail("staging path missing in this build: %s.%s" % [object.get_script().resource_path.get_file() if object.get_script() != null else object.get_class(), member])
	return false

func _quiet_persistence() -> void:
	for system: String in ["audio", "combat_events", "campaign"]:
		var node = game.get(system)
		if is_instance_valid(node) and "persistence_enabled" in node: node.persistence_enabled = false

## Fresh main scene in its menu state.
func menu() -> void:
	await _close()
	seed(int(spec.get("seed", 1)))
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	_quiet_persistence()
	await frames(12)

## Fresh main scene with a running scenario. Options: position, build_type,
## hud (default true), hold_rounds (default true), quiet (default true:
## initial radio line and notice cleared), characters.
func play(count: int, environment: String, options: Dictionary = {}) -> void:
	await menu()
	if options.has("characters"): game.selected_characters.assign(options.characters)
	game.start_scenario(count, {"environment": environment, "build_type": str(options.get("build_type", "bastion")), "position": str(options.get("position", "left"))})
	if not game.started:
		fail("start_scenario did not start a match for " + environment)
		return
	# Game code draws from the global generator and from a few fixed-seed
	# generators; reseeding after the world exists keeps both reproducible.
	seed(int(spec.get("seed", 1)) + 17)
	if bool(options.get("hold_rounds", true)): game.rounds.running = false
	if bool(options.get("quiet", true)):
		if is_instance_valid(game.dialogue) and game.dialogue.has_method("reset"): game.dialogue.reset()
		game.notice_time = 0
		if is_instance_valid(game.solo_tutorial) and game.solo_tutorial.has_method("set_enabled") and not bool(options.get("tutorial", false)): game.solo_tutorial.set_enabled(false)
	game.hud.visible = bool(options.get("hud", true))
	await frames(int(options.get("settle", 45)))

func _close() -> void:
	release_all()
	_aim_world = null
	_aim_source = Callable()
	_frame_hook = Callable()
	_track = null
	if not is_instance_valid(game): return
	if is_instance_valid(game.network) and game.network.active: game.network.leave()
	paused = false
	await Cleanup.free_scene(game, self)
	game = null
	for stray in root.get_children():
		if stray is Window or stray == game: continue
		if stray.name == "NetworkSession" or stray.name in ["Localization", "ProfileMigration", "SocialHub"]: continue
		if stray.get_script() == get_script(): continue
	await process_frame

# input ------------------------------------------------------------------
func hold(action: String) -> void:
	if not InputMap.has_action(action):
		fail("input action missing: " + action)
		return
	Input.action_press(action)
	_held[action] = true

func release(action: String) -> void:
	if InputMap.has_action(action): Input.action_release(action)
	_held.erase(action)

func release_all() -> void:
	for action: String in _held.keys(): release(action)

## One real action event through the input pipeline (menus and HUD listen to it).
func press(action: String) -> void:
	if not InputMap.has_action(action):
		fail("input action missing: " + action)
		return
	for pressed: bool in [true, false]:
		var event := InputEventAction.new()
		event.action = action
		event.pressed = pressed
		Input.parse_input_event(event)
		await process_frame
	await process_frame

## Player one aims with the pointer. The pointer lives on the isolated display.
func aim(world: Variant) -> void:
	_aim_world = world
	if world != null: _warp()

func _warp() -> void:
	if not is_instance_valid(game) or not (_aim_world is Vector2): return
	root.warp_mouse(game.get_viewport().get_canvas_transform() * (_aim_world as Vector2))

func park_pointer() -> void:
	_aim_world = null
	_aim_source = Callable()
	root.warp_mouse(PARK)

func each_frame(hook: Callable) -> void:
	_frame_hook = hook

## Player one keeps the pointer on whatever `source` returns each frame.
func aim_follow(source: Callable) -> void:
	_aim_source = source
	_warp()

# camera -----------------------------------------------------------------
## The game's own overview framing for the current view stage.
func camera_overview() -> void:
	game.player_camera.set_process(true)
	game.set_camera_mode("overview")
	game.player_camera.update_view(0.0, true)

## The game's own follow camera at the given zoom (clamped by the game).
func camera_follow(zoom: float) -> void:
	game.player_camera.set_process(true)
	game.set_camera_mode("follow")
	game.set_camera_zoom(zoom)
	game.player_camera.update_view(0.0, true)

## Exactly what a player sees: the game's own camera with a fresh profile's
## settings (follow mode at the default zoom; couch co-op fits every local
## worker), settled once and then left to follow on its own.
func camera_game() -> void:
	_track = null
	game.player_camera.set_process(true)
	game.player_camera.reset_view()
	game.player_camera.update_view(0.0, true)

## World rectangle the camera currently shows.
func view_rect() -> Rect2:
	var view: Vector2 = root.get_visible_rect().size / game.camera.zoom
	return Rect2(game.camera.get_screen_center_position() - view * 0.5, view)

## Authored close-up; the follow logic is held, the world keeps running.
func camera_at(center: Vector2, zoom: float) -> void:
	_track = null
	_place_camera(center, zoom)

## Builds with a whole-pixel world grid (scripts/pixel_grid.gd) present authored
## framings the way the game's own camera does: a whole number of physical
## pixels per world unit (nearest step; a fit never grows past its area) and a
## centre on whole pixels. Older checkouts keep the exact authored zoom.
func _grid() -> Variant:
	return load("res://scripts/pixel_grid.gd") if ResourceLoader.exists("res://scripts/pixel_grid.gd") else null

func _grid_zoom(zoom: float, fit: bool = false) -> Vector2:
	# Never closer than a player can zoom: close-ups authored at 4-5 px per world
	# unit showed the art larger than the game ever does.
	zoom = minf(zoom, _max_zoom())
	var grid: Variant = _grid()
	if grid == null: return Vector2.ONE * zoom
	var factor: Vector2 = grid.stretch(root)
	var unit := minf(factor.x, factor.y)
	var scale: float = grid.fit_scale(zoom * unit) if fit else grid.nearest_scale(zoom * unit)
	return grid.zoom_for(scale, root)

func _max_zoom() -> float:
	var camera: Variant = load("res://scripts/player_camera.gd") if ResourceLoader.exists("res://scripts/player_camera.gd") else null
	return float(camera.get_script_constant_map().get("MAX_ZOOM", INF)) if camera is Script else INF

func _place_camera(center: Vector2, zoom: float) -> void:
	game.player_camera.set_process(false)
	var zoom_vector := _grid_zoom(zoom)
	var grid: Variant = _grid()
	game.camera.position = grid.snap_center(center, zoom_vector, root) if grid != null else center
	game.camera.zoom = zoom_vector
	if game.camera.has_method("reset_smoothing"): game.camera.reset_smoothing()
	game.camera.force_update_scroll()

## Close camera that follows one actor every simulated frame.
func track(actor: Node2D, offset: Vector2, zoom: float) -> void:
	_track = actor
	_track_offset = offset
	_track_zoom = zoom
	_place_camera(actor.global_position + offset, zoom)

## Largest zoom that keeps a world rectangle inside the logical viewport.
## With anchor_bottom the area's lower edge sits near the bottom of the frame
## (spare height goes to the sky, not underground).
func camera_fit(area: Rect2, margin: float = 40.0, limit: float = 4.0, anchor_bottom: bool = false) -> void:
	var view: Vector2 = root.get_visible_rect().size
	var authored := clampf(snappedf(minf(view.x / (area.size.x + margin * 2.0), view.y / (area.size.y + margin * 2.0)), 0.05), 0.3, limit)
	# Nearest whole step while the area itself (not its margin) stays inside.
	var zoom := _grid_zoom(authored, true).y
	var nearer := _grid_zoom(authored).y
	if nearer > zoom and nearer <= minf(view.x / area.size.x, view.y / area.size.y): zoom = nearer
	var center := area.get_center()
	# A whole-pixel fit that shows more than the authored framing keeps its
	# lower edge and gives the extra height to the sky, not to the rock below.
	if zoom < authored: center.y += view.y * 0.5 / authored - view.y * 0.5 / zoom
	if anchor_bottom: center.y = area.end.y + margin - view.y / zoom * 0.5
	camera_at(center, zoom)

func spawn(scene: String, at: Vector2, properties: Dictionary = {}):
	if not ResourceLoader.exists("res://scenes/%s.tscn" % scene):
		fail("scene missing: " + scene)
		return null
	return game._entity(scene, at, properties)

# capture ----------------------------------------------------------------
func _grab(path: String) -> bool:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image == null or image.is_empty():
		fail("viewport returned no image")
		return false
	var wanted := Vector2i(int(spec.size[0]), int(spec.size[1]))
	if image.get_size() != wanted: note("rendered %dx%d instead of %dx%d" % [image.get_width(), image.get_height(), wanted.x, wanted.y])
	if image.save_png(out_dir + "/" + path) != OK:
		fail("could not write " + path)
		return false
	return true

func still() -> void:
	if failed(): return
	var path := str(spec.id) + ".png"
	if await _grab(path): files.append(path)

## One sequence frame; the timestamp is simulated seconds since the first frame.
func sequence_frame() -> void:
	if failed(): return
	if _sequence_start < 0:
		_sequence_start = Engine.get_process_frames()
		DirAccess.make_dir_recursive_absolute(out_dir + "/" + str(spec.id))
	var stamp := float(Engine.get_process_frames() - _sequence_start) / 60.0
	var path := "%s/f%02d.png" % [str(spec.id), files.size()]
	if await _grab(path):
		files.append(path)
		times.append(snappedf(stamp, 0.001))

## count frames, step simulated frames apart. The callable runs before each
## frame with its index, e.g. to trigger an event partway through.
func sequence(count: int, step: int, before: Callable = Callable()) -> void:
	for index in count:
		if failed(): return
		if before.is_valid(): await before.call(index)
		await sequence_frame()
		if index < count - 1: await frames(step)

## Wall-clock frame times of the current scene. Each frame still simulates
## exactly 1/60 s (--fixed-fps), so every run measures the same workload.
func measure(seconds: float) -> Dictionary:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	for warm in 30: await RenderingServer.frame_post_draw
	var viewport_rid := root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(viewport_rid, true)
	var samples: Array[float] = []
	var details: Array[Dictionary] = []
	var draw_calls := 0
	# Node types that first appear during the probe, keyed to the frame they appear
	# in: a hitch next to a new wreck, pickup or light names its own suspect.
	var seen := {}
	var appeared: Array[String] = []
	var watch := func(node: Node) -> void:
		var key := node.get_class() + (":" + str(node.get_script().resource_path).get_file() if node.get_script() else "")
		if not seen.has(key):
			seen[key] = true
			appeared.append(key)
	node_added.connect(watch)
	# The same for node types leaving the tree for the first time: freeing a light,
	# texture or material can cost as much as creating one.
	var left := {}
	var departed: Array[String] = []
	var watch_exit := func(node: Node) -> void:
		var key := node.get_class() + (":" + str(node.get_script().resource_path).get_file() if node.get_script() else "")
		if not left.has(key):
			left[key] = true
			departed.append(key)
	node_removed.connect(watch_exit)
	var kills := int(game.stats.get("kills", 0)) if game != null and game.get("stats") is Dictionary else 0
	var memory := Performance.get_monitor(Performance.MEMORY_STATIC)
	var stamps := {}
	var markers: Array[Node] = []
	for tag in ["first_", "last_"]:
		var marker := FrameStamp.new()
		marker.stamps = stamps
		marker.tag = tag
		marker.process_mode = Node.PROCESS_MODE_ALWAYS
		marker.process_priority = -1000000 if tag == "first_" else 1000000
		marker.process_physics_priority = marker.process_priority
		root.add_child(marker)
		markers.append(marker)
	# Deferred calls, including every queued _draw, run between the last _process
	# and frame_pre_draw; the rendering server's sync and draw follow it.
	var pre_draw := func() -> void: stamps["pre_draw"] = Time.get_ticks_usec()
	RenderingServer.frame_pre_draw.connect(pre_draw)
	var previous := Time.get_ticks_usec()
	for index in int(seconds * 60.0):
		stamps.clear()
		await frames(1)
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		var physics_ms := float(int(stamps.get("last_physics", 0)) - int(stamps.get("first_physics_first", 0))) / 1000.0 if stamps.has("last_physics") and stamps.has("first_physics_first") else 0.0
		var process_ms := float(int(stamps.get("last_process", 0)) - int(stamps.get("first_process", 0))) / 1000.0 if stamps.has("last_process") and stamps.has("first_process") else 0.0
		var stepped := int(stamps.get("last_process", now))
		var drawn := int(stamps.get("pre_draw", stepped))
		var killed := int(game.stats.get("kills", 0)) if game != null and game.get("stats") is Dictionary else kills
		var memory_now := Performance.get_monitor(Performance.MEMORY_STATIC)
		samples.append(float(now - previous) / 1000.0)
		# The rendering timers lag a frame or two behind; they still separate a
		# script or loading stall (process high, render low) from a renderer one.
		details.append({"physics_ms": physics_ms, "process_ms": process_ms, "deferred_draw_ms": float(drawn - stepped) / 1000.0, "server_ms": float(now - drawn) / 1000.0, "render_cpu_ms": RenderingServer.viewport_get_measured_render_time_cpu(viewport_rid),
			"render_gpu_ms": RenderingServer.viewport_get_measured_render_time_gpu(viewport_rid), "memory_kb": (memory_now - memory) / 1024.0, "kills": killed - kills, "new": appeared.duplicate(), "gone": departed.duplicate(),
			"phase": str(game.rounds.get("phase")) if game != null and is_instance_valid(game.get("rounds")) else ""})
		appeared.clear()
		departed.clear()
		kills = killed
		memory = memory_now
		previous = now
		draw_calls = maxi(draw_calls, int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)))
	node_added.disconnect(watch)
	node_removed.disconnect(watch_exit)
	for marker in markers: marker.queue_free()
	RenderingServer.frame_pre_draw.disconnect(pre_draw)
	RenderingServer.viewport_set_measure_render_time(viewport_rid, false)
	var sorted := samples.duplicate()
	sorted.sort()
	var total := 0.0
	for sample in samples: total += sample
	var median: float = sorted[sorted.size() / 2]
	# Frames far above the median, with what happened in them, so a one-time hitch
	# (a first shader, a first effect) can be told apart from steady cost.
	var spikes: Array = []
	for index in samples.size():
		if samples[index] > maxf(50.0, median * 3.0) and spikes.size() < 24:
			var row: Dictionary = details[index]
			spikes.append({"frame": index, "ms": snappedf(samples[index], 0.1), "physics_ms": snappedf(row.physics_ms, 0.1), "process_ms": snappedf(row.process_ms, 0.1), "deferred_draw_ms": snappedf(row.deferred_draw_ms, 0.1), "server_ms": snappedf(row.server_ms, 0.1),
				"render_cpu_ms": snappedf(row.render_cpu_ms, 0.1), "render_gpu_ms": snappedf(row.render_gpu_ms, 0.1), "memory_kb": snappedf(row.memory_kb, 1.0), "new": row.new, "gone": row.gone,
				"phase": row.phase if index == 0 or details[index - 1].phase == row.phase else "%s -> %s" % [details[index - 1].phase, row.phase]})
	# Kill frames: a defeat shows its wreck and effects from the next frame on, so
	# each kill counts the slower of its frame and the one after it.
	var kill_costs: Array[float] = []
	for index in samples.size():
		if int(details[index].kills) > 0: kill_costs.append(maxf(samples[index], samples[mini(index + 1, samples.size() - 1)]))
	var kill_report := {"count": kill_costs.size(), "costs_ms": kill_costs.map(func(cost: float) -> float: return snappedf(cost, 0.1))}
	if not kill_costs.is_empty():
		var repeats := kill_costs.slice(1)
		repeats.sort()
		kill_report.merge({"first_kill_ms": snappedf(kill_costs[0], 0.1), "repeat_median_ms": snappedf(repeats[repeats.size() / 2], 0.1) if not repeats.is_empty() else null,
			"repeat_max_ms": snappedf(repeats[-1], 0.1) if not repeats.is_empty() else null})
	return {"frames": samples.size(), "simulated_seconds": seconds, "mean_ms": snappedf(total / samples.size(), 0.001), "p50_ms": snappedf(median, 0.001),
		"p95_ms": snappedf(sorted[mini(sorted.size() - 1, ceili(sorted.size() * 0.95) - 1)], 0.001),
		"p99_ms": snappedf(sorted[mini(sorted.size() - 1, ceili(sorted.size() * 0.99) - 1)], 0.001), "max_ms": snappedf(sorted[-1], 0.001), "peak_draw_calls": draw_calls,
		"spikes": spikes, "kills": kill_report}

# ------------------------------------------------------------------ driver
func _write(row: Dictionary) -> void:
	_results.store_line(JSON.stringify(row))
	_results.flush()

func _run_shot() -> void:
	var stage: Variant = STAGES.get(str(spec.stage))
	if stage == null or not stage.has_method(str(spec.method)):
		fail("unknown stage %s.%s" % [spec.stage, spec.method])
	else:
		await stage.call(str(spec.method), self, spec)
	_shot_done = true

func _main() -> void:
	var arguments := OS.get_cmdline_user_args()
	if "--no-profile-save" not in arguments or "--no-upnp" not in arguments:
		push_error("visual review requires --no-profile-save --no-upnp")
		quit(2)
		return
	var list_path := _argument("--list=")
	var options := {"size": _argument("--size="), "locale": _argument("--locale=")}
	if not list_path.is_empty():
		AudioServer.set_bus_mute(0, true)
		var listing: Array = await ShotList.build(self, options)
		var file := FileAccess.open(list_path, FileAccess.WRITE)
		file.store_string(JSON.stringify(listing, "\t"))
		file.close()
		await _close()
		quit(0)
		return
	out_dir = _argument("--out=").trim_suffix("/")
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(_argument("--shots=")))
	if out_dir.is_empty() or not parsed is Array or DisplayServer.get_name() == "headless":
		push_error("visual review needs --out, --shots and a graphical display")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(out_dir)
	_results = FileAccess.open(out_dir + "/" + _argument("--results="), FileAccess.WRITE)
	AudioServer.set_bus_mute(0, true)
	root.mode = Window.MODE_WINDOWED
	process_frame.connect(_tick)
	root.set_flag(Window.FLAG_NO_FOCUS, true)
	var renderer := {"method": RenderingServer.get_current_rendering_method(), "adapter": RenderingServer.get_video_adapter_name(), "driver": OS.get_cmdline_args().has("--rendering-driver")}
	for entry: Dictionary in parsed:
		spec = entry
		notes = []
		failure = ""
		files = []
		times = []
		extra = {}
		_sequence_start = -1
		_shot_done = false
		print("VR BEGIN ", spec.id)
		_write({"event": "begin", "id": spec.id})
		# Movie-writer shots mix into the discarded recording, never to a device.
		AudioServer.set_bus_mute(0, not bool(spec.get("movie", false)))
		root.size = Vector2i(int(spec.size[0]), int(spec.size[1]))
		LocaleText.set_locale(str(spec.locale), false)
		# Builds with interface motion keep it off in script runs unless asked.
		if ResourceLoader.exists("res://scripts/ui_motion.gd"):
			var motion: Variant = load("res://scripts/ui_motion.gd")
			if motion != null and motion.has_method("force"): motion.call("force", bool(spec.get("ui_motion", false)))
			# Interface motion reads a wall clock; step it with the simulation instead.
			_motion_clock = motion if motion != null and motion.has_method("set_manual_clock") and bool(spec.get("ui_motion", false)) else null
			if motion != null and motion.has_method("set_manual_clock") and _motion_clock == null: motion.call("set_manual_clock", -1.0)
		park_pointer()
		await frames(3)
		var started := Time.get_ticks_msec()
		_run_shot()
		var hung := false
		while not _shot_done:
			await process_frame
			if float(Time.get_ticks_msec() - started) / 1000.0 > float(spec.get("wall_seconds", SHOT_WALL_SECONDS)):
				hung = true
				break
		release_all()
		_aim_world = null
		_aim_source = Callable()
		_frame_hook = Callable()
		if hung: fail("shot did not finish within its time limit")
		var expected := int(spec.get("frames", 1))
		if not failed() and bool(spec.get("captures", true)) and files.size() != expected:
			fail("captured %d of %d frames (a staging step stopped early; see the log)" % [files.size(), expected])
		var row := {"event": "end", "id": spec.id, "status": "failed" if failed() else "ok", "reason": failure, "notes": notes, "files": files, "frame_times": times,
			"seconds": snappedf(float(Time.get_ticks_msec() - started) / 1000.0, 0.01), "renderer": renderer, "viewport": [root.size.x, root.size.y],
			"logical": [root.get_visible_rect().size.x, root.get_visible_rect().size.y]}
		row.merge(extra)
		_write(row)
		print("VR END ", spec.id, " ", row.status)
		if hung:
			# A suspended staging coroutine may still resume; never reuse this process.
			_results.close()
			quit(3)
			return
		await _close()
	_results.close()
	quit(0)
