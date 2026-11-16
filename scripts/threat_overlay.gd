extends Control
## Threat read of the local view, drawn in the HUD canvas from state every peer
## already has (replicated enemy position, hp, max_hp, kind, elite and the
## round phase), so a guest sees what the host sees:
## - framed health bars (UiArt.meter, with a draining trail) that fade in as an
##   enemy closes on the bunker or the crew, or once it has taken damage;
## - outlined names only on elite and named threats (announced heavy contacts,
##   the final machine); every other enemy keeps just its bar;
## - red edge indicators toward enemies outside the view (chevrons for how
##   near, a class glyph and the count), during combat only, grouped per side
##   and class, capped.
## While it covers a game (the HUD is shown) the enemies skip their own
## world-space bar and label (see covers()); with the HUD hidden they draw
## them as before. In menus nothing is drawn. Presentation only. The airship
## shield stays world art: the airship draws it through draw_shield().
const L := preload("res://scripts/locale_text.gd")
const MAX_BARS := 16
const MAX_ARROWS := 6
## World distance from the bunker's outer wall (or from a worker) at which an
## approaching enemy's bar appears: past the outer fence line (445).
const APPROACH := 520.0
const FADE_IN := 5.0
const FADE_OUT := 2.5
const TRAIL_HOLD := .45
const TRAIL_DRAIN := 1.1
const SCAN_SECONDS := .1
const HEAVY_CHASSIS := ["breaker", "colossus", "siege"]
const COMBAT_PHASES := ["warning", "attack", "occupation"]
const HOSTILE := Color("d0583f")
const HOSTILE_LIGHT := Color("f08a5c")
const SHIELD := Color("86dcf4")
const OUTLINE := Color(0.025, 0.035, 0.04, 0.92)
## 7x7 class silhouettes facing left like the native machine art ("=" marks
## the gun or nose), drawn in 2x2 design-pixel cells.
const GLYPHS := {
	"infantry": ["...###.", "..#####", "...###.", "=######", "...###.", "...#.#.", "..##.##"],
	"mech": [".......", ".#####.", "=######", ".#####.", ".#...#.", "#.....#", "#.....#"],
	"vehicle": [".......", "..###..", "====##.", ".#####.", "#######", "#.#.#.#", "......."],
	"air": [".......", "......#", ".....##", "=######", "..####.", "...#...", "......."],
}
static var _current: WeakRef
var game
var hud
## True while this overlay owns the enemies' status drawing (HUD shown).
var covering := false
var bars_drawn := 0
var arrows_drawn := 0
var _enemies: Array[Node2D] = []
var _scan := 0.0
var _state: Dictionary = {}
var _order: Array[Node2D] = []
var _label_rects: Array[Rect2] = []
var _bar_rects: Array[Rect2] = []
## Bars and names drawn last frame (HUD canvas); combat numbers keep clear.
var drawn_rects: Array[Rect2] = []
var _reduced := false
var _unit := 1.0

## Called from the enemies' own _draw(): skip the world-space status (bar,
## label, shield) while an overlay draws it for their game.
static func covers(enemy: Node) -> bool:
	if _current == null: return false
	var overlay: Variant = _current.get_ref()
	return overlay != null and is_instance_valid(overlay) and overlay.covering and is_instance_valid(enemy) and overlay.game == enemy.get("game")

func _ready() -> void:
	name = "ThreatOverlay"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_current = weakref(self)

func _exit_tree() -> void:
	if _current != null and _current.get_ref() == self: _current = null

func _process(delta: float) -> void:
	covering = is_instance_valid(game) and bool(game.get("started")) and is_instance_valid(hud) and hud.visible
	visible = covering and str(hud.overlay).is_empty() and not (hud.has_method("has_session_action") and hud.has_session_action())
	if not visible:
		return
	_reduced = "weather" in game and is_instance_valid(game.weather) and bool(game.weather.reduced_effects)
	if get_tree().paused: delta = 0.0
	_scan -= delta
	if _scan <= 0.0 or _enemies.is_empty():
		_scan = SCAN_SECONDS
		_refresh()
	for enemy in _enemies:
		if not is_instance_valid(enemy): continue
		var entry: Dictionary = _state.get(enemy.get_instance_id(), {})
		if entry.is_empty(): continue
		var ratio := _ratio(enemy)
		var want := _wants_bar(enemy, ratio)
		var target := 1.0 if want else 0.0
		entry.shown = target if _reduced else move_toward(float(entry.shown), target, delta * (FADE_IN if want else FADE_OUT))
		if ratio < float(entry.ratio) - .0001:
			entry.trail = maxf(float(entry.trail), float(entry.ratio))
			entry.hold = TRAIL_HOLD
		entry.ratio = ratio
		if float(entry.hold) > 0.0: entry.hold = float(entry.hold) - delta
		else: entry.trail = move_toward(float(entry.trail), ratio, delta * TRAIL_DRAIN)
	queue_redraw()

