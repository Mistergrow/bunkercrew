extends Node2D
## Marks that round impacts leave on the real surface they struck: a scuff on
## steel that glows and cools, a chipped pit in concrete, a divot in earth.
## Whole texels along the surface; a fixed pool, the oldest replaced; a mark
## dissolves texel by texel at the end of its life and goes at once when the
## surface it sits on moves, opens or is destroyed. Created on demand below the
## game by ImpactBurst (host and guests alike, from the replicated impact
## event); impacts in open air leave nothing. Presentation only.
const META := &"impact_marks"
const MAX_MARKS := 28
const LIFE := 7.0
const COOL := 0.55
const SURFACES := ["metal", "concrete", "earth"]

var _pos := PackedVector2Array()
var _normal := PackedVector2Array()
var _state := PackedVector2Array() # x: age (negative: free), y: surface index
var _support: Array[WeakRef] = []
var _support_transform: Array[Transform2D] = []
var _next := 0
var marks_made := 0

static func of(node: Node) -> Node2D:
	# The game owning a burst is its parent; stubs without one get no marks.
	if not is_instance_valid(node) or not node.is_inside_tree(): return null
	var host: Node = node.get_parent()
	if not (host is Node2D) or not host.has_method("impact"): return null
	if host.has_meta(META):
		var existing: Variant = host.get_meta(META)
		if is_instance_valid(existing) and not existing.is_queued_for_deletion() and existing.get_parent() == host: return existing
	var marks: Node2D = load("res://scripts/impact_marks.gd").new()
	marks.name = "ImpactMarks"
	host.set_meta(META, marks)
	host.add_child(marks)
	return marks

func _ready() -> void:
	z_index = 1
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_pos.resize(MAX_MARKS)
	_normal.resize(MAX_MARKS)
	_state.resize(MAX_MARKS)
	_support.resize(MAX_MARKS)
	_support_transform.resize(MAX_MARKS)
	for index in MAX_MARKS: _state[index] = Vector2(-1, 0)
	set_process(false)

## A mark at `at` on a static surface `collider` facing `normal`.
func mark(at: Vector2, normal: Vector2, surface: String, collider: Object) -> void:
	var kind := SURFACES.find(surface)
	if kind < 0 or not at.is_finite() or normal.length_squared() < .25 or not (collider is Node2D): return
	# A second hit on a fresh mark renews it instead of stacking another.
	for index in MAX_MARKS:
		if _state[index].x >= 0.0 and _pos[index].distance_squared_to(at) < 4.0:
			_state[index] = Vector2(0, kind)
			return
	# The first texel inside the surface, not the open texel in front of it.
	_pos[_next] = (at - normal.normalized() * .5).floor() + Vector2(.5, .5)
	_normal[_next] = normal.normalized()
	_state[_next] = Vector2(0, kind)
	_support[_next] = weakref(collider)
	_support_transform[_next] = (collider as Node2D).global_transform
	_next = (_next + 1) % MAX_MARKS
	marks_made += 1
	set_process(true)
	queue_redraw()

func _supported(index: int) -> bool:
	var body: Object = _support[index].get_ref() if _support[index] != null else null
	if not is_instance_valid(body) or (body is Node and (body as Node).is_queued_for_deletion()): return false
	if body.has_method("is_blocking") and not body.is_blocking(): return false
	if body is CollisionObject2D and ((body as CollisionObject2D).collision_layer & 3) == 0: return false
	return (body as Node2D).global_transform == _support_transform[index]

func _process(delta: float) -> void:
	var live := false
	for index in MAX_MARKS:
		var state := _state[index]
		if state.x < 0.0: continue
		state.x += delta
		if state.x >= LIFE or not _supported(index): state.x = -1.0
		else: live = true
		_state[index] = state
	queue_redraw()
	if not live: set_process(false)

func _draw() -> void:
	for index in MAX_MARKS:
		var state := _state[index]
		if state.x < 0.0: continue
		var age := state.x
		# The last seconds remove the mark's texels in a fixed order.
		var keep := 1.0 - smoothstep(LIFE * .6, LIFE, age)
		var tangent := _normal[index].orthogonal()
		var at := to_local(_pos[index])
		var cool := clampf(age / COOL, 0.0, 1.0)
		match int(state.y):
			0:
				# Steel: a bright gouge along the face that cools to a pale scratch
				# with a dark pit in the middle.
				var hot := Color("fff0b1").lerp(Color("a3a89c"), cool)
				_texel(at + tangent * -1.0, hot, keep, 0)
				_texel(at + tangent, hot, keep, 1)
				_texel(at, Color("ffd27a").lerp(Color("2a2f2e"), cool), keep, 2)
				if cool < 1.0: _texel(at + _normal[index], Color(1.0, .66, .30, 1.0 - cool), 1.0, 3)
			1:
				# Concrete: freshly broken stone is paler than the weathered face;
				# a dark pit one texel deeper gives the chip its depth.
				_texel(at, Color("c9c2ac"), keep, 0)
				_texel(at - _normal[index], Color("2b2823"), keep, 1)
				_texel(at + tangent, Color("a9a28d"), keep, 2)
				_texel(at - tangent, Color("8f8977"), keep, 3)
			_:
				# Earth: a dark divot with a crumbled lighter rim.
				_texel(at - tangent, Color("3a2e24"), keep, 0)
				_texel(at, Color("2c231b"), keep, 1)
				_texel(at + tangent, Color("3a2e24"), keep, 2)
				_texel(at - tangent * 2.0, Color("8a7458"), keep, 3)

## One whole texel; `order` drops it once `keep` falls below its turn.
func _texel(point: Vector2, color: Color, keep: float, order: int) -> void:
	if keep <= float(order) * .25: return
	draw_rect(Rect2(point.floor(), Vector2.ONE), color)
