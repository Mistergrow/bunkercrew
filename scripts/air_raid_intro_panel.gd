extends Control
## Presentation only. The controller owns the spawn barrier and pause lifetime.
const L := preload("res://scripts/locale_text.gd")
const Catalog := preload("res://scripts/air_raid_intro_catalog.gd")
const PoseArt := preload("res://scripts/worker_pose_art.gd")
const EquipmentArt := preload("res://scripts/support_equipment_art.gd")
const AIRCRAFT := preload("res://assets/cinematics/air_scout_top_v1.png")
const CLOUDS := preload("res://assets/cinematics/air_clouds_top_v1.png")
const CLOUD_SHADER := preload("res://shaders/air_intro_cloud.gdshader")
const REFERENCE := Vector2(1440, 900)
const VOICE_AT := 1.15

var game: Node
var hud: Node
var caption_bounds := Rect2()
var portrait_bounds := Rect2()
var skip_button: Button
var caption_label: Label
var speaker_label: Label
var voice: AudioStreamPlayer
var flyover: AudioStreamPlayer
var dialogue: Dictionary = {}
var scene_root: Node2D
var decoration: Control
var portrait_canvas: Node2D
var cloud_nodes: Array[TextureRect] = []
var cloud_specs: Array[Dictionary] = []
var aircraft_nodes: Array[Node2D] = []
var _controller: Node
var _voice_started := false
var _clock := 0.0
var _reduced := false
var _fade := 0.0
var _ui_scale := 1.0
var _layout_rect := Rect2()
var _gradient: GradientTexture2D
var _lower_shade: GradientTexture2D

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_controller = game.air_raid_intro
	_controller.began.connect(_begin)
	_controller.ended.connect(_end)
	_gradient = _make_gradient([Color("0b1925"), Color("263f52"), Color("172936")], PackedFloat32Array([0.0, 0.6, 1.0]))
	_lower_shade = _make_gradient([Color(0.015, 0.025, 0.035, 0.0), Color(0.015, 0.025, 0.035, 0.9)], PackedFloat32Array([0.0, 1.0]))
	scene_root = Node2D.new()
	add_child(scene_root)
	_create_clouds()
	for index in 3:
		var aircraft := Node2D.new()
		aircraft.z_index = 2
		aircraft.draw.connect(_draw_aircraft.bind(aircraft, index))
		scene_root.add_child(aircraft)
		aircraft_nodes.append(aircraft)
	decoration = Control.new()
	decoration.z_index = 10
	decoration.mouse_filter = Control.MOUSE_FILTER_IGNORE
	decoration.draw.connect(_draw_decoration)
	add_child(decoration)
	portrait_canvas = Node2D.new()
	portrait_canvas.z_index = 11
	portrait_canvas.draw.connect(_draw_portrait)
	add_child(portrait_canvas)
	caption_label = _label(UiArt.MENU_FONT, 25, UiArt.IVORY)
	caption_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	speaker_label = _label(UiArt.MENU_FONT, 20, UiArt.AMBER)
	skip_button = Button.new()
	skip_button.z_index = 12
	skip_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	skip_button.flat = true
	skip_button.add_theme_font_override("font", UiArt.MENU_FONT)
	for state in ["normal", "hover", "pressed", "disabled"]:
		skip_button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	var focus := StyleBoxFlat.new()
	focus.bg_color = Color(0, 0, 0, 0)
	focus.border_width_bottom = 2
	focus.border_color = UiArt.AMBER
	skip_button.add_theme_stylebox_override("focus", focus)
	skip_button.add_theme_color_override("font_color", UiArt.MUTED)
	skip_button.add_theme_color_override("font_hover_color", UiArt.IVORY)
	skip_button.add_theme_color_override("font_pressed_color", UiArt.AMBER)
	skip_button.pressed.connect(_controller.skip)
	add_child(skip_button)
	voice = AudioStreamPlayer.new()
	voice.bus = &"Voice"
	add_child(voice)
	flyover = AudioStreamPlayer.new()
	flyover.bus = &"SFX"
	add_child(flyover)
	var localization := get_node_or_null("/root/Localization")
	if localization != null: localization.locale_changed.connect(_locale_changed)
	_layout()
	if _controller.active: _begin(_controller.context)

func _make_gradient(colors: Array, offsets: PackedFloat32Array) -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray(colors)
	gradient.offsets = offsets
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 4
	texture.height = 256
	texture.fill_from = Vector2(0, 0)
	texture.fill_to = Vector2(0, 1)
	return texture

func _label(font: Font, font_size: int, tint: Color) -> Label:
	var label := Label.new()
	label.z_index = 12
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", tint)
	label.add_theme_color_override("font_shadow_color", Color(0.005, 0.01, 0.015, 0.95))
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.add_theme_constant_override("shadow_offset_x", 0)
	add_child(label)
	return label