func _refresh() -> void:
	_enemies.clear()
	var seen := {}
	for node in get_tree().get_nodes_in_group("enemies"):
		if not node is Node2D or node.get("game") != game or bool(node.get("dead")) or node.is_queued_for_deletion(): continue
		_enemies.append(node)
		var id: int = node.get_instance_id()
		seen[id] = true
		if not _state.has(id):
			var ratio := _ratio(node)
			_state[id] = {"shown": 0.0, "ratio": ratio, "trail": ratio, "hold": 0.0, "hull": _hull_node(node)}
	for id in _state.keys():
		if not seen.has(id): _state.erase(id)

static func _ratio(enemy: Node) -> float:
	var top := float(enemy.get("max_hp")) if enemy.get("max_hp") != null else 1.0
	return clampf(float(enemy.get("hp")) / maxf(top, .001), 0.0, 1.0) if enemy.get("hp") != null else 1.0

static func _hull_node(enemy: Node) -> CollisionShape2D:
	for hull_name in ["MachineHitbox", "AircraftHull"]:
		var shape := enemy.get_node_or_null(hull_name) as CollisionShape2D
		if shape != null and shape.shape is RectangleShape2D: return shape
	return null

## World rectangle of an enemy's hull (its hitbox), the anchor for its status.
func _hull(enemy: Node2D) -> Rect2:
	var entry: Dictionary = _state.get(enemy.get_instance_id(), {})
	var shape: CollisionShape2D = entry.get("hull") if is_instance_valid(entry.get("hull")) else null
	if shape == null: return Rect2(enemy.global_position - Vector2(24, 48), Vector2(48, 48))
	var extent: Vector2 = (shape.shape as RectangleShape2D).size * shape.global_scale.abs()
	return Rect2(shape.global_position - extent * .5, extent)

## World height of the top of an enemy's art: the anchors its own status
## used (machines and infantry), the painted hull for aircraft.
static func _art_top(enemy: Node2D) -> float:
	var art_scale := float(enemy.get("visual_scale")) if enemy.get("visual_scale") != null else 1.0
	var local := -48.0
	if enemy.is_in_group("air_enemies"):
		var profile: Variant = enemy.get("profile")
		var body: Vector2 = (profile as Dictionary).get("body_size", Vector2(57, 34)) if profile is Dictionary else Vector2(57, 34)
		local = -body.y * .5 - 4.0
	elif enemy.get("stance") != null:
		local = (-73.0 + float(enemy.get("stance")) * 10.0) * art_scale
	elif enemy.get("body_height") != null:
		local = -float(enemy.get("body_height")) - 33.0 * art_scale
	return enemy.to_global(Vector2(0, local)).y

static func family(kind: String) -> String:
	if AirEnemyCatalog.is_air(kind): return "air"
	if EnemyCatalog.is_human(kind): return "infantry"
	if kind in EnemyCatalog.VEHICLE_CLASSES: return "vehicle"
	return "mech"

func _front_distance(at: Vector2) -> float:
	var bunker: Node = game.get("scenario_bunker")
	if is_instance_valid(bunker) and bunker.get("room_left") != null:
		return maxf(0.0, maxf(float(bunker.room_left) - at.x, at.x - float(bunker.room_right)))
	var core: Node = game.get("core")
	if is_instance_valid(core) and core is Node2D: return maxf(0.0, absf(at.x - (core as Node2D).global_position.x) - 140.0)
	return INF

