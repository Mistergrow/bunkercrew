class_name ScenarioSelectPanel
extends Control
const L := preload("res://scripts/locale_text.gd")
const Scenery := preload("res://scripts/menu_scenery.gd")
## Choose a real landscape first; the controls sit quietly over that same world.
const LOCATION_RECT := Rect2(82, 210, 388, 49)
const CONFIGURATION_X := 1024.0
var game
var hud
var options: Dictionary
var cards: Array[Button] = []
var next_button: Button
var story_button: Button
var classic_button: Button
var back_button: Button
var environments: Array = []
var preview: Node2D
var preview_clip: Control
var decoration: Control
var construction_preview: Control
var position_preview: Control
var elapsed := 0.0
var _screen_bounds := Rect2()
var _layout_clock := 0.0

func _ready() -> void:
	name = "ScenarioSelectPanel"
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	size = Vector2(1440, 900)
	options = ScenarioCatalog.validate(ScenarioCatalog.last_selection)
	environments = ScenarioCatalog.environments()
	if not environments.any(func(entry): return entry.id == options.environment):
		options.environment = environments[0].id
	preview_clip = Control.new()
	preview_clip.name = "SelectedWorld"
	preview_clip.clip_contents = true
	preview_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(preview_clip)
	_show_environment()
	decoration = Control.new()
	decoration.name = "ReadingGradients"
	decoration.mouse_filter = Control.MOUSE_FILTER_IGNORE
	decoration.draw.connect(_draw_foreground)
	add_child(decoration)
	construction_preview = Control.new()
	construction_preview.name = "ActualBunkerCutaway"
	construction_preview.position = Vector2(CONFIGURATION_X + 18, 232)
	construction_preview.size = Vector2(300, 109)
	construction_preview.clip_contents = true
	construction_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	construction_preview.draw.connect(_draw_construction)
	add_child(construction_preview)
	position_preview = Control.new()
	position_preview.name = "BunkerPositionPreview"
	position_preview.position = Vector2(CONFIGURATION_X + 18, 547)
	position_preview.size = Vector2(300, 57)
	position_preview.clip_contents = true
	position_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	position_preview.draw.connect(_draw_position)
	add_child(position_preview)
	for index in environments.size():
		var entry: Dictionary = environments[index]
		var rect := LOCATION_RECT
		rect.position.y += index * LOCATION_RECT.size.y
		var choice := _button(str(entry.title).capitalize(), rect, func(): choose("environment", str(entry.id)), 22, 35)
		choice.tooltip_text = str(entry.get("detail", entry.title))
		choice.set_meta("choice_key", "environment")
		choice.set_meta("choice_value", str(entry.id))
		choice.draw.connect(func(): _draw_location(choice, index))
		cards.append(choice)
	for index in ScenarioCatalog.BUILD_TYPES.size():
		var entry: Dictionary = ScenarioCatalog.BUILD_TYPES[index]
		var choice := _button(L.text(str(entry.title)).capitalize(), Rect2(CONFIGURATION_X, 350 + index * 58, 334, 54), func(): choose("build_type", str(entry.id)), 19, 18, 20)
		choice.tooltip_text = L.text(str(entry.detail))
		choice.set_meta("choice_key", "build_type")
		choice.set_meta("choice_value", str(entry.id))
		choice.draw.connect(func(): _draw_detail(choice, str(entry.detail)))
		cards.append(choice)
	for index in ScenarioCatalog.POSITIONS.size():
		var entry: Dictionary = ScenarioCatalog.POSITIONS[index]
		var choice := _button(L.text(str(entry.title)).capitalize(), Rect2(CONFIGURATION_X, 610 + index * 45, 334, 44), func(): choose("position", str(entry.id)), 19, 18, 16)
		choice.tooltip_text = L.text(str(entry.detail))
		choice.set_meta("choice_key", "position")
		choice.set_meta("choice_value", str(entry.id))
		choice.draw.connect(func(): _draw_detail(choice, str(entry.detail), 39))
		cards.append(choice)
	back_button = _button("Zurück  ·  Esc / B", Rect2(82, 802, 242, 48), hud._close_scenario_selection, 17)
	classic_button = _button("Klassischer Bunker", Rect2(346, 802, 268, 48), _classic, 17)
	classic_button.visible = not (hud.has_method("_online") and hud._online())
	story_button = _button("", Rect2(CONFIGURATION_X, 95, 334, 43), _toggle_story, 16)
	next_button = _button("Zurück zum Online-Raum" if hud.has_method("_online") and hud._online() else "Weiter zur Figurenwahl", Rect2(1006, 796, 370, 58), confirm, 22)
	_update_story_button()
	_update_choices()
	_wire_focus()
	# Returning from character selection keeps both the choice and the focus.
	for index in environments.size():
		if str(environments[index].id) == str(options.environment):
			cards[index].grab_focus.call_deferred()
			break

