extends SceneTree
## Flame geometry of burning scenery: every flipbook quad is finite, stands on
## the burning wood (its lower edge on the base, never below it) and reaches
## its tip at the requested height and lean.
const PixelArt := preload("res://scripts/pixel_effect_art.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	for width in [2.8, 3.6, 5.0, 7.0, 10.0, 13.0]:
		for height in [6.0, 9.0, 13.0, 20.0, 31.0, 42.0]:
			for lean in [-9.0, -3.0, 0.0, 4.0, 11.0]:
				for offset in [Vector2.ZERO, Vector2(.2, .8), Vector2(-.49, .49)]:
					var base: Vector2 = Vector2(50, 100) + offset
					var quad: Transform2D = PixelArt.flame_quad(base, width, height, lean)
					checks += 1
					var center: Vector2 = quad.origin
					var bottom: Array[Vector2] = [center + quad.x + quad.y, center - quad.x + quad.y]
					var tip: Vector2 = center - quad.y
					var ok := center.is_finite() and quad.x.is_finite() and quad.y.is_finite()
					ok = ok and is_equal_approx(bottom[0].y, base.y) and is_equal_approx(bottom[1].y, base.y)
					ok = ok and tip.is_equal_approx(base + Vector2(lean, -height))
					ok = ok and is_equal_approx(absf(bottom[0].x - bottom[1].x), width)
					if not ok: failures += 1
	# Frames loop through the 32-frame flipbook and phases never coincide.
	checks += 1
	if PixelArt.flame_frame(1.0, 0) == PixelArt.flame_frame(1.0, 1) or PixelArt.flame_frame(0.0, 0) != 0 or PixelArt.flame_frame(1.0 / PixelArt.FLAME_FPS, 0) != 1:
		failures += 1
	print("SCENERY EFFECT GEOMETRY: %d shapes, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
