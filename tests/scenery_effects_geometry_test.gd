extends SceneTree
const EFFECTS := preload("res://scripts/scenery_prop_effects.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	var effects := EFFECTS.new()
	for width in [2.8, 3.6, 5.0, 7.0, 10.0, 13.0]:
		for height in [6.0, 9.0, 13.0, 20.0, 31.0, 42.0]:
			for lean in [-9.0, -3.0, 0.0, 4.0, 11.0]:
				for variant in 3:
					for offset in [Vector2.ZERO, Vector2(.2, .8), Vector2(-.49, .49)]:
						var shape := effects._flame_polygon(Vector2(50, 100) + offset, width, height, lean, variant)
						checks += 1
						if shape.size() < 3 or Geometry2D.triangulate_polygon(shape).is_empty():
							failures += 1
						for point: Vector2 in shape:
							if not point.is_equal_approx(point.round()) or point.y > roundf(100 + offset.y):
								failures += 1
	effects.free()
	print("SCENERY EFFECT GEOMETRY: %d shapes, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
