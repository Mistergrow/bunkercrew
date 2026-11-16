extends Node2D
## Atmospheric grade of the painted backdrop. The panoramas are painted at a
## higher detail and contrast than the playable layer, so behind the crew and
## the enemies they compete with them. One translucent veil in the world's own
## sky colour lies over every backdrop layer (panorama, extended landscape,
## clouds, distant water and mist) and under every playable item: it compresses
## the backdrop's value range and saturation toward the air between it and the
## fight, thinnest in the open sky and densest along the horizon band where the
## busy mid-ground sits behind the actors. Along the ground line a low,
## dithered band of ground haze with a ragged upper edge carries the painted
## land into the drawn ground instead of meeting it in a straight seam; ash,
## mist and blowing snow thicken it. Derived from catalog colours and the
## measured backdrop light only, so every environment gets it without a
## per-world row. Presentation only; WorldLighting places it and passes the
## storm grade on to it through `modulate`, like every other backdrop layer,
## and lightning through set_flash(): a glow around the bolt, not a uniform lift.
## The veil's strength follows the world's measured light (strength_for()):
## bright day panoramas, snow above all, carry the same value range and detail
## as the play plane and swallowed machines and aircraft, so they recede
## further; night worlds recede a little more by darkening.
## Share of the sky colour over the open sky above the panorama.
const SKY_ALPHA := .05
## ... at the top edge of the panorama and at its bottom (the ground line).
const TOP_ALPHA := .08
const GROUND_ALPHA := .24
## Densest the veil may get along the ground line, whatever the strength.
const GROUND_ALPHA_MAX := .46
## Far enough past every framing (3440x1440 overview included).
const EXTENT := 20000.0
## Ground haze band: texels above the ground line and its texture period.
const HAZE_HEIGHT := 44
const HAZE_PERIOD := 256
## Densest share of the ground haze per catalog weather.
const HAZE_DENSITY := {"ash":.52, "mist":.46, "snow":.40, "dust":.42, "rain":.34, "storm":.36, "clear":.28}
const LightKeys := preload("res://scripts/backdrop_light_keys.gd")
## Radius of the lightning glow around a bolt, in world texels.
const FLASH_RADIUS := 1100.0
static var _haze_texture: ImageTexture
static var _flash_texture: GradientTexture2D
var haze := Color(.5, .55, .6)
var ground_haze := Color(.5, .55, .6, .3)
var top_y := -253.0
var ground_y := 430.0
## The playable ground line (the bunker's), where the haze band stands.
var ground_line := 430.0
var flash := 0.0
var flash_at := Vector2.ZERO
var glow: Node2D
## Multiplier on the veil's shares (strength_for()).
var veil_strength := 1.0

## The aerial-perspective colour of an environment: its catalog sky key, the
## colour distant forms fade toward in that world's light. A night sky key is
## brighter than the dark land below it, so at night the haze is taken down
## toward the shadows: the backdrop then recedes by losing its highlights
## (lit windows, fires) instead of being lifted toward the lit actors.
## `night` is WorldLighting.night_for() of the same data.
static func haze_for(data: Dictionary, night: float) -> Color:
	var sky := Color(str(data.get("sky_color", "#808890")))
	sky = sky.darkened(.55 * clampf(night, 0.0, 1.0))
	sky.a = 1.0
	return sky

## How strongly a world's backdrop recedes behind the play plane, as a factor
## on the base veil: 1.15 everywhere, bright day skies (measured sky key) add
## up to .8, snow by day .3 more, night .15 (where the haze darkens). About
## 1.2-1.3 for the night and dusk worlds, 1.5-2 by day, 2.25 for the sunlit
## snow of the rail yard (its ground share stops at GROUND_ALPHA_MAX).
static func strength_for(data: Dictionary, night: float) -> float:
	var id := str(data.get("id", ""))
	var sky: Color = LightKeys.KEYS[id].sky if LightKeys.KEYS.has(id) else Color(str(data.get("sky_color", "#808890")))
	var light := sky.r * .299 + sky.g * .587 + sky.b * .114
	var dark := clampf(night, 0.0, 1.0)
	var bright := smoothstep(.34, .68, light) * (1.0 - dark)
	var snow := (1.0 if str(data.get("weather", "")) == "snow" else 0.0) * (1.0 - dark)
	return 1.15 + .8 * bright + .3 * snow + .15 * dark

## Ground haze of a world: its aerial haze leaning toward the measured land
## colour along the ground line (rgb), and its density by weather (a).
static func ground_haze_for(data: Dictionary, night: float) -> Color:
	var air := haze_for(data, night)
	var id := str(data.get("id", ""))
	var land := air
	if LightKeys.KEYS.has(id):
		var measured: Color = LightKeys.KEYS[id].land
		land = measured.lightened(.18 * (1.0 - clampf(night, 0.0, 1.0)))
	var result := air.lerp(land, .45)
	result.a = float(HAZE_DENSITY.get(str(data.get("weather", "")), .26))
	return result

