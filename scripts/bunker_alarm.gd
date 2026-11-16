extends Node2D
## Wave alarm beacons: rotating warning lamps above the surface gates and on
## the roof edges. They turn while a wave is announced and for the first
## seconds of the attack, on the side the machines come from (both sides for a
## centred bunker); the other gate keeps a steady dim glow. Presentation only,
## from the replicated round phase and the bunker's position, on every peer.
## The reflector steps through ROTATION_KEYS authored keys at about one turn
## per second, so the bright face passes the viewer about once a second (well
## under three flashes per second); reduced effects keep a steady lit dome
## without the passing face or the beams. Drawn only: no light source of its
## own (WorldLighting already pulses the gate spill during a wave).
const PixelArt := preload("res://scripts/pixel_effect_art.gd")
const TURN_SECONDS := 0.92
const ROTATION_KEYS := 12
const ATTACK_HOLD := 5.0
const HOUSING := Color("23282a")
const HOUSING_LIT := Color("6f7364")
const GLASS_OFF := Color("4d1c18")
const GLASS := Color("b8321f")
const GLASS_HOT := Color("ff8a5c")
const GLASS_CORE := Color("ffe2c4")
const BEAM := Color(1.0, .30, .16)

var game: Node
var clock := 0.0
var active := false
var _phase := ""
var _since := 0.0
var _key := -1
var _quiet := false
## Beacon sockets: x, y (dome centre), side (-1 left, 1 right), roof (0/1).
var _sockets: Array[Vector4] = []
var _glow: Node2D

static func create(owner_game: Node) -> Node2D:
	var alarm: Node2D = load("res://scripts/bunker_alarm.gd").new()
	alarm.name = "BunkerAlarm"
	alarm.game = owner_game
	return alarm

func _ready() -> void:
	z_index = 2
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_glow = Node2D.new()
	_glow.name = "Beams"
	_glow.material = PixelArt.grid_material(PixelArt.GRID_ADD)
	_glow.draw.connect(_draw_beams)
	add_child(_glow)
	_place()

func _place() -> void:
	_sockets.clear()
	var bunker: Node = game.get("scenario_bunker") if is_instance_valid(game) else null
	var left := 90.0
	var right := 730.0
	var top := 245.0
	var ground := 430.0
	if is_instance_valid(bunker):
		left = float(bunker.get("room_left"))
		right = float(bunker.get("room_right"))
		ground = float(bunker.get("ground_y"))
		top = ScenarioBunker.ROOF_Y
	# Above each surface gate, on the inner face of the wall over the opening.
	var gate_top := ground - 91.0
	_sockets.append(Vector4(left + 36.0, gate_top - 10.0, -1.0, 0.0))
	_sockets.append(Vector4(right - 36.0, gate_top - 10.0, 1.0, 0.0))
	# On the roof slab over each outer wall.
	_sockets.append(Vector4(left + 10.0, top - 7.0, -1.0, 1.0))
	_sockets.append(Vector4(right - 10.0, top - 7.0, 1.0, 1.0))

## Sides the machines approach from: -1 left, 1 right, 0 both.
func attack_side() -> float:
	var scenario: Variant = ScenarioCombat.for_game(game) if is_instance_valid(game) else null
	if scenario == null: return 0.0
	match str(scenario.get("position_mode")):
		"left": return 1.0
		"right": return -1.0
	return 0.0

func _process(delta: float) -> void:
	if not is_instance_valid(game): return
	var rounds: Node = game.get("rounds")
	var phase := str(rounds.get("phase")) if is_instance_valid(rounds) else ""
	if phase != _phase:
		# The first observed phase (a guest joining mid-wave) is state, not an event.
		if not _phase.is_empty() and phase == "warning": clock = 0.0
		_phase = phase
		_since = 0.0
	_since += delta
	var now := phase == "warning" or (phase == "attack" and _since < ATTACK_HOLD)
	_quiet = WeaponEffectArt.reduced(game)
	if now: clock += delta
	var key := posmod(floori(clock / TURN_SECONDS * ROTATION_KEYS), ROTATION_KEYS) if now and not _quiet else -1
	if now != active or key != _key:
		active = now
		_key = key
		queue_redraw()
		_glow.queue_redraw()

func _turning(side: float) -> bool:
	var attack := attack_side()
	return active and (attack == 0.0 or attack == side)