func _create_clouds() -> void:
	# Large distant forms make a continuous cloud sea. Closer torn banks part
	# around the lead scout, then cross the escorts at a different speed.
	cloud_specs = [
		{"at":Vector2(-150, -220), "width":1020.0, "cell":0, "depth":0},
		{"at":Vector2(550, -300), "width":1200.0, "cell":1, "depth":0},
		{"at":Vector2(1190, -110), "width":1150.0, "cell":2, "depth":0},
		{"at":Vector2(-130, 500), "width":1080.0, "cell":3, "depth":0},
		{"at":Vector2(610, 620), "width":1120.0, "cell":2, "depth":0},
		{"at":Vector2(1430, 650), "width":1080.0, "cell":0, "depth":0},
		{"at":Vector2(60, 140), "width":790.0, "cell":2, "depth":1},
		{"at":Vector2(1050, -60), "width":900.0, "cell":3, "depth":1},
		{"at":Vector2(1290, 460), "width":850.0, "cell":1, "depth":1},
		{"at":Vector2(370, 810), "width":950.0, "cell":0, "depth":1},
		{"at":Vector2(390, -310), "width":810.0, "cell":1, "depth":3},
		{"at":Vector2(1540, -80), "width":1100.0, "cell":3, "depth":3},
		{"at":Vector2(-200, 560), "width":1020.0, "cell":0, "depth":3},
	]
	for index in cloud_specs.size():
		var spec: Dictionary = cloud_specs[index]
		var cloud := TextureRect.new()
		cloud.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cloud.texture = CLOUDS
		cloud.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		cloud.size = Vector2.ONE * float(spec.width)
		cloud.pivot_offset = cloud.size * 0.5
		cloud.rotation = sin(float(index) * 1.74) * 0.23
		cloud.z_index = int(spec.depth)
		var shader_material := ShaderMaterial.new()
		shader_material.shader = CLOUD_SHADER
		var cell := int(spec.cell)
		shader_material.set_shader_parameter("source_region", Vector4((cell % 2) * .5, floorf(float(cell) / 2.0) * .5, .5, .5))
		shader_material.set_shader_parameter("phase", float(index) * 1.137)
		cloud.material = shader_material
		scene_root.add_child(cloud)
		cloud_nodes.append(cloud)

func _begin(context: Dictionary) -> void:
	visible = true
	_voice_started = false
	_clock = 0.0
	_fade = 0.0
	dialogue = Catalog.line(str(context.get("character_id", "")))
	_refresh_dialogue()
	var path := "res://assets/audio/air_raid_flyover_v1.wav"
	if ResourceLoader.exists(path):
		var loop: AudioStreamWAV = load(path).duplicate()
		loop.loop_mode = AudioStreamWAV.LOOP_FORWARD
		loop.loop_begin = 0
		loop.loop_end = roundi(loop.get_length() * loop.mix_rate)
		flyover.stream = loop
		flyover.volume_db = -60.0
		flyover.play()
	_layout()
	_update_frame()

func _end(_skipped: bool) -> void:
	visible = false
	voice.stop()
	flyover.stop()
	_set_ducked(false)
	skip_button.release_focus()
	_voice_started = false

func _exit_tree() -> void:
	_set_ducked(false)

func _set_ducked(enabled: bool) -> void:
	if is_instance_valid(game) and is_instance_valid(game.audio):
		game.audio.set_dialogue_active(enabled, "air_intro")

func _locale_changed(_locale: String) -> void:
	if not visible: return
	dialogue = Catalog.line(str(_controller.context.get("character_id", "")))
	_refresh_dialogue()
	if _voice_started:
		# A language switch restarts the same person's matching recording.
		_play_voice()
		_controller.duration = maxf(float(_controller.duration), minf(12.0, _clock + float(dialogue.get("minimum_duration", 3.2)) + .7))

func _refresh_dialogue() -> void:
	caption_label.text = str(dialogue.get("text", ""))
	speaker_label.text = str(dialogue.get("speaker_name", ""))
	speaker_label.add_theme_color_override("font_color", dialogue.get("accent", UiArt.AMBER))
	skip_button.text = L.text("Überspringen · Leertaste / Enter / Esc / A")
	_layout()

func _play_voice() -> void:
	voice.stop()
	var path := str(dialogue.get("voice_path", ""))
	if path.is_empty():
		_set_ducked(false)
		return
	voice.stream = load(path)
	_set_ducked(true)
	voice.play()

func _process(_delta: float) -> void:
	if not visible: return
	if not is_instance_valid(_controller) or not _controller.active:
		_end(false)
		return
	_layout()
	_update_frame()

