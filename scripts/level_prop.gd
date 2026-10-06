class_name LevelProp
extends Node2D
## One independently replaceable piece of background equipment. Artwork comes
## from an atlas cell; moving parts, indicators and light remain separate nodes.

enum Kind { CABINET, WORKBENCH, PIPES, CRATE, BARREL, LAMP, FAN, GAS_BOTTLES,
	CEMENT_SACKS, WHEELBARROW, JUNCTION_BOX, CONSOLE, FLAG, SCRAP, CABLE_SPOOL, MINE_BRACE }
enum Anchor { FEET, CENTER, CEILING }

@export var kind_index: Kind = Kind.CRATE
@export var display_size := Vector2(48, 48)
@export var anchor: Anchor = Anchor.FEET
@export var sprite_override: Texture2D
@export var flip_horizontal := false
@export var light_strength := 1.0
@export var motion_enabled := true

# These textures are independently reusable in the editor. Their measured
# regions retain complete handles/feet; image scanning is never needed at run time.
const SPRITE_RESOURCES := [
	"res://assets/props/cabinet.tres", "res://assets/props/workbench.tres",
	"res://assets/props/pipes.tres", "res://assets/props/crate.tres",
	"res://assets/props/barrel.tres", "res://assets/props/lamp.tres",
	"res://assets/props/fan.tres", "res://assets/props/gas_bottles.tres",
	"res://assets/props/cement_sacks.tres", "res://assets/props/wheelbarrow.tres",
	"res://assets/props/junction_box.tres", "res://assets/props/console.tres",
	"res://assets/props/flag.tres", "res://assets/props/scrap.tres",
	"res://assets/props/cable_spool.tres", "res://assets/props/mine_brace.tres",
]
static var _textures: Dictionary = {}
var artwork: Sprite2D
var moving_part: Node2D
var indicators: Node2D
var glow: Node2D
var cable: Line2D
var _bounds := Rect2()
var _clock := 0.0
var _phase := 0.0
var _fan_radius := 0.0

func _ready() -> void:
	add_to_group("level_props")
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_phase = position.x * 0.041 + position.y * 0.017 + kind_index
	_build_artwork()
	if artwork == null:
		return
	_build_moving_parts()
	set_process(motion_enabled and (moving_part != null or indicators != null or glow != null or cable != null))

func _build_artwork() -> void:
	var texture: Texture2D = sprite_override
	if texture == null:
		var index := clampi(kind_index, 0, SPRITE_RESOURCES.size() - 1)
		if not _textures.has(index):
			var path: String = SPRITE_RESOURCES[index]
			if not ResourceLoader.exists(path):
				push_warning("Industrial prop texture is missing: " + path)
				return
			_textures[index] = load(path)
		texture = _textures[index]
	var factor := minf(display_size.x / texture.get_width(), display_size.y / texture.get_height())
	var size := texture.get_size() * factor
	var top_left := Vector2(-size.x * 0.5, -size.y)
	if anchor == Anchor.CENTER:
		top_left.y = -size.y * 0.5
	elif anchor == Anchor.CEILING:
		top_left.y = 0.0
	_bounds = Rect2(top_left, size)
	artwork = Sprite2D.new()
	artwork.name = "Artwork"
	artwork.texture = texture
	artwork.position = _bounds.get_center()
	artwork.scale = Vector2.ONE * factor
	artwork.flip_h = flip_horizontal
	add_child(artwork)

