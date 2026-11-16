extends Node2D
## The shell turns around the inclined drum axis; an audible kick can gently
## bounce its suspended drum while the cradle stays planted. This child runs on clients,
## where the authoritative production node intentionally has processing disabled.
const DRUM_SHADER := preload("res://shaders/mixer_drum.gdshader")
const SHELL_TEXTURE := preload("res://assets/machinery/mixer_shell.png")
const PADDLE_TEXTURE := preload("res://assets/machinery/mixer_paddle.png")
const DRUM_RECT := Rect2(-36, -98, 74, 65)
## Revolutions per second while mixing (a site mixer turns at ~25-30 rpm).
const TURN_RATE := 0.45
const ACCELERATION := 0.65
const BRAKING := 0.90
const SNAPSHOT_LEAD := 0.15
const EFFECT_FPS := 24.0
const Rhythm := preload("res://scripts/rhythm_presentation.gd")
const MAX_BEAT_BOB := 1.2

var station: Node2D
var drum: Sprite2D
var drum_material: ShaderMaterial
var phase := 0.0
var angular_speed := 0.0
var uniform_updates := 0
var rhythm_offset := Vector2.ZERO
var _visual_clock := 0.0
var _last_source_clock := 0.0
var _last_draw_phase := -1.0
## Concrete level in the mouth (0..1) and the motor's status lamp: presentation
## of the replicated working/output state, eased on the visual clock.
var fill := 0.0
var _last_fill := -1.0
var _lamp_step := -1
const FILL_RATE := 1.6
const LAMP := Vector2(-39,-31)
const LAMP_HZ := 1.25
## Pass 7A-crew: a working drum rumbles (a whole-texel bump of the suspended
## drum each time a plate seam rolls over the cradle's support roller), throws
## cement spatter out of its mouth and takes the tending worker's mallet knocks
## with a jolt and a dust puff. All of it is the drum sprite's texture offset
## (its position stays the beat bob's) and a texel-grid layer drawn above the
## drum, both pure functions of the visual clock and the turn phase.
const RUMBLE_SEAMS := 6.0
const RUMBLE_SHARE := 0.3
var rumble_offset := Vector2.ZERO
var _grit: Node2D
## The knock's puff is drawn above the crew: the mallet face is in front of
## the drum, so its contact must not hide behind the tending worker.
var _knock_layer: Node2D
var _grit_step := -1
var _knock_age := 10.0
var _knock_at := Vector2.ZERO
var _knock_side := 1.0
const KNOCK_SECONDS := 0.30
## Spatter clumps: launch point (station texels, in the mouth where the
## paddles throw the mix up), launch velocity (texels/s), period and phase (s)
## of each clump's own repeat, size. They are flung up out of the mouth, arc
## over against the wall and drop past the motor; the last two are slops that
## roll over the lower lip down the front of the shell.
const SPATTER := [
	[Vector2(-20,-72), Vector2(-30,-70), 1.13, 0.00, Vector2(2,2)],
	[Vector2(-22,-70), Vector2(-42,-58), 1.37, 0.41, Vector2(2,1)],
	[Vector2(-18,-74), Vector2(-20,-82), 1.21, 0.77, Vector2(2,2)],
	[Vector2(-21,-71), Vector2(-52,-48), 1.53, 0.18, Vector2(1,1)],
	[Vector2(-19,-73), Vector2(-36,-76), 1.07, 0.59, Vector2(2,2)],
	[Vector2(-23,-69), Vector2(-26,-62), 1.29, 0.96, Vector2(1,1)],
	[Vector2(-20,-72), Vector2(-46,-66), 1.61, 1.22, Vector2(2,1)],
	[Vector2(-27,-60), Vector2(6,2), 1.43, 0.35, Vector2(3,2)],
	[Vector2(-25,-59), Vector2(9,-3), 1.97, 1.40, Vector2(2,3)],
]
## A clump lives until it reaches the floor line or this age.
const SPATTER_LIFE := 0.9
const SPATTER_FLOOR := -4.0
const SPATTER_GRAVITY := 210.0
## Wet cement: lit top texel, body, and the darker tone it dries to falling.
const SPATTER_COLORS := [Color("dcd7c2"), Color("a6a291"), Color("7c796e")]

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	station = get_parent() as Node2D
	_visual_clock = float(station.get("elapsed"))
	_last_source_clock = _visual_clock
	# Joining an already running batch starts at a plausible mixing phase without
	# ever changing its inputs, timing, output, or the shared network schema.
	if bool(station.get("working")):
		phase = fposmod(float(station.get("production_time")) * TURN_RATE, 1.0)
		angular_speed = TURN_RATE
	drum_material = ShaderMaterial.new()
	drum_material.shader = DRUM_SHADER
	# The drum's world-texel bake (74 x 65, tools/bake_world_density_art.py):
	# one texel per world unit like the frame; the source region only as a
	# fallback. The shader re-skins it per world texel either way.
	var drum_texture: Texture2D = MachineryArt.world_texture("mixer_drum", Vector2i(DRUM_RECT.size))
	var baked := drum_texture is AtlasTexture and (drum_texture as AtlasTexture).atlas != MachineryArt.ATLAS
	var source_region: Rect2 = (drum_texture as AtlasTexture).region if drum_texture is AtlasTexture else MachineryArt.REGIONS.mixer_drum
	var source_size := Vector2((drum_texture as AtlasTexture).atlas.get_size()) if drum_texture is AtlasTexture else Vector2(MachineryArt.ATLAS.get_size())
	drum_material.set_shader_parameter("atlas_region", Vector4(source_region.position.x / source_size.x, source_region.position.y / source_size.y, source_region.size.x / source_size.x, source_region.size.y / source_size.y))
	# Room-light neighbourhood of about one world texel: one baked texel, or
	# five source pixels of the 4.35x source.
	drum_material.set_shader_parameter("light_tap", 1.0 if baked else 5.0)
	drum_material.set_shader_parameter("shell_texture", SHELL_TEXTURE)
	drum_material.set_shader_parameter("has_shell", true)
	drum_material.set_shader_parameter("paddle_texture", PADDLE_TEXTURE)
	var paddle_size := Vector2(PADDLE_TEXTURE.get_size())
	drum_material.set_shader_parameter("paddle_region", Vector4(468.0 / paddle_size.x, 90.0 / paddle_size.y, 310.0 / paddle_size.x, 1071.0 / paddle_size.y))
	drum_material.set_shader_parameter("has_paddle", true)
	drum = Sprite2D.new()
	drum.name = "RotatingDrum"
	drum.texture = drum_texture
	drum.position = DRUM_RECT.get_center()
	drum.scale = DRUM_RECT.size / source_region.size
	drum.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	drum.material = drum_material
	add_child(drum)
	# Drawn after the drum, so spatter and knock dust sit in front of it.
	_grit = Node2D.new()
	_grit.name = "Spatter"
	_grit.draw.connect(_draw_grit)
	add_child(_grit)
	_knock_layer = Node2D.new()
	_knock_layer.name = "Knock"
	_knock_layer.z_as_relative = false
	_knock_layer.z_index = 16
	_knock_layer.draw.connect(_draw_knock)
	add_child(_knock_layer)
	_update_material()

