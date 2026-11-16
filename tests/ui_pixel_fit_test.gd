extends SceneTree
## UiArt.pixel_fit / pixel_rect / glyph: pixel art in menus lands on a whole
## number of real pixels per texel at the 1.2 design stretch of 1080p, on the
## real pixel grid; below one real pixel per texel the exact fit is kept.
var checks := 0
var failures := 0

func _initialize() -> void: run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1
	print("UI PIXEL FIT %s: %s" % ["PASS" if value else "FAIL", label])

func run() -> void:
	root.size = Vector2i(1440, 900)
	var layer := CanvasLayer.new()
	root.add_child(layer)
	var canvas := Control.new()
	layer.add_child(canvas)
	var node := Control.new()
	canvas.add_child(node)
	await process_frame
	var base := UiArt.output_scale(node)
	# The canvas carries the stretch the window would add at 1920x1080 (1.2)
	# on top of whatever the test window itself uses.
	canvas.scale = Vector2.ONE * (1.2 / base)
	canvas.position = Vector2(80.3, 0)
	await process_frame
	var pixels := UiArt.output_scale(node)
	check(is_equal_approx(pixels, 1.2), "The node draws at 1.2 real pixels per design pixel")
	var bust := UiArt.pixel_fit(node, Vector2(80, 80), Vector2(270, 270))
	check(is_equal_approx(bust * pixels, 4.0), "An 80 px bust in 270 design px lands at 4 real px per texel, not 3.6")
	var sprite := UiArt.pixel_fit(node, Vector2(77, 77), Vector2(154, 154))
	check(is_equal_approx(sprite * pixels, 2.0), "A 77 px figure in 154 design px lands at 2 real px per texel, not 2.4")
	var picture := UiArt.pixel_fit(node, Vector2(50, 50), Vector2(200, 200))
	check(is_equal_approx(picture * pixels, 4.0), "A 50 px plan in 200 design px lands at 4 real px per texel, not 4.8")
	var small := UiArt.pixel_fit(node, Vector2(77, 77), Vector2(35, 35))
	check(is_equal_approx(small, 35.0 / 77.0), "Below one real pixel per texel the exact fit is kept")
	var rect := UiArt.pixel_rect(node, Vector2(80, 80), Rect2(940.4, 182.0, 270, 270))
	var screen := node.get_viewport().get_final_transform() * node.get_global_transform_with_canvas()
	var corner := screen * rect.position
	var far := screen * rect.end
	check(corner.is_equal_approx(corner.round()) and far.is_equal_approx(far.round()), "The drawn rectangle starts and ends on real pixel edges")
	check(absf(rect.end.y - 452.0) <= 1.0 / pixels and absf(rect.get_center().x - 1075.4) <= 1.0 / pixels, "It stands on the room's floor, centred across (within the one real pixel the snap may move it)")
	check(is_equal_approx((far - corner).x, 320.0), "Its real width is 4 x 80 px")
	var centred := UiArt.pixel_rect(node, Vector2(50, 50), Rect2(0, 0, 214, 214), true)
	check(absf(centred.get_center().y - 107.0) <= 1.0, "A centred picture keeps its vertical middle")
	layer.queue_free()
	await process_frame
	print("UI PIXEL FIT: %d/%d checks passed" % [checks - failures, checks])
	quit(1 if failures else 0)
