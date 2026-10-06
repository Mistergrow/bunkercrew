extends RefCounted
## Generic pixel alert/search cues use the robot's existing brass and olive.
## The owner reports semantic task changes; this helper never replans a route.
const ALERT_SECONDS := 0.95
const SEARCH_SECONDS := 1.65
var kind := ""
var remaining := 0.0
var direction := 1.0
var _duration := 0.0

func notice(value: String, towards: Vector2 = Vector2.ZERO) -> void:
	if value not in ["alert", "search"]:
		clear()
		return
	kind = value
	_duration = ALERT_SECONDS if value == "alert" else SEARCH_SECONDS
	remaining = _duration
	if absf(towards.x) > 0.01:
		direction = signf(towards.x)

func clear() -> void:
	kind = ""
	remaining = 0.0
	_duration = 0.0

func advance(delta: float) -> bool:
	var was_active := is_active()
	var dt := maxf(0.0, delta) if is_finite(delta) else 0.0
	remaining = maxf(0.0, remaining - dt)
	if remaining <= 0.0:
		kind = ""
	return was_active

func is_active() -> bool:
	return not kind.is_empty() and remaining > 0.0

func head_look(base: float) -> float:
	if not is_active():
		return base
	var age := _duration - remaining
	var fade := smoothstep(0.0, 0.10, age) * smoothstep(0.0, 0.18, remaining)
	var look := direction * 4.5
	if kind == "search":
		look = sin(age * 6.0) * 4.5
	return lerpf(base, look, fade)

func draw(canvas: Node2D) -> bool:
	if not is_active():
		return false
	var age := _duration - remaining
	var opacity := smoothstep(0.0, 0.06, age) * smoothstep(0.0, 0.20, remaining)
	var base := Vector2(24, -57 - roundf((1.0 - smoothstep(0.0, 0.14, age)) * 2.0))
	var tint := Color("ddb76d") if kind == "alert" else Color("acba97")
	tint.a = opacity
	var ink := Color("17211f")
	ink.a = opacity
	var pixels: Array[Vector2i] = []
	if kind == "alert":
		pixels.assign([Vector2i(1,0),Vector2i(2,0),Vector2i(1,1),Vector2i(2,1),Vector2i(1,2),Vector2i(2,2),Vector2i(1,3),Vector2i(2,3),Vector2i(1,4),Vector2i(1,6),Vector2i(2,6)])
	else:
		pixels.assign([Vector2i(1,0),Vector2i(2,0),Vector2i(3,0),Vector2i(0,1),Vector2i(3,1),Vector2i(3,2),Vector2i(2,3),Vector2i(1,4),Vector2i(1,6)])
	# Outline follows the glyph itself: no panel, rounded badge or foreign font.
	for pixel: Vector2i in pixels:
		canvas.draw_rect(Rect2(base + Vector2(pixel) - Vector2.ONE, Vector2(3,3)), ink)
	for pixel: Vector2i in pixels:
		canvas.draw_rect(Rect2(base + Vector2(pixel), Vector2.ONE), tint)
	return true