func _classic() -> void:
	hud.story_selected = false
	hud.scenario_selected = false
	game.story_mode = false
	hud._open_character_selection(hud.selection_count)

func choose(key: String, value: String) -> void:
	var world_changed := key == "environment" and str(options.environment) != value
	options[key] = value
	ScenarioCatalog.last_selection = options.duplicate()
	if world_changed: _show_environment()
	_update_choices()
	construction_preview.queue_redraw()
	position_preview.queue_redraw()
	decoration.queue_redraw()

func _toggle_story() -> void:
	hud.story_selected = not hud.story_selected
	_update_story_button()
	decoration.queue_redraw()

func _update_story_button() -> void:
	story_button.text = L.text("Geschichte: Das letzte Signal" if hud.story_selected else "Freie Schicht")
	story_button.tooltip_text = L.text("Story auch im Koop in der Schauplatzauswahl aktivieren.")
	story_button.add_theme_color_override("font_color", UiArt.AMBER if hud.story_selected else UiArt.IVORY)

func confirm() -> void:
	hud.scenario_options = ScenarioCatalog.validate(options)
	hud.scenario_selected = true
	if hud.has_method("_online") and hud._online():
		hud.overlay = "network"
	else:
		hud._open_character_selection(hud.selection_count)

func _button(title: String, rect: Rect2, callback: Callable, font_size: int = 18, inset: float = 18.0, bottom_inset: float = 0.0) -> Button:
	var result := Button.new()
	result.text = L.text(title)
	result.position = rect.position
	result.size = rect.size
	result.alignment = HORIZONTAL_ALIGNMENT_LEFT
	result.focus_mode = Control.FOCUS_ALL
	result.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	result.add_theme_font_override("font", UiArt.MENU_FONT if font_size >= 22 else UiArt.FONT)
	result.add_theme_font_size_override("font_size", font_size)
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color.TRANSPARENT
		style.content_margin_left = inset
		style.content_margin_right = 8
		style.content_margin_bottom = bottom_inset
		if state in ["focus", "pressed"]:
			style.border_width_bottom = 1
			style.border_color = Color(UiArt.AMBER, .65)
		result.add_theme_stylebox_override(state, style)
	result.add_theme_color_override("font_color", UiArt.IVORY)
	for state in ["font_hover_color", "font_pressed_color", "font_focus_color"]:
		result.add_theme_color_override(state, UiArt.AMBER)
	result.add_theme_color_override("font_disabled_color", UiArt.MUTED)
	result.pressed.connect(callback)
	add_child(result)
	return result

func _update_choices() -> void:
	for choice in cards:
		var selected := _is_selected(choice)
		choice.add_theme_color_override("font_color", UiArt.AMBER if selected else UiArt.IVORY)
		choice.queue_redraw()

func _is_selected(choice: Button) -> bool:
	return str(options.get(str(choice.get_meta("choice_key", "")), "")) == str(choice.get_meta("choice_value", ""))

func _draw_selected(choice: Button, height: float = 18.0) -> void:
	if _is_selected(choice):
		choice.draw_rect(Rect2(0, (choice.size.y - height) * .5, 2, height), UiArt.AMBER)

func _draw_location(choice: Button, index: int) -> void:
	_draw_selected(choice)
	UiArt.text(choice, Vector2(10, 30), "%02d" % (index + 1), 11, UiArt.AMBER if _is_selected(choice) else UiArt.MUTED)