func _layout() -> void:
	if not is_instance_valid(hud) or not is_instance_valid(skip_button): return
	var bounds: Rect2 = hud.screen_rect()
	if bounds == _layout_rect: return
	_layout_rect = bounds
	position = bounds.position
	size = bounds.size
	var fit := maxf(size.x / REFERENCE.x, size.y / REFERENCE.y)
	scene_root.scale = Vector2.ONE * fit
	scene_root.position = (size - REFERENCE * fit) * .5
	_ui_scale = clampf(minf(size.x / REFERENCE.x, size.y / REFERENCE.y), 1.0, 1.35)
	var caption_width := minf(770.0 * _ui_scale, size.x - 280.0 * _ui_scale)
	var caption_x := (size.x - caption_width) * .5 + 46.0 * _ui_scale
	caption_bounds = Rect2(caption_x, size.y - 181.0 * _ui_scale, caption_width, 88.0 * _ui_scale)
	portrait_bounds = Rect2(caption_x - 112.0 * _ui_scale, caption_bounds.position.y - 35.0 * _ui_scale, 96.0 * _ui_scale, 112.0 * _ui_scale)
	caption_label.position = caption_bounds.position
	caption_label.size = caption_bounds.size
	caption_label.add_theme_font_size_override("font_size", roundi(26.0 * _ui_scale))
	speaker_label.position = caption_bounds.position - Vector2(0, 31.0 * _ui_scale)
	speaker_label.size = Vector2(caption_width, 29.0 * _ui_scale)
	speaker_label.add_theme_font_size_override("font_size", roundi(20.0 * _ui_scale))
	skip_button.add_theme_font_size_override("font_size", roundi(18.0 * _ui_scale))
	skip_button.size = Vector2(368, 42) * _ui_scale
	skip_button.position = Vector2(size.x - skip_button.size.x - 42 * _ui_scale, size.y - 60 * _ui_scale)

func _update_frame() -> void:
	_clock = float(_controller.elapsed)
	_reduced = is_instance_valid(game.weather) and game.weather.reduced_effects
	_fade = smoothstep(0.0, .6, _clock) * (1.0 - smoothstep(float(_controller.duration) - .7, float(_controller.duration), _clock))
	scene_root.modulate.a = _fade
	decoration.modulate.a = _fade
	var caption_alpha := smoothstep(VOICE_AT - .15, VOICE_AT + .2, _clock) * _fade
	caption_label.modulate.a = caption_alpha
	speaker_label.modulate.a = caption_alpha
	portrait_canvas.modulate.a = caption_alpha
	skip_button.visible = _clock >= .35
	skip_button.modulate.a = _fade * .86
	if _clock >= VOICE_AT and not _voice_started:
		_voice_started = true
		_play_voice()
	if _voice_started and not voice.playing: _set_ducked(false)
	flyover.volume_db = linear_to_db(maxf(.0001, _fade)) - 9.0 - (4.0 if voice.playing else 0.0)
	var tint := _environment_tint()
	for index in cloud_nodes.size():
		var spec := cloud_specs[index]
		var depth := int(spec.depth)
		var speed: float = [12.0, 28.0, 0.0, 64.0][depth]
		var motion := .3 if _reduced else 1.0
		cloud_nodes[index].position = Vector2(spec.at) - cloud_nodes[index].size * .5 + Vector2(-.28, 1) * _clock * speed * motion
		var shader_material: ShaderMaterial = cloud_nodes[index].material
		shader_material.set_shader_parameter("cloud_clock", _clock)
		shader_material.set_shader_parameter("morph_amount", .12 if _reduced else 1.0)
		var brightness := .54 if depth == 0 else .87 if depth == 1 else 1.05
		shader_material.set_shader_parameter("cloud_tint", Color(tint.r * brightness, tint.g * brightness, tint.b * brightness, .96 if depth < 3 else .91))
	for index in aircraft_nodes.size():
		var aircraft := aircraft_nodes[index]
		var lane: Vector2 = [Vector2(741, 500), Vector2(463, 674), Vector2(998, 615)][index]
		var drift := Vector2(sin(_clock * .33 + float(index)) * 27.0, -_clock * (13.0 if index == 0 else 16.0))
		aircraft.position = lane + drift * (.35 if _reduced else 1.0)
		aircraft.rotation = -.12 + sin(_clock * .4 + index * .6) * (.012 if _reduced else .052)
		aircraft.scale = Vector2.ONE * (1.0 if index == 0 else .58 if index == 1 else .49)
		aircraft.modulate = Color(1, 1, 1) if index == 0 else Color(.69, .76, .82)
		aircraft.queue_redraw()
	decoration.queue_redraw()
	portrait_canvas.queue_redraw()
	queue_redraw()