## 0..1 of a turn for this beacon; the two sides turn half a turn apart.
func _turn(side: float) -> float:
	return fposmod(float(_key) / ROTATION_KEYS + (0.5 if side > 0.0 else 0.0), 1.0)

func _draw() -> void:
	for socket in _sockets:
		var at := Vector2(socket.x, socket.y).round()
		var side := socket.z
		var roof := socket.w > 0.5
		# Bracket to the wall (gate lamps) or a foot plate on the slab (roof).
		if roof:
			draw_rect(Rect2(at + Vector2(-7, 5), Vector2(14, 2)), HOUSING)
		else:
			draw_rect(Rect2(at + Vector2(-side * 9.0 - 2.0, 3), Vector2(4, 3)), HOUSING)
		draw_rect(Rect2(at + Vector2(-6, 2), Vector2(12, 3)), HOUSING)
		draw_rect(Rect2(at + Vector2(-6, 2), Vector2(12, 1)), HOUSING_LIT)
		var turning := _turning(side)
		var glass := GLASS_OFF
		if active: glass = GLASS if turning else GLASS.darkened(.35)
		# Dome on whole texels: a rounded cap, its shaded left flank, a lit rim.
		draw_rect(Rect2(at + Vector2(-3, -7), Vector2(6, 1)), glass.darkened(.10))
		draw_rect(Rect2(at + Vector2(-4, -6), Vector2(8, 1)), glass)
		draw_rect(Rect2(at + Vector2(-5, -5), Vector2(10, 7)), glass)
		draw_rect(Rect2(at + Vector2(-5, -5), Vector2(2, 7)), glass.darkened(.28))
		draw_rect(Rect2(at + Vector2(-2, -6), Vector2(3, 1)), glass.lightened(.25))
		if active:
			if not turning or _quiet or _key < 0:
				draw_rect(Rect2(at + Vector2(-1, -4), Vector2(3, 4)), GLASS_HOT)
			else:
				# The reflector: a hot band stepping across the dome as it turns,
				# white while it faces the viewer.
				var turn := _turn(side)
				var column := roundi(-3.5 + 7.0 * (0.5 - 0.5 * cos(turn * TAU)))
				var front := sin(turn * TAU) > 0.0
				draw_rect(Rect2(at + Vector2(column - 1, -5), Vector2(3, 6)), GLASS_HOT if front else glass.lightened(.10))
				if front and absf(turn - 0.25) < 0.09:
					draw_rect(Rect2(at + Vector2(-3, -5), Vector2(6, 6)), GLASS_HOT)
					draw_rect(Rect2(at + Vector2(-2, -4), Vector2(4, 4)), GLASS_CORE)
		# Wire cage over the glass and its cap.
		for x in [-3, 2]:
			draw_rect(Rect2(at + Vector2(x, -6), Vector2(1, 8)), HOUSING)
		draw_rect(Rect2(at + Vector2(-5, -2), Vector2(10, 1)), HOUSING)
		draw_rect(Rect2(at + Vector2(-1, -9), Vector2(2, 2)), HOUSING)

## Beams and the passing face, additive on the texel grid.
func _draw_beams() -> void:
	if not active or _quiet or _key < 0: return
	for socket in _sockets:
		var side := socket.z
		if not _turning(side): continue
		var at := Vector2(socket.x, socket.y - 2.0).round()
		var turn := _turn(side)
		var across := cos(turn * TAU)
		var facing := sin(turn * TAU)
		if facing > 0.5:
			# Facing the viewer: a halo around the dome.
			PixelArt.grid_halo(_glow, at, 12.0 + 7.0 * facing, Color(BEAM, .50 * facing))
		elif absf(across) > 0.30:
			# A beam swept out to one side: stepped bands, wider and fainter.
			var direction := signf(across)
			var reach := absf(across)
			for band in 5:
				var height := 3.0 + band * 2.0
				_beam_band(at + Vector2(direction * (5.0 + band * 14.0), -height * 0.5), Vector2(direction * 14.0, height), Color(BEAM, (.32 - band * .06) * reach))

func _beam_band(origin: Vector2, size: Vector2, color: Color) -> void:
	var rect := Rect2(origin, size).abs()
	_glow.draw_rect(Rect2(rect.position.round(), rect.size.round()), color)