func _draw_detail(choice: Button, detail: String, baseline: float = 44.0) -> void:
	_draw_selected(choice, 26)
	UiArt.text(choice, Vector2(18, baseline), detail, 13, UiArt.MUTED)

func _draw_construction() -> void:
	# The exact gameplay assembly gives each material an honest, detailed preview.
	# One selected room replaces three postage-stamp wall samples.
	construction_preview.draw_set_transform(Vector2(0, 5), 0, Vector2.ONE * .46875)
	ScenarioBunkerArt.draw_room(construction_preview, Rect2(0, 0, 640, 185), str(options.build_type), 0, elapsed)
	construction_preview.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)

func _draw_position() -> void:
	# Keep the same material assembly as the large cutaway. The overview frames
	# the initial 1440-unit arena; spawn approaches continue beyond its edges.
	var scale_factor := position_preview.size.x / 1440.0
	var bunker_left := roundf(ScenarioBunker.position_origin(str(options.position)) * scale_factor)
	var bunker_right := bunker_left + roundf(ScenarioRoomCatalog.ROOM_WIDTH * scale_factor)
	position_preview.draw_rect(Rect2(0, 52, 300, 5), Color("262e2c"))
	position_preview.draw_rect(Rect2(0, 52, 300, 1), Color("788071"))
	for index in 25:
		var x := float((index * 47 + 13) % 296)
		position_preview.draw_rect(Rect2(x, 54 + index % 2, 2 + index % 3, 1), Color("41483f"))
	position_preview.draw_set_transform(Vector2(bunker_left, 10), 0, Vector2.ONE * scale_factor)
	ScenarioBunkerArt.draw_room(position_preview, Rect2(0, 0, ScenarioRoomCatalog.ROOM_WIDTH, 185), str(options.build_type))
	position_preview.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	# A small roof flag identifies the bunker without an additional UI label.
	position_preview.draw_rect(Rect2(bunker_left + 7, 1, 1, 9), Color("8b8069"))
	position_preview.draw_rect(Rect2(bunker_left + 8, 1, 8, 4), UiArt.AMBER)
	position_preview.draw_rect(Rect2(bunker_left + 8, 4, 5, 1), Color("836846"))
	if str(options.position) != "left":
		_draw_approach(Vector2(bunker_left - 11, 42), 1, bunker_left - 11)
	if str(options.position) != "right":
		_draw_approach(Vector2(bunker_right + 11, 42), -1, 300 - bunker_right - 11)

func _draw_approach(tip: Vector2, direction: int, space: float) -> void:
	var length := minf(36, space - 5)
	position_preview.draw_rect(Rect2(tip.x - length if direction > 0 else tip.x, tip.y, length, 2), Color(UiArt.AMBER, .75))
	for step in 5:
		position_preview.draw_rect(Rect2(tip.x - direction * step, tip.y - step, 1, 2), UiArt.AMBER)
		position_preview.draw_rect(Rect2(tip.x - direction * step, tip.y + step, 1, 2), UiArt.AMBER)

func _wire_focus() -> void:
	var location_count := environments.size()
	var ordered: Array[Button] = cards.slice(0, location_count)
	ordered.append(story_button)
	ordered.append_array(cards.slice(location_count))
	ordered.append(back_button)
	if classic_button.visible: ordered.append(classic_button)
	ordered.append(next_button)
	for index in ordered.size():
		var choice := ordered[index]
		choice.focus_next = choice.get_path_to(ordered[(index + 1) % ordered.size()])
		choice.focus_previous = choice.get_path_to(ordered[posmod(index - 1, ordered.size())])
	var configuration: Array[Button] = [story_button]
	configuration.append_array(cards.slice(location_count))
	var configuration_rows: Array[Button] = cards.slice(location_count)
	var location_rows: Array[Button] = cards.slice(0, location_count)
	for index in location_count:
		var choice := cards[index]
		choice.focus_neighbor_top = choice.get_path_to(cards[index - 1] if index > 0 else back_button)
		choice.focus_neighbor_bottom = choice.get_path_to(cards[index + 1] if index + 1 < location_count else back_button)
		var across := _closest_row(choice, configuration_rows)
		choice.focus_neighbor_right = choice.get_path_to(across)
		choice.focus_neighbor_left = choice.get_path_to(across)
	for index in configuration.size():
		var choice := configuration[index]
		choice.focus_neighbor_top = choice.get_path_to(configuration[index - 1] if index > 0 else next_button)
		choice.focus_neighbor_bottom = choice.get_path_to(configuration[index + 1] if index + 1 < configuration.size() else next_button)
		var location := _closest_row(choice, location_rows)
		choice.focus_neighbor_left = choice.get_path_to(location)
		choice.focus_neighbor_right = choice.get_path_to(location)
	var footer: Array[Button] = [back_button]
	if classic_button.visible: footer.append(classic_button)
	footer.append(next_button)
	for index in footer.size():
		var choice := footer[index]
		choice.focus_neighbor_left = choice.get_path_to(footer[posmod(index - 1, footer.size())])
		choice.focus_neighbor_right = choice.get_path_to(footer[(index + 1) % footer.size()])
		choice.focus_neighbor_top = choice.get_path_to(cards.back() if choice == next_button else cards[location_count - 1])
		choice.focus_neighbor_bottom = choice.get_path_to(cards[0])