func _build_moving_parts() -> void:
	if kind_index == Kind.FAN:
		_fan_radius = minf(_bounds.size.x, _bounds.size.y) * 0.35
		moving_part = Node2D.new()
		moving_part.name = "RotatingFan"
		moving_part.position = _bounds.get_center() - Vector2(_bounds.size.x * 0.04, 0)
		moving_part.draw.connect(_draw_fan)
		add_child(moving_part)
		var guard := Node2D.new()
		guard.name = "FanGuard"
		guard.position = moving_part.position
		guard.draw.connect(func():
			guard.draw_circle(Vector2.ZERO, _fan_radius + 1, Color("343e38"), false, 2)
			guard.draw_circle(Vector2.ZERO, 2, Color("b1a98a"))
			for offset in [-0.55, 0.55]:
				guard.draw_line(Vector2(-_fan_radius, offset * _fan_radius), Vector2(_fan_radius, offset * _fan_radius), Color("343b34"), 1)
		)
		add_child(guard)
	elif kind_index == Kind.LAMP:
		glow = Node2D.new()
		glow.name = "WarmLampGlow"
		glow.position = _bounds.get_center() + Vector2(0, _bounds.size.y * 0.28)
		glow.z_index = -1
		glow.draw.connect(_draw_glow)
		add_child(glow)
	elif kind_index in [Kind.CABINET, Kind.CONSOLE, Kind.JUNCTION_BOX, Kind.GAS_BOTTLES]:
		indicators = Node2D.new()
		indicators.name = "EquipmentIndicators"
		indicators.draw.connect(_draw_indicators)
		add_child(indicators)
		if kind_index == Kind.JUNCTION_BOX:
			cable = Line2D.new()
			cable.name = "LooseCable"
			cable.width = 2.0
			cable.default_color = Color("242a25")
			add_child(cable)

func _process(delta: float) -> void:
	_clock += delta
	if moving_part != null:
		moving_part.rotation = _clock * 3.1 + _phase
	if indicators != null:
		indicators.queue_redraw()
	if glow != null:
		glow.queue_redraw()
	if cable != null:
		var start := Vector2(_bounds.get_center().x + _bounds.size.x * 0.22, _bounds.end.y - 1)
		var sway := sin(_clock * 1.4 + _phase) * 1.8
		cable.points = PackedVector2Array([start, start + Vector2(sway - 2, 8), start + Vector2(sway + 3, 17), start + Vector2(sway + 1, 24)])

func _draw_fan() -> void:
	moving_part.draw_circle(Vector2.ZERO, _fan_radius, Color("202a27"))
	for blade in 5:
		var angle := blade * TAU / 5.0
		var points := PackedVector2Array()
		for point in [Vector2(2, -1), Vector2(_fan_radius * 0.68, -_fan_radius * 0.46), Vector2(_fan_radius * 0.95, -_fan_radius * 0.15), Vector2(_fan_radius * 0.72, _fan_radius * 0.18), Vector2(2, 2)]:
			points.append(point.rotated(angle))
		moving_part.draw_colored_polygon(points, Color("8e947b"))

func _draw_glow() -> void:
	var flicker := 0.94 + sin(_clock * 9.0 + _phase) * 0.035 + sin(_clock * 23.0) * 0.02
	for radius in range(5, 0, -1):
		glow.draw_circle(Vector2(0, radius * 3), float(radius) * 10, Color(1.0, 0.66, 0.27, 0.018 * flicker * light_strength))
	# The sprite contains the cage; this small luminous core gives the bulb life.
	glow.draw_circle(Vector2.ZERO, 3, Color(1.0, 0.84, 0.49, 0.7 * flicker))

func _draw_indicators() -> void:
	var origin := _bounds.position
	var size := _bounds.size
	if kind_index == Kind.GAS_BOTTLES:
		var gauge := origin + size * Vector2(0.68, 0.18)
		indicators.draw_circle(gauge, 3.0, Color("b5baa0"))
		var angle := -0.8 + sin(_clock * 1.2 + _phase) * 0.08
		indicators.draw_line(gauge, gauge + Vector2(2, 0).rotated(angle), Color("303a32"), 1)
		return
	var at := origin + size * Vector2(0.72, 0.33)
	var blink := sin(_clock * 2.1 + _phase) > -0.25
	indicators.draw_rect(Rect2(at.round(), Vector2(2, 2)), Color("d9b654") if blink else Color("655731"))
	if kind_index == Kind.CONSOLE:
		indicators.draw_rect(Rect2((at + Vector2(-5, 0)).round(), Vector2(2, 2)), Color("8eb19a"))