func _wants_bar(enemy: Node2D, ratio: float) -> bool:
	# The final machine's health already has the boss status strip.
	if "overdrive" in enemy: return false
	if ratio < .999 or bool(enemy.get("elite")): return true
	# Engaged: it has fired (replicated shot counter) or is winding up.
	if int(enemy.get("attack_count") if enemy.get("attack_count") != null else 0) > 0 or float(enemy.get("windup") if enemy.get("windup") != null else 0.0) > 0.0: return true
	var at := enemy.global_position
	if _front_distance(at) < APPROACH: return true
	for worker in game.players:
		if is_instance_valid(worker) and (worker as Node2D).global_position.distance_to(at) < APPROACH * .8: return true
	return false

## Heavy chassis, elites and aircraft: a taller, wider bar.
func _major(enemy: Node2D) -> bool:
	if bool(enemy.get("elite")) or enemy.is_in_group("air_enemies"): return true
	return enemy.has_method("chassis_kind") and str(enemy.chassis_kind()) in HEAVY_CHASSIS

## Only elite and named threats carry a name over their bar: an announced
## heavy contact (replicated `boss_title` meta) and the final machine. A
## class name over every drone and tank only covered the sky they fly in.
## Static so an enemy drawing its own status (HUD hidden) can follow the same
## rule.
static func shows_name(enemy: Node) -> bool:
	return is_instance_valid(enemy) and (bool(enemy.get("elite")) or enemy.has_meta("boss_title") or bool(enemy.get_meta("final_boss", false)))

func _labelled(enemy: Node2D) -> bool:
	return shows_name(enemy)

func _label(enemy: Node2D) -> String:
	if enemy.has_meta("boss_title"): return L.text(str(enemy.get_meta("boss_title")))
	var profile: Variant = enemy.get("profile")
	var label := L.text(str((profile as Dictionary).get("label", ""))) if profile is Dictionary else ""
	return L.format("ELITE · %s", label) if bool(enemy.get("elite")) else label

func _draw() -> void:
	bars_drawn = 0
	arrows_drawn = 0
	if not is_instance_valid(game) or not is_instance_valid(get_viewport()): return
	var world := get_global_transform_with_canvas().affine_inverse() * get_viewport().get_canvas_transform()
	var zoom := absf(world.get_scale().x)
	var screen: Rect2 = hud.screen_rect() if hud.has_method("screen_rect") else get_viewport_rect()
	var view := world.affine_inverse() * screen
	_draw_bars(world, zoom, screen, view)
	if in_combat():
		_unit = _glyph_unit()
		_draw_arrows(world, screen, view)

## Edge arrows belong to combat only (replicated round phase).
func in_combat() -> bool:
	var rounds: Variant = game.get("rounds") if is_instance_valid(game) else null
	return rounds is Node and is_instance_valid(rounds) and str(rounds.get("phase")) in COMBAT_PHASES

# ------------------------------------------------------------------ shields

## The shield of a shielded airship, drawn by the airship itself in world
## space (it is world state, so it stays when the HUD is hidden): an energy
## field that hugs the hull as pixel art on the world texel grid, a 2-texel
## rim brightest on the crown and dim on the keel, ordered-dither bands that
## thin out toward the hull, a crown highlight (no outline box, no dark ink
## edge), a crest that steps down through the field and sparks along the rim.
## A hit (shield_flash) flares the whole field; rapid hits keep it lit rather
## than strobing. No allocation per frame.
static func draw_shield(machine: Node2D, flash: float) -> void:
	const RX := 88.0
	const RY := 46.0
	const DROP := 2.0
	var quiet := WeaponEffectArt.reduced(machine.get("game"))
	var clock := 0.0 if quiet else float(preload("res://scripts/actor_wet_materials.gd").clock)
	# Reduced effects keep only a slight, steady lift on a hit.
	var hit := clampf(flash / .25, 0.0, 1.0) * (.35 if quiet else 1.0)
	# The bubble is world art at one texel per world unit
	# (tools/bake_shield_world.py: 2-texel rim, dithered inner bands, crown
	# highlight), drawn 1:1 on whole world texels in an unmirrored frame, so
	# the crown stays lit from the upper left whichever way the ship flies.
	var world := machine.get_global_transform()
	machine.draw_set_transform_matrix(world.affine_inverse() * Transform2D(Vector2.RIGHT, Vector2.DOWN, world.origin.round()))
	var bubble: Texture2D = _shield_texture()
	var crown := Color("f2fffd")
	if bubble != null:
		var lift := 1.0 + hit * .55
		machine.draw_texture(bubble, Vector2(-RX - 1.0, -RY - 1.0 + DROP), Color(lift, lift, lift, 1.0))
	if not quiet:
		# A crest of light sweeps down the shell: one bright row of rim texels
		# on each side, stepping a texel at a time.
		var crest := floorf(fposmod(clock * 9.0, RY * 2.0 + 24.0) - 12.0 - RY)
		if absf(crest + .5) < RY:
			var half := _shield_half(RX, RY, crest + .5)
			for side in [-1.0, 1.0]:
				var at := Vector2(-half if side < 0.0 else half - 2.0, crest + DROP)
				machine.draw_rect(Rect2(at, Vector2(2, 1)), Color(crown, .9))
		# Energy running round the shell: a few white texels travel along the rim.
		for spark in 4:
			var angle := clock * .9 + float(spark) * TAU / 4.0
			var at := Vector2(cos(angle) * (RX - .5), sin(angle) * (RY - .5) + DROP).round()
			machine.draw_rect(Rect2(at - Vector2(1, 0), Vector2(2, 1)), Color(crown, .95))
	machine.draw_set_transform_matrix(Transform2D.IDENTITY)