func _process(delta: float) -> void:
	if get_tree().paused:
		_set_rhythm_offset(0.0)
		return
	advance_visual(delta)

func advance_visual(delta: float) -> void:
	if not is_instance_valid(station):
		return
	_update_music_bob()
	var source_clock := float(station.get("elapsed"))
	if source_clock < _last_source_clock - 0.1 or source_clock > _visual_clock + 0.5:
		# Reloads and first full snapshots can replace the whole source clock.
		# Rebase the clock without spinning through the elapsed idle time.
		_visual_clock = source_clock
	_last_source_clock = source_clock
	var next_clock := minf(_visual_clock + maxf(delta, 0.0), source_clock + SNAPSHOT_LEAD)
	var visual_delta := clampf(next_clock - _visual_clock, 0.0, 0.1)
	_visual_clock = next_clock
	if visual_delta <= 0.0:
		return
	var loaded := bool(station.get("working")) or int(station.get("output_amount")) > 0
	fill = move_toward(fill, 1.0 if loaded else 0.0, visual_delta * FILL_RATE)
	var lamp := _lamp_state()
	if lamp != _lamp_step:
		_lamp_step = lamp
		queue_redraw()
	var desired_speed := TURN_RATE if bool(station.get("working")) else 0.0
	var previous_speed := angular_speed
	angular_speed = move_toward(angular_speed, desired_speed, visual_delta * (ACCELERATION if desired_speed > 0.0 else BRAKING))
	phase = fposmod(phase + (previous_speed + angular_speed) * 0.5 * visual_delta, 1.0)
	_knock_age += visual_delta
	_update_material()
	_update_rumble()
	var step := floori(_visual_clock * EFFECT_FPS)
	if step != _grit_step and (angular_speed > 0.0 or _knock_age < KNOCK_SECONDS or _grit_step >= 0):
		# Redraw only on a new effect frame, and once more after it all stops.
		_grit_step = step if angular_speed > 0.0 or _knock_age < KNOCK_SECONDS else -1
		if is_instance_valid(_grit): _grit.queue_redraw()
		if is_instance_valid(_knock_layer): _knock_layer.queue_redraw()