func _closest_row(origin: Button, rows: Array[Button]) -> Button:
	var nearest := rows[0]
	var origin_y := origin.get_rect().get_center().y
	var distance := absf(nearest.get_rect().get_center().y - origin_y)
	for candidate in rows:
		var candidate_distance := absf(candidate.get_rect().get_center().y - origin_y)
		if candidate_distance < distance:
			nearest = candidate
			distance = candidate_distance
	return nearest

func _show_environment() -> void:
	if is_instance_valid(preview):
		preview_clip.remove_child(preview)
		preview.queue_free()
	preview = Scenery.new()
	preview.name = "ScenarioLandscape"
	preview.game = game
	preview.environment_id = str(options.environment)
	preview_clip.add_child(preview)
	preview.elapsed = elapsed
	_layout_scenery()

func _layout_scenery() -> void:
	_screen_bounds = hud.screen_rect()
	preview_clip.position = _screen_bounds.position
	preview_clip.size = _screen_bounds.size
	preview.transform = preload("res://scripts/menu_composition.gd").frame(preview.environment_id, preview.panorama_rect, _screen_bounds)
	if is_instance_valid(decoration): decoration.queue_redraw()

func _process(delta: float) -> void:
	elapsed += delta
	_layout_clock += delta
	if _layout_clock < .1: return
	_layout_clock = fmod(_layout_clock, .1)
	if _screen_bounds != hud.screen_rect(): _layout_scenery()
	construction_preview.queue_redraw()

func _draw() -> void:
	draw_rect(hud.screen_rect(), Color("111c20"))

func _shade(rect: Rect2, left: Color, right: Color) -> void:
	decoration.draw_polygon(PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]), PackedColorArray([left, right, right, left]))

