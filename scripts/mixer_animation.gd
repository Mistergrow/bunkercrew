extends Node2D
## The shell turns around the inclined drum axis; an audible kick can gently
## bounce its suspended drum while the cradle stays planted. This child runs on clients,
## where the authoritative production node intentionally has processing disabled.
const DRUM_SHADER := preload("res://shaders/mixer_drum.gdshader")
const SHELL_TEXTURE := preload("res://assets/machinery/mixer_shell.png")
const PADDLE_TEXTURE := preload("res://assets/machinery/mixer_paddle.png")
const DRUM_RECT := Rect2(-36, -98, 74, 65)
const TURN_RATE := 0.30
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
	var source_region: Rect2 = MachineryArt.REGIONS.mixer_drum
	var source_size := Vector2(MachineryArt.ATLAS.get_size())
	drum_material.set_shader_parameter("atlas_region", Vector4(source_region.position.x / source_size.x, source_region.position.y / source_size.y, source_region.size.x / source_size.x, source_region.size.y / source_size.y))
	drum_material.set_shader_parameter("shell_texture", SHELL_TEXTURE)
	drum_material.set_shader_parameter("has_shell", true)
	drum_material.set_shader_parameter("paddle_texture", PADDLE_TEXTURE)
	var paddle_size := Vector2(PADDLE_TEXTURE.get_size())
	drum_material.set_shader_parameter("paddle_region", Vector4(468.0 / paddle_size.x, 90.0 / paddle_size.y, 310.0 / paddle_size.x, 1071.0 / paddle_size.y))
	drum_material.set_shader_parameter("has_paddle", true)
	drum = Sprite2D.new()
	drum.name = "RotatingDrum"
	drum.texture = MachineryArt.texture("mixer_drum")
	drum.position = DRUM_RECT.get_center()
	drum.scale = DRUM_RECT.size / source_region.size
	drum.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	drum.material = drum_material
	add_child(drum)
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
	var desired_speed := TURN_RATE if bool(station.get("working")) else 0.0
	var previous_speed := angular_speed
	angular_speed = move_toward(angular_speed, desired_speed, visual_delta * (ACCELERATION if desired_speed > 0.0 else BRAKING))
	phase = fposmod(phase + (previous_speed + angular_speed) * 0.5 * visual_delta, 1.0)
	_update_material()

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

func _update_material() -> void:
	# A bounded phase, rather than shader TIME, preserves pause and an idle drum's
	# final orientation and avoids unnecessary material updates at high refresh.
	var draw_phase := floorf(phase * EFFECT_FPS / TURN_RATE) / (EFFECT_FPS / TURN_RATE)
	if is_equal_approx(draw_phase, _last_draw_phase):
		return
	_last_draw_phase = draw_phase
	drum_material.set_shader_parameter("turn_phase", draw_phase)
	uniform_updates += 1