func _reduced() -> bool:
	var game = station.get("game")
	return is_instance_valid(game) and "weather" in game and is_instance_valid(game.weather) and game.weather.reduced_effects

## Whole-texel rumble of the drum: down one texel while a plate seam passes
## the support roller (six bumps a turn), and a one-texel jolt along the blow
## for a knock's first two effect frames. Held still with reduced effects.
func _update_rumble() -> void:
	var offset := Vector2.ZERO
	if not _reduced():
		var speed := angular_speed / TURN_RATE
		var seam := fposmod(floorf(phase * EFFECT_FPS / TURN_RATE) / (EFFECT_FPS / TURN_RATE) * RUMBLE_SEAMS, 1.0)
		if speed > 0.5 and seam < RUMBLE_SHARE: offset.y = 1.0
		# Every other seam also rocks the drum a texel towards the motor side.
		if speed > 0.5 and seam < RUMBLE_SHARE and posmod(floori(phase * RUMBLE_SEAMS), 2) == 1: offset.x = -1.0
		if _knock_age < 2.0 / EFFECT_FPS: offset = Vector2(_knock_side, 0.0)
	rumble_offset = offset
	if is_instance_valid(drum) and drum.offset != offset / drum.scale: drum.offset = offset / drum.scale

## A mallet blow on the drum at `global_point` (WorkerVisual's tending knock):
## the drum jolts along the blow and a puff of dust and grit leaves the
## contact. Presentation only.
func knock(global_point: Vector2, side: float = 0.0) -> void:
	_knock_at = (to_local(global_point)).round()
	# The blow's direction is the striker's facing (in this node's space).
	var along := signf((global_transform.basis_xform_inv(Vector2(side, 0.0))).x)
	_knock_side = along if along != 0.0 else (signf(_knock_at.x) if absf(_knock_at.x) > 0.5 else 1.0)
	_knock_age = 0.0
	_update_rumble()
	if is_instance_valid(_knock_layer): _knock_layer.queue_redraw()

func _draw_grit() -> void:
	var clock := floorf(_visual_clock * EFFECT_FPS) / EFFECT_FPS
	var amount := clampf(angular_speed / TURN_RATE, 0.0, 1.0) * smoothstep(0.25, 0.6, fill)
	var clumps := SPATTER.size() if not _reduced() else 2
	if amount <= 0.05: return
	for index in clumps:
		var clump: Array = SPATTER[index]
		var age := fposmod(clock + float(clump[3]), float(clump[2]))
		# Fewer clumps while the drum spins up or down.
		if age > SPATTER_LIFE or float(index) >= amount * float(clumps): continue
		var at: Vector2 = (Vector2(clump[0]) + Vector2(clump[1]) * age + Vector2(0, 0.5 * SPATTER_GRAVITY * age * age)).round()
		if at.y > SPATTER_FLOOR: continue
		var size: Vector2 = clump[4]
		# Wet body with a lit top texel, drying darker as it falls away.
		_grit.draw_rect(Rect2(at, size), SPATTER_COLORS[1 if age < 0.45 else 2])
		_grit.draw_rect(Rect2(at, Vector2.ONE), SPATTER_COLORS[0] if age < 0.45 else SPATTER_COLORS[1])

## The knock's own frames at EFFECT_FPS (in this node's space, above the
## crew): a hot contact flash with sparks, a dust puff that opens and thins
## away from the mallet, and grit specks dropping off the shell.
func _draw_knock() -> void:
	if _knock_age >= KNOCK_SECONDS: return
	var frame := floori(_knock_age * EFFECT_FPS)
	var at := _knock_at
	var back := -_knock_side
	if frame == 0:
		_knock_layer.draw_rect(Rect2(at + Vector2(-2, -2), Vector2(5, 5)), Color("d9d2b8"))
		_knock_layer.draw_rect(Rect2(at + Vector2(-1, -1), Vector2(3, 3)), Color("fff4d2"))
	elif frame == 1:
		_knock_layer.draw_rect(Rect2(at + Vector2(-1, -1), Vector2(3, 3)), Color("bdb69e"))
		_knock_layer.draw_rect(Rect2(at, Vector2.ONE), Color("fff4d2"))
	if frame <= 2:
		var reach := 3.0 + float(frame) * 2.0
		_knock_layer.draw_rect(Rect2(at + Vector2(back * reach, -reach), Vector2.ONE), Color("ffcf6e"))
		_knock_layer.draw_rect(Rect2(at + Vector2(back * (reach - 1.0), reach * 0.5), Vector2.ONE), Color("ffcf6e"))
		_knock_layer.draw_rect(Rect2(at + Vector2(_knock_side * reach * 0.5, -reach - 1.0), Vector2.ONE), Color("ffe3a0"))
	if frame >= 1 and frame <= 6:
		# Three clumps of dust open up and back from the contact, then thin.
		var spread := float(frame) + 1.0
		var dust := Color("aea893") if frame <= 3 else Color("88847a")
		var size := Vector2(3, 2) if frame <= 2 else (Vector2(2, 2) if frame <= 4 else Vector2.ONE)
		_knock_layer.draw_rect(Rect2(at + Vector2(back * spread - 1.0, -spread - 1.0), size), dust)
		_knock_layer.draw_rect(Rect2(at + Vector2(back * (spread + 2.0), 1.0 - spread * 0.5), size), dust)
		_knock_layer.draw_rect(Rect2(at + Vector2(_knock_side * 1.0, -spread * 1.5 - 2.0), size), dust)
	var age := float(frame) / EFFECT_FPS
	for speck in 4:
		if frame < 1: break
		var drop := Vector2(back * (2.0 + speck * 2.0) * (1.0 + float(frame)), 0.5 * SPATTER_GRAVITY * age * age + float(speck))
		_knock_layer.draw_rect(Rect2((at + drop).round(), Vector2(2, 1) if speck == 0 else Vector2.ONE), SPATTER_COLORS[1 + speck % 2])

