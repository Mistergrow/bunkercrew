extends SceneTree
## Bounds/preferences on the real menu. Authored audible-marker integration and
## rendered kick/rest captures are verified by menu_rave_gameplay_test.gd separately.
const Menu := preload("res://scripts/main_menu_panel.gd")
const Cleanup := preload("res://tests/scene_cleanup.gd")
var game
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func frames(count: int = 3) -> void:
	for frame in count: await process_frame

func _assert_rest(pose: Dictionary, label: String) -> void:
	check(float(pose.scale) == 1.0 and float(pose.pulse) == 0.0 and pose.tint == UiArt.IVORY and float(pose.get("vertical_offset", 0.0)) == 0.0 and float(pose.get("horizontal_offset", 0.0)) == 0.0, label)

func _run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args() or "--no-upnp" not in OS.get_cmdline_user_args():
		push_error("Run with --no-profile-save --no-upnp to preserve player settings and avoid hosting")
		quit(2)
		return
	root.size = Vector2i(1440, 900)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await frames(8)
	var menu = game.hud.main_menu_panel
	check(is_instance_valid(menu) and is_instance_valid(menu.wordmark), "The real paused menu has a dedicated beat wordmark")
	menu.set_process(false)
	var buttons: Dictionary = {}
	for button: Button in menu._ordered_buttons(): buttons[button.get_instance_id()] = {"rect":button.get_rect(), "transform":button.get_transform()}
	var preview_transform: Transform2D = menu.preview.get_transform()
	var decoration_transform: Transform2D = menu.decoration.get_transform()
	var original_center := Menu.WORDMARK_RECT.get_center()
	var resting_pose := Menu.pose_for_menu_rhythm({}, false)
	_assert_rest(resting_pose, "An absent audio frame preserves the original title")
	_assert_rest(Menu.pose_for_menu_rhythm({"active":false, "kick_pulse":1.0}, false), "Inactive audio cannot leave a cosmetic beat behind")
	for invalid: Variant in [NAN, INF, -INF, "invalid", {}, []]:
		_assert_rest(Menu.pose_for_menu_rhythm({"active":true, "kick_pulse":invalid}, false), "A nonnumeric/nonfinite pulse cannot transform the menu")
	_assert_rest(Menu.pose_for_menu_rhythm({"active":true, "kick_pulse":-1.0}, false), "Negative pulse strength is bounded at rest")
	var peak: Dictionary = Menu.pose_for_menu_rhythm({"active":true, "kick_pulse":99.0, "phase":0.0}, false)
	check(float(peak.scale) == Menu.WORDMARK_MAX_SCALE and float(peak.pulse) == 1.0, "Oversized impulses are bounded by the restrained maximum size")
	for strength in [0.0, 0.05, 0.25, 0.5, 0.75, 1.0]:
		var pose: Dictionary = Menu.pose_for_menu_rhythm({"active":true, "kick_pulse":strength, "phase":strength}, false)
		menu._apply_wordmark_pose(pose)
		var current: Dictionary = menu.wordmark_state()
		check(absf(current.center.x - original_center.x) <= Menu.WORDMARK_SWAY_DISTANCE + 0.001 and is_equal_approx(current.center.y, original_center.y), "Every heard beat phase bounds horizontal sway and preserves the vertical center")
		check(float(current.scale) >= 1.0 and float(current.scale) <= Menu.WORDMARK_MAX_SCALE and current.rect.position.y > 128 and current.rect.end.y < 198, "The entire pulse stays inside the original title clearance")
		for button: Button in menu._ordered_buttons():
			var before: Dictionary = buttons[button.get_instance_id()]
			check(button.get_rect() == before.rect and button.get_transform() == before.transform and not current.rect.intersects(button.get_rect()), "Beat response never moves, scales or overlaps an action hit target")
	check(menu.preview.get_transform() == preview_transform and menu.decoration.get_transform() == decoration_transform, "Only the wordmark transforms; scenery and foreground retain their original transforms")
	for beat_phase in [0.0, 0.125, 0.25, 0.5, 0.75, 0.999]:
		menu._apply_wordmark_pose(Menu.pose_for_menu_rhythm({"active":true, "kick_pulse":1.0, "secondary_pulse":1.0, "phase":beat_phase}, false))
		var sway: Dictionary = menu.wordmark_state()
		check(absf(sway.horizontal_offset) <= Menu.WORDMARK_SWAY_DISTANCE and sway.vertical_offset == 0.0, "Audible beat phase moves the title inside its small horizontal range")
		check(absf(sway.center.x - original_center.x - sway.horizontal_offset) < 0.001 and is_equal_approx(sway.center.y, original_center.y), "The actual wordmark transform follows horizontal sway without shifting vertically")
		check(sway.rect.position.y > 128.0 and sway.rect.end.y < 198.0, "Combined scaling and sway remain between the original tagline and subtitle")
	var opposite: Dictionary = Menu.pose_for_menu_rhythm({"active":true, "phase":0.5}, false)
	check(peak.horizontal_offset == -Menu.WORDMARK_SWAY_DISTANCE and opposite.horizontal_offset == Menu.WORDMARK_SWAY_DISTANCE, "The title swings from left to right between downbeat and offbeat")
	for invalid_phase: Variant in [NAN, INF, -INF, "invalid", {}, []]:
		_assert_rest(Menu.pose_for_menu_rhythm({"active":true, "phase":invalid_phase}, false), "Invalid audible phase never moves the title")
	_assert_rest(Menu.pose_for_menu_rhythm({"active":false, "kick_pulse":1.0, "secondary_pulse":1.0}, false), "Muted or inactive instruments cannot leave the title moving")
	menu._apply_wordmark_pose(Menu.pose_for_menu_rhythm({"active":true, "kick_pulse":1.0, "secondary_pulse":1.0, "phase":0.5}, true))
	check(menu.wordmark.scale == Vector2.ONE and menu.wordmark.position == Menu.WORDMARK_RECT.position and float(menu.wordmark_state().redraw_hz) == 12.0, "Reduced effects preserve title size and position and lower its presentation cadence")
	var reduced_tint: Color = menu.wordmark_state().tint
	check(reduced_tint.r - UiArt.IVORY.r < 0.004 and reduced_tint.g - UiArt.IVORY.g < 0.004 and reduced_tint.b - UiArt.IVORY.b < 0.004, "Reduced motion uses a tiny ivory lift instead of an amber accent")
	# Verify the real preference path, not only the pure color/size helper.
	game.audio.set_rhythm_motion_reduced(true)
	menu._tick_wordmark(1.0 / 60.0, false)
	check(menu.wordmark.scale == Vector2.ONE and bool(menu.wordmark_state().reduced), "The player's audio reduced-motion setting reaches the actual menu")
	game.audio.set_rhythm_motion_reduced(false)
	menu._tick_wordmark(1.0 / 60.0, true)
	check(menu.wordmark.scale == Vector2.ONE and bool(menu.wordmark_state().reduced), "F3 weather reduction also reaches the menu title")
	game.audio.set_music_volume(0.0)
	await frames(2)
	menu._tick_wordmark(0.0, false)
	var muted: Dictionary = menu.wordmark_state()
	_assert_rest(muted, "Muting music restores the exact original title without waiting for a redraw interval")
	check(menu.wordmark.modulate == Color.WHITE and menu.wordmark.position == Menu.WORDMARK_RECT.position, "The resting title retains its original ivory modulation and coordinates")
	for dimensions: Vector2i in [Vector2i(960,600), Vector2i(1920,1080), Vector2i(2560,1440)]:
		root.size = dimensions
		await frames(3)
		game.hud._layout_viewport()
		menu._layout_scenery()
		menu._apply_wordmark_pose(peak)
		var global_rect: Rect2 = menu.wordmark.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, menu.wordmark.size)
		check(root.get_visible_rect().encloses(global_rect), "At %s the complete wordmark pulse stays inside the viewport" % dimensions)
	check(not game.started and paused and not game.network.active, "Menu pulsing never starts gameplay or a room")
	paused = false
	check(await Cleanup.free_scene(game, self), "Menu/title/audio teardown releases cleanly")
	print("MENU RAVE LOGO: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures > 0 else 0)