const SHIELD_PATH := "res://assets/enemies/shield_bubble_world.png"
static var _shield: Texture2D

static func _shield_texture() -> Texture2D:
	if _shield == null and ResourceLoader.exists(SHIELD_PATH): _shield = load(SHIELD_PATH)
	return _shield

## Half width in whole texels of an ellipse with radii rx, ry at row centre y.
static func _shield_half(rx: float, ry: float, y: float) -> float:
	if absf(y) >= ry: return 0.0
	return roundf(rx * sqrt(1.0 - (y * y) / (ry * ry)))

# -------------------------------------------------------------------- bars

## Enemies in `view` (world rect) whose bar shows, nearest the bunker first
## once there are more than MAX_BARS.
func bar_enemies(view: Rect2) -> Array[Node2D]:
	_order.clear()
	for enemy in _enemies:
		if not is_instance_valid(enemy): continue
		var entry: Dictionary = _state.get(enemy.get_instance_id(), {})
		if entry.is_empty() or float(entry.shown) <= .01: continue
		if not _hull(enemy).intersects(view): continue
		_order.append(enemy)
	if _order.size() > MAX_BARS:
		_order.sort_custom(func(a: Node2D, b: Node2D) -> bool: return _front_distance(a.global_position) < _front_distance(b.global_position))
		_order.resize(MAX_BARS)
	return _order

## Off-screen threats grouped per screen side and class, nearest first and
## capped at MAX_ARROWS. `in_sight` collects the world hulls already visible.
func arrow_groups(view: Rect2, in_sight: Array[Rect2] = []) -> Array:
	var groups := {}
	for enemy in _enemies:
		if not is_instance_valid(enemy): continue
		var hull := _hull(enemy)
		if hull.intersects(view):
			in_sight.append(hull)
			continue
		var center := Vector2(hull.get_center().x, minf(hull.position.y, _art_top(enemy)) - 10.0)
		var side := "left" if center.x < view.position.x else ("right" if center.x > view.end.x else ("top" if center.y < view.position.y else "bottom"))
		var kind := family(str(enemy.get("kind")))
		var key := side + ":" + kind
		var distance := view.get_center().distance_to(center)
		# How far beyond the edge of the view it is (world units).
		var beyond := maxf(0.0, float({"left": view.position.x - hull.end.x, "right": hull.position.x - view.end.x, "top": view.position.y - hull.end.y}.get(side, hull.position.y - view.end.y)))
		var group: Dictionary = groups.get(key, {})
		if group.is_empty():
			groups[key] = {"side": side, "kind": kind, "count": 1, "distance": distance, "beyond": beyond, "at": center}
		else:
			group.count = int(group.count) + 1
			group.beyond = minf(float(group.beyond), beyond)
			if distance < float(group.distance):
				group.distance = distance
				group.at = center
	var ordered: Array = groups.values()
	ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.distance) < float(b.distance))
	return ordered.slice(0, MAX_ARROWS)