func _update_music_bob() -> void:
	var frame := Rhythm.frame_for(station)
	var bob := 0.0
	var music_bus := AudioServer.get_bus_index("Music")
	var muted := AudioServer.is_bus_mute(0) or (music_bus >= 0 and AudioServer.is_bus_mute(music_bus))
	var game = station.get("game")
	var effects_reduced: bool = is_instance_valid(game) and "weather" in game and is_instance_valid(game.weather) and game.weather.reduced_effects
	if not get_tree().paused and not muted and not effects_reduced and bool(frame.get("active", false)) and not bool(frame.get("reduced_motion", false)):
		var timestamp := float(frame.get("kick_timestamp", -INF))
		var heard := float(frame.get("audible_seconds", -1.0))
		var age := heard - timestamp
		if is_finite(timestamp) and age >= 0.0 and age < 0.45:
			var strength := clampf(float(frame.get("kick_strength", 0.0)) / 0.8, 0.0, 1.0)
			# A small spring response settles down, rebounds up and returns to its
			# fixed bearing. Its source is a heard drum hit, never shader TIME.
			bob = clampf(sin(age * TAU / 0.32) * exp(-age / 0.18) * 1.7 * strength, -MAX_BEAT_BOB, MAX_BEAT_BOB)
	_set_rhythm_offset(bob)

func _set_rhythm_offset(offset_y: float) -> void:
	rhythm_offset = Vector2(0.0, offset_y)
	if is_instance_valid(drum):
		var target := DRUM_RECT.get_center() + rhythm_offset
		if drum.position != target: drum.position = target

## 0 off, 1 working (bright), 2 working (dim), 3 output ready. The working
## lamp steps between two levels at LAMP_HZ, never on/off; reduced effects
## hold it steady.
func _lamp_state() -> int:
	if int(station.get("output_amount")) > 0: return 3
	if not bool(station.get("working")): return 0
	var game = station.get("game")
	var quiet: bool = is_instance_valid(game) and "weather" in game and is_instance_valid(game.weather) and game.weather.reduced_effects
	if quiet: return 1
	return 1 if fposmod(_visual_clock * LAMP_HZ, 1.0) < 0.5 else 2

func _draw() -> void:
	# Indicator in the motor housing's window: whole texels, dark when idle.
	var lit: Color = Color("2a2117")
	match _lamp_step:
		1: lit = Color("ffb347")
		2: lit = Color("b8662a")
		3: lit = Color("7fd6c8")
	draw_rect(Rect2(LAMP - Vector2(2, 2), Vector2(5, 5)), Color("15130f"))
	draw_rect(Rect2(LAMP - Vector2(1, 1), Vector2(3, 3)), lit)
	if _lamp_step in [1, 3]:
		draw_rect(Rect2(LAMP - Vector2(1, 1), Vector2.ONE), Color(1, 0.95, 0.8))

func _update_material() -> void:
	# A bounded phase, rather than shader TIME, preserves pause and an idle drum's
	# final orientation and avoids unnecessary material updates at high refresh.
	var draw_fill := snappedf(fill, 0.125)
	if draw_fill != _last_fill:
		_last_fill = draw_fill
		drum_material.set_shader_parameter("fill", draw_fill)
	var draw_phase := floorf(phase * EFFECT_FPS / TURN_RATE) / (EFFECT_FPS / TURN_RATE)
	if is_equal_approx(draw_phase, _last_draw_phase):
		return
	_last_draw_phase = draw_phase
	drum_material.set_shader_parameter("turn_phase", draw_phase)
	uniform_updates += 1