func _draw_foreground() -> void:
	var bounds: Rect2 = hud.screen_rect()
	var ink := Color(.024, .040, .044)
	# Continuous gradients keep both text columns readable while the landscape
	# remains the page itself. No panel outline or repeated card backplates.
	_shade(Rect2(bounds.position, Vector2(420 - bounds.position.x, bounds.size.y)), Color(ink, .94), Color(ink, .87))
	_shade(Rect2(420, bounds.position.y, 330, bounds.size.y), Color(ink, .87), Color(ink, 0))
	_shade(Rect2(890, bounds.position.y, 210, bounds.size.y), Color(ink, 0), Color(ink, .86))
	_shade(Rect2(1100, bounds.position.y, bounds.end.x - 1100, bounds.size.y), Color(ink, .86), Color(ink, .94))
	decoration.draw_polygon(PackedVector2Array([bounds.position, Vector2(bounds.end.x, bounds.position.y), Vector2(bounds.end.x, 188), Vector2(bounds.position.x, 188)]), PackedColorArray([Color(ink, .74), Color(ink, .74), Color(ink, 0), Color(ink, 0)]))
	decoration.draw_polygon(PackedVector2Array([Vector2(bounds.position.x, 542), Vector2(bounds.end.x, 542), bounds.end, Vector2(bounds.position.x, bounds.end.y)]), PackedColorArray([Color(ink, 0), Color(ink, 0), Color(ink, .96), Color(ink, .96)]))
	UiArt.text(decoration, Vector2(100, 120), "Plane deine Schicht", 34, UiArt.IVORY, UiArt.MENU_FONT)
	UiArt.text(decoration, Vector2(100, 188), "Schauplatz", 13, UiArt.MUTED)
	UiArt.text(decoration, Vector2(CONFIGURATION_X + 18, 201), "Bauart", 13, UiArt.MUTED)
	UiArt.text(decoration, Vector2(CONFIGURATION_X + 18, 536), "Position im Gelände", 13, UiArt.MUTED)
	if str(options.position) == "center":
		var attack_detail := UiArt.wrap_text("Mittellage: gleiche Gesamtzahl an Gegnern, auf zwei Fronten verteilt.", 316, 10)
		for line in mini(attack_detail.size(), 2): UiArt.text(decoration, Vector2(CONFIGURATION_X + 18, 755 + line * 13), attack_detail[line], 10, UiArt.MUTED)
	var story_detail := UiArt.wrap_text("Story: Mauerbau, Funkaufträge und 20 Wellen.", 316, 13)
	for line in mini(story_detail.size(), 2): UiArt.text(decoration, Vector2(CONFIGURATION_X + 18, 157 + line * 17), story_detail[line], 13, UiArt.MUTED)
	var selected: Dictionary = ScenarioCatalog.environment(str(options.environment))
	var location_number := 0
	for index in environments.size():
		if str(environments[index].id) == str(options.environment): location_number = index + 1
	UiArt.text(decoration, Vector2(540, 617), "%02d / %02d" % [location_number, environments.size()], 12, UiArt.MUTED)
	var title := L.text(str(selected.title)).capitalize()
	var title_size := 29
	while title_size > 18 and UiArt.MENU_FONT.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, title_size).x > 442: title_size -= 1
	UiArt.text(decoration, Vector2(538, 655), title, title_size, UiArt.IVORY, UiArt.MENU_FONT)
	var detail := UiArt.wrap_text(str(selected.get("detail", "")), 396, 13)
	for line in mini(detail.size(), 4): UiArt.text(decoration, Vector2(540, 684 + line * 18), detail[line], 13, UiArt.MUTED)
	UiArt.text(decoration, Vector2(100, 713), "Du beginnst mit einem Raum.", 14, UiArt.IVORY)
	UiArt.text(decoration, Vector2(100, 737), "Weitere Räume kosten Beton und Stahl.", 11, UiArt.MUTED)
	# A single quiet footer rule establishes the action hierarchy.
	decoration.draw_line(Vector2(100, 781), Vector2(1358, 781), Color(UiArt.MUTED, .18), 1)
	UiArt.text(decoration, Vector2(100, 879), "Pfeile / Steuerkreuz: wählen · Enter / A: bestätigen", 12, UiArt.MUTED)

func refresh_locale() -> void:
	environments = ScenarioCatalog.environments()
	for index in environments.size():
		cards[index].text = L.text(str(environments[index].title)).capitalize()
		cards[index].tooltip_text = L.text(str(environments[index].get("detail", environments[index].title)))
	for index in ScenarioCatalog.BUILD_TYPES.size():
		cards[environments.size() + index].text = L.text(str(ScenarioCatalog.BUILD_TYPES[index].title)).capitalize()
		cards[environments.size() + index].tooltip_text = L.text(str(ScenarioCatalog.BUILD_TYPES[index].detail))
	for index in ScenarioCatalog.POSITIONS.size():
		cards[environments.size() + ScenarioCatalog.BUILD_TYPES.size() + index].text = L.text(str(ScenarioCatalog.POSITIONS[index].title)).capitalize()
		cards[environments.size() + ScenarioCatalog.BUILD_TYPES.size() + index].tooltip_text = L.text(str(ScenarioCatalog.POSITIONS[index].detail))
	back_button.text = L.text("Zurück  ·  Esc / B")
	classic_button.text = L.text("Klassischer Bunker")
	next_button.text = L.text("Zurück zum Online-Raum" if hud.has_method("_online") and hud._online() else "Weiter zur Figurenwahl")
	_update_story_button()
	_update_choices()
	decoration.queue_redraw()