func _draw_bars(world: Transform2D, zoom: float, screen: Rect2, view: Rect2) -> void:
	_label_rects.clear()
	drawn_rects.clear()
	_bar_rects.clear()
	# Older contacts keep their place; a later one whose bar would print over
	# theirs stacks above it, so every machine in a cluster keeps a bar of its
	# own that can be counted.
	var enemies := bar_enemies(view)
	if enemies.size() > 1: enemies.sort_custom(_spawned_earlier)
	for enemy in enemies:
		var entry: Dictionary = _state[enemy.get_instance_id()]
		var hull := _hull(enemy)
		var top := world * Vector2(hull.get_center().x, minf(hull.position.y, _art_top(enemy)))
		# Close framings show the machines larger: bar and label grow with
		# them in whole steps, up to 1.5x of the overview size.
		var grow := clampf(snappedf(zoom * .55, .25), 1.0, 1.5)
		# Major threats (heavy chassis, elites, aircraft up to the airship) get
		# a taller bar that may span more of their hull; the rest stay slim.
		# Only elite and named ones (see _labelled) add their name above it.
		var major := _major(enemy)
		var named := _labelled(enemy)
		var height := (4.0 if grow < 1.25 else 5.0) + (2.0 if major else 0.0)
		var width := clampf(roundf(hull.size.x * .62 * zoom), 22.0, roundf((112.0 if major else 64.0) * grow))
		var rect := Rect2(Vector2(roundf(top.x - width * .5), roundf(top.y - 3.0 - height)), Vector2(width, height))
		rect.position.y = clampf(rect.position.y, screen.position.y + 4.0, screen.end.y - 4.0 - height)
		rect = _stacked(rect, screen)
		_bar_rects.append(rect)
		var alpha := float(entry.shown)
		_meter(rect, float(entry.ratio), float(entry.trail), alpha)
		if drawn_rects.size() < MAX_BARS * 2: drawn_rects.append(rect.grow(1))
		if named:
			# Machines flying or rolling in a stack keep one readable name: a
			# label that would print over an earlier one is left out (its bar
			# stays), instead of two names merging into one smear.
			var label := _label(enemy)
			var font_size := roundi(12.0 * grow)
			var label_width := UiArt.FONT.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
			var label_rect := Rect2(rect.get_center().x - label_width * .5 - 2.0, rect.position.y - 4.0 - UiArt.FONT.get_ascent(font_size), label_width + 4.0, UiArt.FONT.get_height(font_size))
			var clear := true
			for taken in _label_rects:
				if taken.intersects(label_rect):
					clear = false
					break
			if clear:
				_label_rects.append(label_rect)
				drawn_rects.append(label_rect)
				_outlined(Vector2(rect.get_center().x, rect.position.y - 4.0), label, font_size, UiArt.AMBER if bool(enemy.get("elite")) else UiArt.IVORY, alpha)
		bars_drawn += 1

## `rect` moved up in whole bar steps (bar height plus a 3 px gap) until it
## clears every bar already placed this frame; at most STACK_STEPS steps, then
## it stays where the last step put it.
const STACK_STEPS := 4
static func _spawned_earlier(a: Node2D, b: Node2D) -> bool:
	return a.get_instance_id() < b.get_instance_id()

func _stacked(rect: Rect2, screen: Rect2) -> Rect2:
	for attempt in STACK_STEPS:
		var hit := false
		for placed in _bar_rects:
			if placed.grow(1.0).intersects(rect):
				rect.position.y = placed.position.y - rect.size.y - 3.0
				hit = true
		if not hit or rect.position.y < screen.position.y + 4.0: break
	rect.position.y = maxf(rect.position.y, screen.position.y + 4.0)
	return rect

## UiArt.meter's inked frame, lit edge and draining trail, with a fade.
func _meter(rect: Rect2, ratio: float, trail: float, alpha: float) -> void:
	draw_rect(rect.grow(1), Color(UiArt.INK, alpha))
	draw_rect(rect, Color(Color("2b3832"), alpha))
	if trail > ratio:
		draw_rect(Rect2(rect.position, Vector2(floorf(rect.size.x * clampf(trail, 0.0, 1.0)), rect.size.y)), Color(Color("e9d9b0"), alpha))
	var fill := Rect2(rect.position, Vector2(floorf(rect.size.x * ratio), rect.size.y))
	if ratio > 0.0 and fill.size.x < 1.0: fill.size.x = 1.0
	draw_rect(fill, Color(HOSTILE, alpha))
	if fill.size.x > 1.0: draw_rect(Rect2(fill.position, Vector2(fill.size.x, 1)), Color(HOSTILE_LIGHT, alpha))
	if fill.size.x > 1.0 and rect.size.y >= 5.0: draw_rect(Rect2(fill.position + Vector2(0, rect.size.y - 1), Vector2(fill.size.x, 1)), Color(HOSTILE.darkened(.25), alpha))
	# Long bars read in quarters, like UiArt.meter (two design pixels wide).
	if rect.size.x >= 64.0:
		for quarter in [.25, .5, .75]:
			draw_rect(Rect2(rect.position + Vector2(roundf(rect.size.x * quarter) - 1.0, 0), Vector2(2, rect.size.y)), Color(UiArt.INK, .42 * alpha))