## One period of the haze band: alpha ramps up toward the ground line in four
## dithered steps on whole texels, under an uneven, slowly wandering top edge.
static func haze_texture() -> ImageTexture:
	if _haze_texture == null:
		var bayer := [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]
		var image := Image.create(HAZE_PERIOD, HAZE_HEIGHT, false, Image.FORMAT_RGBA8)
		var random := RandomNumberGenerator.new()
		random.seed = 7331
		var knots: Array[float] = []
		for index in 9: knots.append(random.randf())
		knots[8] = knots[0]
		for x in HAZE_PERIOD:
			var at := float(x) / HAZE_PERIOD * 8.0
			var knot := floori(at)
			var t := at - knot
			var wander := lerpf(knots[knot], knots[mini(knot + 1, 8)], t * t * (3.0 - 2.0 * t))
			var top := 4.0 + wander * 18.0 + sin(float(x) * .21) * 1.5
			for y in HAZE_HEIGHT:
				var ramp := clampf((float(y) - top) / (float(HAZE_HEIGHT) - top), 0.0, 1.0)
				var value := pow(ramp, 1.4) * 4.0
				var step := floorf(value)
				if value - step > (bayer[(y % 4) * 4 + x % 4] + .5) / 16.0: step += 1.0
				image.set_pixel(x, y, Color(1, 1, 1, clampf(step / 4.0, 0.0, 1.0)))
		_haze_texture = ImageTexture.create_from_image(image)
	return _haze_texture

func _ready() -> void:
	name = "BackdropGrade"
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	glow = Node2D.new()
	glow.name = "LightningGlow"
	var add := CanvasItemMaterial.new()
	add.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	glow.material = add
	glow.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	glow.draw.connect(_draw_glow)
	add_child(glow)

func configure(scenery: Node, night: float) -> void:
	var data: Variant = scenery.get("data")
	haze = haze_for(data if data is Dictionary else {}, night)
	ground_haze = ground_haze_for(data if data is Dictionary else {}, night)
	veil_strength = strength_for(data if data is Dictionary else {}, night)
	var rect: Variant = scenery.get("panorama_rect")
	if rect is Rect2 and (rect as Rect2).has_area():
		top_y = (rect as Rect2).position.y
		ground_y = (rect as Rect2).end.y
	queue_redraw()

## Lightning: strength and the bolt's top in world space. The sky around the
## bolt lights up; WorldLighting lifts the rest of the backdrop only slightly.
func set_flash(strength: float, at: Vector2) -> void:
	if is_equal_approx(strength, flash) and at.is_equal_approx(flash_at): return
	flash = strength
	flash_at = at
	if is_instance_valid(glow): glow.queue_redraw()

func _draw() -> void:
	var sky := Color(haze, SKY_ALPHA * veil_strength)
	var top := Color(haze, TOP_ALPHA * veil_strength)
	var ground := Color(haze, minf(GROUND_ALPHA * veil_strength, GROUND_ALPHA_MAX))
	draw_rect(Rect2(-EXTENT, -EXTENT, EXTENT * 2.0, EXTENT + top_y - 64.0), sky)
	draw_polygon(PackedVector2Array([Vector2(-EXTENT, top_y - 64.0), Vector2(EXTENT, top_y - 64.0), Vector2(EXTENT, top_y), Vector2(-EXTENT, top_y)]), PackedColorArray([sky, sky, top, top]))
	draw_polygon(PackedVector2Array([Vector2(-EXTENT, top_y), Vector2(EXTENT, top_y), Vector2(EXTENT, ground_y), Vector2(-EXTENT, ground_y)]), PackedColorArray([top, top, ground, ground]))
	draw_rect(Rect2(-EXTENT, ground_y, EXTENT * 2.0, EXTENT), ground)
	# Ground haze: tiled from a fixed world origin so it never swims.
	draw_texture_rect(haze_texture(), Rect2(-EXTENT, ground_line - HAZE_HEIGHT, EXTENT * 2.0, HAZE_HEIGHT), true, ground_haze)

## Soft radial falloff of the lightning glow: bright core, long thin tail.
static func flash_texture() -> GradientTexture2D:
	if _flash_texture == null:
		var gradient := Gradient.new()
		gradient.offsets = PackedFloat32Array([0.0, .18, .55, 1.0])
		gradient.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, .62), Color(1, 1, 1, .16), Color(1, 1, 1, 0)])
		_flash_texture = GradientTexture2D.new()
		_flash_texture.gradient = gradient
		_flash_texture.fill = GradientTexture2D.FILL_RADIAL
		_flash_texture.fill_from = Vector2(.5, .5)
		_flash_texture.fill_to = Vector2(1.0, .5)
		_flash_texture.width = 128
		_flash_texture.height = 128
	return _flash_texture

func _draw_glow() -> void:
	if flash <= .004: return
	var size := Vector2(FLASH_RADIUS * 2.0, FLASH_RADIUS * 1.4)
	glow.draw_texture_rect(flash_texture(), Rect2(flash_at + Vector2(0, 160) - size * .5, size), false, Color(.66, .74, .92, .48 * flash))