func _environment_tint() -> Color:
	var environment := str(_controller.context.get("environment", "sector07"))
	if environment in ["frozen_rail_yard", "mountain_pass"]: return Color(1.04, 1.16, 1.27)
	if environment in ["ash_foundry", "iron_canyon", "basalt_quarry"]: return Color(1.04, 1.05, 1.12)
	if environment in ["storm_dam", "flooded_power_station", "abandoned_harbor"]: return Color(.87, 1.11, 1.18)
	return Color(.95, 1.08, 1.19)

func _draw_aircraft(node: Node2D, index: int) -> void:
	# Transparent rotor wells preserve the authored frame above spinning blades.
	var extent := 362.0
	var hubs := [Vector2(-104.1, -1.1), Vector2(96.4, -1.1)]
	for side in 2:
		var hub: Vector2 = hubs[side]
		node.draw_circle(hub, 37.0, Color(.08, .12, .13, .74))
		var phase := _clock * (6.4 if _reduced else 22.0) * (1.0 if side == 0 else -1.0) + index * 2.1
		for blade in 5:
			var angle := phase + blade * TAU / 5.0
			var axis := Vector2.from_angle(angle)
			var normal := axis.orthogonal()
			var vertices := PackedVector2Array([hub + axis * 9.0 - normal * 3.0, hub + axis * 34.0 - normal * 5.0, hub + axis * 36.0 + normal * 1.0, hub + axis * 9.0 + normal * 2.0])
			node.draw_colored_polygon(vertices, Color(.3, .34, .32, .88 if _reduced else .7))
			if not _reduced: node.draw_arc(hub, 31.0, angle-.3, angle+.08, 7, Color(.57, .59, .5, .17), 3.0)
	# Own shadow is offset and restrained; it never reads as a floor beneath it.
	node.draw_texture_rect(AIRCRAFT, Rect2(Vector2(-extent*.5, -extent*.5) + Vector2(13, 22), Vector2.ONE*extent), false, Color(.02, .03, .04, .17))
	node.draw_texture_rect(AIRCRAFT, Rect2(Vector2.ONE * -extent * .5, Vector2.ONE * extent), false)
	# The small sensor breathes; no flashing full-screen warning.
	var glow := .42 + .12 * sin(_clock * 1.9 + index)
	node.draw_rect(Rect2(-6, -113, 4, 5), Color(.94, .18, .07, glow))

func _draw() -> void:
	if not visible: return
	draw_rect(Rect2(Vector2.ZERO, size), Color(.016, .039, .063, _fade))
	draw_texture_rect(_gradient, Rect2(Vector2.ZERO, size), false, Color(1, 1, 1, _fade))

func _draw_decoration() -> void:
	if not visible: return
	var lower := Rect2(0, size.y - 310 * _ui_scale, size.x, 310 * _ui_scale)
	decoration.draw_texture_rect(_lower_shade, lower, false)
	decoration.draw_rect(Rect2(0, 0, size.x, 38 * _ui_scale), Color(.008, .013, .019, .92))
	decoration.draw_rect(Rect2(0, size.y - 22 * _ui_scale, size.x, 22 * _ui_scale), Color(.008, .013, .019, .92))
	var label_pos := Vector2(52, 90) * _ui_scale
	decoration.draw_string_outline(UiArt.MENU_FONT, label_pos, L.text("LUFTKONTAKT"), HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(21 * _ui_scale), 2, Color(.015, .025, .035, _fade))
	decoration.draw_string(UiArt.MENU_FONT, label_pos, L.text("LUFTKONTAKT"), HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(21 * _ui_scale), Color(.83, .79, .65, _fade))

func _draw_portrait() -> void:
	if _clock < VOICE_AT - .15 or dialogue.is_empty(): return
	var identity := str(dialogue.get("portrait_id", ""))
	# Radio pose retains this character's real clothes, head and equipment.
	var pose := PoseArt.sample("radio_check", clampf((_clock - VOICE_AT) / 5.5, .12, .82), 0.0, Vector2(24, -13), identity)
	var portrait_scale := minf(portrait_bounds.size.x / 77.0, portrait_bounds.size.y / 77.0)
	var origin := portrait_bounds.get_center() - Vector2(38.5, 38.5) * portrait_scale
	portrait_canvas.draw_set_transform(origin + Vector2(32, 73) * portrait_scale, 0, Vector2.ONE * portrait_scale)
	if identity=="san":
		# A radio warning belongs to the actual rescue robot, never a worker
		# texture fallback for this non-character speaker ID.
		EquipmentArt.tracks(portrait_canvas,0.0)
		EquipmentArt.medic_body(portrait_canvas,sin(_clock*2.2)*.65,3.0,0,false)
	else:
		PoseArt.draw_identity_pose(portrait_canvas, pose, identity)
	portrait_canvas.draw_set_transform(Vector2.ZERO)