func _outlined(anchor: Vector2, value: String, font_size: int, color: Color, alpha: float = 1.0) -> void:
	var at := (anchor - Vector2(UiArt.FONT.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x * .5, 0)).round()
	UiArt.outlined(self, at, value, font_size, Color(color, alpha), UiArt.ring_step(self), OUTLINE)

# ------------------------------------------------------------------- arrows

func _draw_arrows(world: Transform2D, screen: Rect2, view: Rect2) -> void:
	var in_sight: Array[Rect2] = []
	var ordered := arrow_groups(view, in_sight)
	if ordered.is_empty(): return
	# Arrows never cover a machine that is already in sight, nor the HUD.
	var reserved: Array[Rect2] = []
	for hull in in_sight: reserved.append(Rect2(world * hull.position, hull.size * absf(world.get_scale().x)).grow(4))
	if hud.has_method("occupied_gameplay_bounds"): reserved.append_array(hud.occupied_gameplay_bounds())
	var inset := Rect2(screen.position + Vector2(8, 64), screen.size - Vector2(16, 64 + 96))
	for group: Dictionary in ordered:
		var point := world * Vector2(group.at)
		var side := str(group.side)
		var tip := Vector2.ZERO
		match side:
			"left": tip = Vector2(inset.position.x, clampf(point.y, inset.position.y, inset.end.y))
			"right": tip = Vector2(inset.end.x, clampf(point.y, inset.position.y, inset.end.y))
			"top": tip = Vector2(clampf(point.x, inset.position.x + 24, inset.end.x - 24), inset.position.y)
			_: tip = Vector2(clampf(point.x, inset.position.x + 24, inset.end.x - 24), inset.end.y)
		# First free slot along the edge: in place, then up and down in steps
		# (upward first: the sky above an entry lane is usually empty).
		var step := (Vector2(0, 22) if side in ["left", "right"] else Vector2(40, 0)) * _unit
		var origin := tip
		var box := _arrow_box(tip, side)
		for attempt in 9:
			var offset := step * floorf((attempt + 1) * .5) * (-1.0 if attempt % 2 == 1 else 1.0)
			var candidate := origin + offset
			if side in ["left", "right"]: candidate.y = clampf(candidate.y, inset.position.y, inset.end.y)
			var trial := _arrow_box(candidate, side)
			var blocked := false
			for occupied in reserved:
				if trial.grow(2).intersects(occupied):
					blocked = true
					break
			tip = candidate
			box = trial
			if not blocked: break
		reserved.append(box)
		_arrow(tip.round(), side, str(group.kind), int(group.count), proximity(float(group.beyond)))
		arrows_drawn += 1

## Nearness of an off-screen group as 1..3 chevrons: three when it is about to
## enter the view, two within a short run, one further out.
const NEAR := 360.0
const MIDDLE := 900.0
static func proximity(beyond: float) -> int:
	return 3 if beyond < NEAR else (2 if beyond < MIDDLE else 1)

## The indicator's extent from its tip: up to three chevrons (CHEVRON_RUN),
## a gap and the class plate (PLATE cells of 2 units), plus the count badge
## that overhangs the plate's inner lower corner.
const PLATE := 9.0
const CHEVRON_RUN := 16.0
func _arrow_box(tip: Vector2, side: String) -> Rect2:
	var u := _unit
	var along := (CHEVRON_RUN + 2.0 + PLATE * 2.0 + 6.0) * u
	var across := PLATE * 2.0 * u
	match side:
		"left": return Rect2(tip + Vector2(0, -across * .5), Vector2(along, across + 6.0 * u))
		"right": return Rect2(tip + Vector2(-along, -across * .5), Vector2(along, across + 6.0 * u))
		"top": return Rect2(tip + Vector2(-across * .5, 0), Vector2(across + 6.0 * u, along))
	return Rect2(tip + Vector2(-across * .5, -along), Vector2(across + 6.0 * u, along))

