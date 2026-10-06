extends SceneTree
## Authored surface bounds, safe reflection sampling, static camera anchoring,
## and caller-controlled pause/reduced-effects time for the wide water field.

const Water := preload("res://scripts/distant_water.gd")
class SceneryFixture extends Node2D:
	var environment_id := "sector07"
	var data: Dictionary = {}
	var panorama_rect := Rect2(-144, -64, 1728, 576)
	var panorama := Sprite2D.new()
	func _init() -> void:
		add_child(panorama)
	func _edge_color(_y: float, side: int) -> Color:
		return Color("234852") if side == 0 else Color("34635c")

var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	print("DISTANT WATER %s: %s" % ["PASS" if value else "FAIL", label])
	if not value:
		failures += 1
		push_error(label)

func _run() -> void:
	var scenery := SceneryFixture.new()
	root.add_child(scenery)
	var water := Water.new()
	scenery.add_child(water)
	var water_worlds := 0
	var wide := Rect2(-2480, -1340, 6400, 3600)
	for entry: Dictionary in ScenarioCatalog.environments():
		scenery.environment_id = str(entry.id)
		scenery.data = entry
		scenery.panorama.texture = ScenarioCatalog.texture(str(entry.path))
		water.configure(scenery)
		water.update_view(wide, 0.0)
		var regions: Array = entry.get("water_regions", [])
		if regions.is_empty():
			check(not water.enabled and not water.visible and water.water_material == null, "%s creates no active water surface or shader" % entry.id)
			continue
		water_worlds += 1
		var expected_top := -64.0 + float(regions[0][1]) * 576.0
		check(water.enabled and water.visible and is_equal_approx(water.water_top, expected_top), "%s joins the exact authored shoreline" % entry.id)
		check(water.bounds.encloses(Rect2(wide.position.x, expected_top, wide.size.x, 430.0 - expected_top)), "%s covers the maximum supported overview width" % entry.id)
		check(is_equal_approx(water.bounds.end.y, 430.0) and is_equal_approx(water.bounds.position.y, expected_top), "%s draws only between waterline and ground" % entry.id)
		var shader := water.water_material
		var source: Vector2 = shader.get_shader_parameter("source_water")
		check(is_equal_approx(source.x, float(regions[0][1])) and source.y <= float(regions[0][1]) + float(regions[0][3]), "%s reflection sampling remains inside the declared water region" % entry.id)
		check(shader.get_shader_parameter("panorama_water") == scenery.panorama.texture, "%s reuses the painted water texture" % entry.id)
		check(shader.get_shader_parameter("top_left") == scenery._edge_color(expected_top + 12.0, 0), "%s retains sampled shore color" % entry.id)
		water.update_view(wide, 5.0)
		check(is_equal_approx(shader.get_shader_parameter("water_clock"), 5.0), "%s moves only with caller-supplied scene time" % entry.id)
		var original_bounds: Rect2 = water.bounds
		water.update_view(Rect2(wide.position + Vector2(5, 0), wide.size), 5.0)
		check(is_equal_approx(shader.get_shader_parameter("water_clock"), 5.0) and water.bounds == original_bounds, "%s paused camera adjustment keeps time and cached quad stable" % entry.id)
		water.update_view(wide, 5.0, true)
		check(is_equal_approx(shader.get_shader_parameter("motion_strength"), 0.25), "%s reduced effects lowers ripple strength" % entry.id)
		water.update_view(wide, 6.0, false)
		check(is_equal_approx(shader.get_shader_parameter("motion_strength"), 1.0), "%s normal effects restores ripple strength" % entry.id)
		water.update_view(Rect2(-800, 440, 3000, 900), 6.0)
		check(not water.visible, "%s underground camera submits no water" % entry.id)
		water.update_view(Rect2(-800, -900, 3000, 700), 6.0)
		check(not water.visible, "%s upper-sky camera submits no water" % entry.id)
	check(water_worlds == 2, "Only harbor and power station have distant water")
	await preload("res://tests/scene_cleanup.gd").free_scene(scenery, self)
	print("DISTANT WATER: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