## Design units per glyph cell over two: a cell is a whole number of real
## pixels at every window size, so the glyph stays crisp. About 3.3 design
## pixels per cell (4 real pixels at 1080p: a 28 px class glyph on a 36 px
## plate) reads from across the room; at least two real pixels in the
## smallest window.
func _glyph_unit() -> float:
	var pixels := UiArt.output_scale(self)
	if pixels <= 0.0: return 1.0
	return maxf(2.0, roundf(3.34 * pixels)) / pixels * .5

## An off-screen threat: up to three stepped chevrons in the hostile accent
## pointing off screen (more = nearer), then the class glyph on a plate framed
## in the same red, and the number of machines on an ink badge when more than
## one is out there. Every part sits on ink, so it holds on snow and sky alike.
func _arrow(tip: Vector2, side: String, kind: String, count: int, chevrons: int) -> void:
	var u := _unit
	var out := {"left": Vector2.LEFT, "right": Vector2.RIGHT, "top": Vector2.UP}.get(side, Vector2.DOWN) as Vector2
	var across := Vector2(-out.y, out.x)
	for index in chevrons:
		var point := tip - out * float(index) * 6.0 * u
		var base := point - out * 5.0 * u
		var ink := PackedVector2Array([point + out * 1.5 * u, base - out * 1.5 * u + across * 7.0 * u, base - out * 1.5 * u - across * 7.0 * u])
		draw_colored_polygon(ink, Color(UiArt.INK, .92))
		draw_colored_polygon(PackedVector2Array([point, base + across * 5.5 * u, base - across * 5.5 * u]), HOSTILE if index == 0 else HOSTILE.darkened(.12 * index))
		draw_colored_polygon(PackedVector2Array([point - out * u, base + across * 2.5 * u, base - across * 2.5 * u]), HOSTILE_LIGHT)
	var cell := 2.0 * u
	var side_length := PLATE * cell
	var plate_center := tip - out * (CHEVRON_RUN + 2.0 + PLATE) * u
	var plate := Rect2(_pixel_snap(plate_center - Vector2(side_length, side_length) * .5), Vector2(side_length, side_length))
	draw_rect(plate.grow(u), Color(UiArt.INK, .95))
	draw_rect(plate, HOSTILE)
	draw_rect(plate.grow(-u), Color(UiArt.SURFACE, .97))
	var rows: Array = GLYPHS.get(kind, GLYPHS.mech)
	var origin := plate.position + Vector2(cell, cell)
	# Machines beyond the left edge face right, toward the bunker they close on.
	var mirrored := side == "left"
	for row in rows.size():
		var line := str(rows[row])
		for column in line.length():
			var mark := line[column]
			if mark == ".": continue
			var x := (line.length() - 1 - column) if mirrored else column
			draw_rect(Rect2(origin + Vector2(x, row) * cell, Vector2(cell, cell)), HOSTILE_LIGHT if mark == "=" else UiArt.IVORY)
	if count > 1:
		var label := L.format("×%d", count)
		var font_size := roundi(9.0 * u)
		var width := UiArt.FONT.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		# The badge overhangs the plate's lower corner on the side facing in.
		var inward := -out if side in ["left", "right"] else Vector2.RIGHT
		var corner := plate.get_center() + Vector2(inward.x * side_length * .5, side_length * .5)
		var badge := Rect2(_pixel_snap(corner - Vector2(width * .5 + 3.0 * u, 6.0 * u)), Vector2(width + 6.0 * u, 10.0 * u))
		draw_rect(badge.grow(u), Color(UiArt.INK, .95))
		draw_rect(badge, HOSTILE.darkened(.35))
		draw_string(UiArt.FONT, Vector2(badge.position.x + 3.0 * u, badge.end.y - 2.5 * u).round(), label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, UiArt.IVORY)

## A design-space point on the nearest real pixel.
func _pixel_snap(point: Vector2) -> Vector2:
	var pixels := UiArt.output_scale(self)
	if pixels <= 0.0: return point.round()
	return (point * pixels).round() / pixels

func diagnostics() -> Dictionary:
	return {"covering": covering, "visible": visible, "enemies": _enemies.size(), "bars": bars_drawn, "arrows": arrows_drawn, "tracked": _state.size()}
