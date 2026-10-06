extends Control
const L := preload("res://scripts/locale_text.gd")
## A real animated landscape, quiet typography and native keyboard/controller controls.
const Scenery := preload("res://scripts/menu_scenery.gd")
const Portraits := preload("res://scripts/character_select_panel.gd")
const Progression := preload("res://scripts/menu_progression.gd")
const MODE_TITLES := ["Neues Spiel", "Lokaler Koop", "Online-Koop"]
const MODE_DETAILS := ["Beginne eine neue Solo-Schicht. Wähle Schauplatz und Crewfigur.", "Spielt mit zwei bis vier Personen an einem Rechner.", "Erstelle einen Raum oder gib einen Code ein."]
const UTILITY_DETAILS := ["Steuerung, Bunkerbau und Zusammenarbeit nachlesen.", "Ton, Anzeige, Grafik und Eingabe einstellen.", "Charakterstufen, Tänze und Erfolge ansehen."]
const STORY_DETAIL := "Das letzte Signal: zwölf Orte, persönliche Rettungen und neue Crewmitglieder. Beginne die Solo-Geschichte im Aschewerk."
const PREVIEW_DETAIL := "Die Vorschau zeigt den Schauplatz. Deine Spielauswahl bleibt unverändert."
const WORDMARK_RECT := Rect2(98, 133, 494, 59)
const WORDMARK_MAX_SCALE := 1.04
const WORDMARK_SWAY_DISTANCE := 2.2
var game
var hud
var mode_buttons: Array[Button] = []
var utility_buttons: Array[Button] = []
var quit_button: Button
var release_button: Button
var release_panel: Control
var _release_focus: Control
var preview_previous: Button
var preview_next: Button
var story_button: Button
var friends_button: Button
var continue_button: Button
var environment_index := 0
var elapsed := 0.0
var preview: Node2D
var preview_clip: Control
var decoration: Control
var wordmark: Control
var environments: Array = []
var _redraw_clock := 0.0
var _wordmark_clock := 0.0
var _wordmark_pose: Dictionary = {}
var _screen_bounds := Rect2()
var _campaign_preview: Dictionary = {}
var _resume_error := ""
var _quitting := false

func _ready() -> void:
	name = "MainMenuPanel"
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	size = Vector2(1440, 900)
	environments = ScenarioCatalog.environments(true)
	_campaign_preview = Progression.read_saved(game.campaign.save_path, game.campaign.persistence_enabled)
	var last: String = str(_campaign_preview.environment)
	for index in environments.size():
		if str(environments[index].id) == last: environment_index = index
	preview_clip = Control.new()
	preview_clip.name = "WorldPreview"
	preview_clip.clip_contents = true
	preview_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(preview_clip)
	_show_environment()
	decoration = Control.new()
	decoration.mouse_filter = Control.MOUSE_FILTER_IGNORE
	decoration.draw.connect(_draw_foreground)
	add_child(decoration)
	# Keep the original lettering on its own canvas item. Its beat response
	# never transforms the landscape, action column or any hit targets.
	wordmark = Control.new()
	wordmark.name = "BeatWordmark"
	wordmark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wordmark.position = WORDMARK_RECT.position
	wordmark.size = WORDMARK_RECT.size
	wordmark.pivot_offset = wordmark.size * 0.5
	wordmark.draw.connect(func(): UiArt.wordmark(wordmark, Rect2(Vector2.ZERO, wordmark.size)))
	decoration.add_child(wordmark)
	_apply_wordmark_pose(pose_for_menu_rhythm({}, false))
	var has_save := _has_campaign_save()
	if has_save:
		continue_button = _button("Kampagne fortsetzen", Rect2(84, 264, 458, 49), _resume_campaign, 24, "continue")
	var first_y := 320 if has_save else 282
	var actions: Array[Callable] = [hud._open_new_game, func(): hud._open_scenario_selection(2), hud._open_network]
	for index in 3:
		var button := _button(MODE_TITLES[index], Rect2(84, first_y + index * 57, 458, 49), actions[index], 24, ["new_game", "local_coop", "online_coop"][index])
		button.tooltip_text = MODE_DETAILS[index]
		mode_buttons.append(button)
	story_button = _button("Solo-Story", Rect2(84, first_y + 3 * 57, 458, 49), func(): hud._open_story_selection(1), 24, "story")
	story_button.tooltip_text = STORY_DETAIL
	var utilities: Array[Callable] = [hud._toggle_help, hud._toggle_audio, hud._toggle_personnel]
	for index in 3:
		var button := _button(["Hilfe · F1", "Optionen · F4", "Akte · P"][index], Rect2(84 + index * 156, 612, 146, 40), utilities[index], 13, ["help", "options", "personal"][index])
		button.tooltip_text = UTILITY_DETAILS[index]
		utility_buttons.append(button)
	friends_button = _button("Freunde · F7",Rect2(552,612,156,40),hud._open_social,13,"friends")
	friends_button.tooltip_text = "Freunde finden, Anfragen annehmen und gemeinsam spielen."
	quit_button = _button("Beenden", Rect2(84, 670, 146, 40), _quit_game, 16, "quit")
	quit_button.tooltip_text = "Bunkercrew schließen."
	release_button = _button("Änderungen",Rect2(250,670,235,40),_open_release_notes,16,"release_notes")
	release_button.tooltip_text = "Neue Versionen und Verbesserungen nachlesen."
	preview_previous = _button("‹", Rect2(1232, 680, 46, 42), func(): browse_environment(-1), 26, "preview_previous")
	preview_next = _button("›", Rect2(1292, 680, 46, 42), func(): browse_environment(1), 26, "preview_next")
	preview_previous.tooltip_text = "Vorherigen Schauplatz ansehen"
	preview_next.tooltip_text = "Nächsten Schauplatz ansehen"
	refresh_locale()
	_wire_focus()
	(continue_button if is_instance_valid(continue_button) else mode_buttons[0]).grab_focus.call_deferred()

func _has_campaign_save() -> bool:
	return bool(_campaign_preview.get("has_campaign", false))

func has_modal_subpanel() -> bool:
	return is_instance_valid(release_panel)

func _open_release_notes() -> void:
	if has_modal_subpanel() or _quitting: return
	_release_focus=get_viewport().gui_get_focus_owner()
	for button: Button in _ordered_buttons(): button.hide()
	release_panel=preload("res://scripts/release_notes_panel.gd").new()
	release_panel.hud=hud
	release_panel.closed.connect(_release_closed.bind(release_panel.get_instance_id()))
	release_panel.tree_exited.connect(_release_closed.bind(release_panel.get_instance_id()))
	add_child(release_panel)

func close_modal_subpanel() -> void:
	if is_instance_valid(release_panel): release_panel.close()

func _release_closed(instance_id: int) -> void:
	if not is_instance_valid(release_panel) or release_panel.get_instance_id()!=instance_id: return
	release_panel=null
	if not is_inside_tree() or is_queued_for_deletion(): return
	for button: Button in _ordered_buttons(): button.show()
	if is_instance_valid(_release_focus): _release_focus.grab_focus.call_deferred()

func _quit_game() -> void:
	if _quitting: return
	_quitting = true
	game.set_meta("quit_requested", true)
	for button: Button in _ordered_buttons(): button.disabled = true
	# Keep this menu alive while the mixer releases its native playback handles.
	# HUD shortcuts share the quit flag so they cannot replace it during drain.
	var tree := get_tree()
	if is_instance_valid(game.audio) and game.audio.has_method("drain_for_exit"):
		await game.audio.drain_for_exit()
	if is_instance_valid(tree): tree.quit()

func _resume_campaign() -> void:
	if game.expedition.resume_saved(): return
	# The checkpoint may have disappeared or become unreadable since this menu
	# was built. Keep the menu usable and show a concrete failure rather than
	# silently swallowing the button press.
	_campaign_preview = Progression.read_saved(game.campaign.save_path, game.campaign.persistence_enabled)
	_resume_error = "Der Spielstand kann gerade nicht geladen werden. Beginne eine neue Schicht."
	if is_instance_valid(continue_button):
		continue_button.disabled = not _has_campaign_save()
		if continue_button.disabled:
			_wire_focus()
			mode_buttons[0].grab_focus()
	decoration.queue_redraw()

func navigation_state() -> Dictionary:
	var focus_key := ""
	var focused := get_viewport().gui_get_focus_owner()
	if is_instance_valid(focused) and is_ancestor_of(focused):
		focus_key = str(focused.get_meta("menu_focus_key", ""))
	return {"focus": focus_key, "environment": str(environments[environment_index].id), "elapsed": elapsed}

func restore_navigation(state: Dictionary) -> void:
	if state.is_empty(): return
	var saved_environment := str(state.get("environment", ""))
	for index in environments.size():
		if str(environments[index].id) == saved_environment:
			if environment_index != index:
				environment_index = index
				_show_environment()
			break
	var saved_elapsed: Variant = state.get("elapsed", elapsed)
	if (saved_elapsed is int or saved_elapsed is float) and is_finite(float(saved_elapsed)):
		elapsed = maxf(0.0, float(saved_elapsed))
		preview.elapsed = elapsed
	var focus_key := str(state.get("focus", ""))
	for button in _ordered_buttons():
		if str(button.get_meta("menu_focus_key", "")) == focus_key:
			button.grab_focus.call_deferred()
			break
	decoration.queue_redraw()

func _process(delta: float) -> void:
	elapsed += delta
	_redraw_clock += delta
	var reduced: bool = is_instance_valid(game.weather) and game.weather.reduced_effects
	_tick_wordmark(delta, reduced)
	if _redraw_clock < 1.0 / (12.0 if reduced else 30.0): return
	_redraw_clock = 0.0
	if _screen_bounds != hud.screen_rect(): _layout_scenery()
	var unread: int=hud.social_pending_count()
	friends_button.text = L.format("Freunde · %d",unread) if unread>0 else L.text("Freunde · F7")
	decoration.queue_redraw()

static func pose_for_menu_rhythm(frame: Dictionary, reduced_motion: bool) -> Dictionary:
	var active: bool = frame.get("active", false) == true
	var pulse_value: Variant = frame.get("kick_pulse", 0.0)
	var pulse := 0.0
	if active and (pulse_value is float or pulse_value is int) and is_finite(float(pulse_value)):
		pulse = clampf(float(pulse_value), 0.0, 1.0)
	var secondary_value: Variant = frame.get("secondary_pulse", 0.0)
	var secondary_pulse := 0.0
	if active and (secondary_value is float or secondary_value is int) and is_finite(float(secondary_value)):
		secondary_pulse = clampf(float(secondary_value), 0.0, 1.0)
	# The attack/decay comes from an authored audible bassdrum. Reduced motion
	# preserves an almost imperceptible
	# ivory lift with no scaling, amber flashes or additional light effects.
	var title_scale := 1.0 if reduced_motion else lerpf(1.0, WORDMARK_MAX_SCALE, pulse)
	var title_tint := UiArt.IVORY.lerp(Color("e6e3d4"), pulse * 0.10) if reduced_motion else UiArt.IVORY.lerp(UiArt.AMBER, pulse * 0.24)
	# A simple left-to-right sway follows the actual audible decoder's beat
	# phase. It never advances on a local menu timer or moves other controls.
	var horizontal_offset := 0.0
	var phase_value: Variant = frame.get("phase", null)
	if active and not reduced_motion and (phase_value is float or phase_value is int) and is_finite(float(phase_value)):
		horizontal_offset = -cos(fposmod(float(phase_value), 1.0) * TAU) * WORDMARK_SWAY_DISTANCE
	return {"active":active, "pulse":pulse, "secondary_pulse":secondary_pulse, "vertical_offset":0.0, "horizontal_offset":horizontal_offset, "scale":title_scale, "tint":title_tint, "reduced":reduced_motion, "redraw_hz":12.0 if reduced_motion else (60.0 if active else 30.0)}

func _tick_wordmark(delta: float, reduced_effects: bool) -> void:
	if not is_instance_valid(wordmark): return
	var frame: Dictionary = {}
	var audio = game.audio if is_instance_valid(game) and "audio" in game else null
	var reduced_motion := reduced_effects
	if is_instance_valid(audio):
		if "rhythm_motion_reduced" in audio:
			reduced_motion = reduced_motion or bool(audio.rhythm_motion_reduced)
		if audio.has_method("menu_rhythm_frame"):
			var sampled: Variant = audio.menu_rhythm_frame()
			if sampled is Dictionary: frame = sampled
	var pose := pose_for_menu_rhythm(frame, reduced_motion)
	_wordmark_clock += delta
	# Restore the original title immediately after mute, calibration or leaving
	# menu playback. The next menu frame must not retain a suspended pulse.
	if not bool(pose.active) or bool(_wordmark_pose.get("reduced", false)) != reduced_motion:
		_apply_wordmark_pose(pose)
		_wordmark_clock = 0.0
		return
	if _wordmark_clock < 1.0 / float(pose.redraw_hz): return
	_wordmark_clock = fmod(_wordmark_clock, 1.0 / float(pose.redraw_hz))
	_apply_wordmark_pose(pose)

func _apply_wordmark_pose(pose: Dictionary) -> void:
	_wordmark_pose = pose
	wordmark.scale = Vector2.ONE * float(pose.scale)
	wordmark.position = WORDMARK_RECT.position + Vector2(float(pose.get("horizontal_offset", 0.0)), 0.0)
	var tint: Color = pose.tint
	# UiArt draws the unchanged ivory title. Canvas modulation adds only the
	# requested restrained accent and keeps the established font untouched.
	wordmark.modulate = Color(tint.r / UiArt.IVORY.r, tint.g / UiArt.IVORY.g, tint.b / UiArt.IVORY.b)

func wordmark_state() -> Dictionary:
	var state := _wordmark_pose.duplicate()
	if is_instance_valid(wordmark):
		state.rect = wordmark.get_transform() * Rect2(Vector2.ZERO, wordmark.size)
		state.center = wordmark.get_transform() * (wordmark.size * 0.5)
	return state

func browse_environment(direction: int) -> void:
	environment_index = posmod(environment_index + direction, environments.size())
	_show_environment()
	decoration.queue_redraw()

func _show_environment() -> void:
	if is_instance_valid(preview):
		preview_clip.remove_child(preview)
		preview.queue_free()
	preview = Scenery.new()
	preview.game = game
	preview.environment_id = str(environments[environment_index].id)
	preview_clip.add_child(preview)
	preview.elapsed = elapsed
	_layout_scenery()

func _layout_scenery() -> void:
	_screen_bounds = hud.screen_rect()
	preview_clip.position = _screen_bounds.position
	preview_clip.size = _screen_bounds.size
	# Compose each painted site around its own landmark, not the gameplay floor.
	preview.transform = preload("res://scripts/menu_composition.gd").frame(
		preview.environment_id, preview.panorama_rect, _screen_bounds)

func _button(title: String, rect: Rect2, callback: Callable, font_size: int = 24, focus_key: String = "") -> Button:
	var button := Button.new()
	button.text = title
	button.position = rect.position
	button.size = rect.size
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_override("font", UiArt.MENU_FONT if font_size >= 24 else UiArt.FONT)
	button.add_theme_font_size_override("font_size", 28 if font_size == 24 else font_size + 2)
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color.TRANSPARENT
		style.content_margin_left = 16
		style.content_margin_right = 8
		style.content_margin_top = 0
		style.content_margin_bottom = 0
		if state in ["hover", "focus", "pressed"]:
			style.border_width_left = 2
			style.border_color = UiArt.AMBER
			style.bg_color = Color(.10, .13, .12, .18)
		button.add_theme_stylebox_override(state, style)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(state, UiArt.IVORY if state == "font_color" else UiArt.AMBER)
	button.add_theme_color_override("font_disabled_color", UiArt.MUTED)
	button.pressed.connect(callback)
	button.set_meta("menu_focus_key", focus_key)
	for signal_name in ["mouse_entered", "mouse_exited", "focus_entered", "focus_exited"]:
		button.connect(signal_name, decoration.queue_redraw)
	add_child(button)
	hud.buttons.append(button)
	return button

func _ordered_buttons() -> Array[Button]:
	var ordered: Array[Button] = []
	if is_instance_valid(continue_button) and not continue_button.disabled: ordered.append(continue_button)
	ordered.append_array(mode_buttons)
	ordered.append(story_button)
	ordered.append_array(utility_buttons)
	ordered.append(friends_button)
	ordered.append(quit_button)
	ordered.append(release_button)
	ordered.append_array([preview_previous, preview_next])
	return ordered

func _wire_focus() -> void:
	var ordered := _ordered_buttons()
	for index in ordered.size():
		var current := ordered[index]
		current.focus_next = current.get_path_to(ordered[(index + 1) % ordered.size()])
		current.focus_previous = current.get_path_to(ordered[posmod(index - 1, ordered.size())])
	# Arrow keys follow the visible rows and columns. Tab retains the complete
	# linear route through all controls, including the exit action.
	var actions: Array[Button] = []
	if is_instance_valid(continue_button) and not continue_button.disabled: actions.append(continue_button)
	actions.append_array(mode_buttons)
	actions.append(story_button)
	for index in actions.size():
		var current := actions[index]
		current.focus_neighbor_top = current.get_path_to(actions[index-1] if index > 0 else utility_buttons[0])
		current.focus_neighbor_bottom = current.get_path_to(actions[index+1] if index+1 < actions.size() else utility_buttons[0])
		current.focus_neighbor_right = current.get_path_to(preview_previous)
		current.focus_neighbor_left = current.get_path_to(preview_next)
	for index in 3:
		utility_buttons[index].focus_neighbor_top = utility_buttons[index].get_path_to(story_button)
		utility_buttons[index].focus_neighbor_bottom = utility_buttons[index].get_path_to(quit_button)
		utility_buttons[index].focus_neighbor_left = utility_buttons[index].get_path_to(utility_buttons[posmod(index - 1, 3)])
		utility_buttons[index].focus_neighbor_right = utility_buttons[index].get_path_to(utility_buttons[(index + 1) % 3])
	utility_buttons[0].focus_neighbor_left = utility_buttons[0].get_path_to(friends_button)
	utility_buttons[2].focus_neighbor_right = utility_buttons[2].get_path_to(friends_button)
	friends_button.focus_neighbor_left = friends_button.get_path_to(utility_buttons[2])
	friends_button.focus_neighbor_right = friends_button.get_path_to(utility_buttons[0])
	friends_button.focus_neighbor_top = friends_button.get_path_to(story_button)
	friends_button.focus_neighbor_bottom = friends_button.get_path_to(quit_button)
	quit_button.focus_neighbor_top = quit_button.get_path_to(utility_buttons[0])
	quit_button.focus_neighbor_bottom = quit_button.get_path_to(actions[0])
	quit_button.focus_neighbor_right = quit_button.get_path_to(preview_previous)
	quit_button.focus_neighbor_left = quit_button.get_path_to(preview_next)
	preview_previous.focus_neighbor_right = preview_previous.get_path_to(preview_next)
	preview_next.focus_neighbor_left = preview_next.get_path_to(preview_previous)
	preview_previous.focus_neighbor_left = preview_previous.get_path_to(friends_button)
	preview_next.focus_neighbor_right = preview_next.get_path_to(actions[0])
	for preview_button: Button in [preview_previous, preview_next]:
		preview_button.focus_neighbor_top = preview_button.get_path_to(quit_button)
		preview_button.focus_neighbor_bottom = preview_button.get_path_to(quit_button)
	utility_buttons[2].focus_neighbor_bottom=utility_buttons[2].get_path_to(release_button)
	release_button.focus_neighbor_top=release_button.get_path_to(utility_buttons[2])
	release_button.focus_neighbor_bottom=release_button.get_path_to(actions[0])
	release_button.focus_neighbor_left=release_button.get_path_to(quit_button)
	release_button.focus_neighbor_right=release_button.get_path_to(preview_previous)

func selection_hint() -> String:
	if not _resume_error.is_empty(): return _resume_error
	var selected: Button
	for button in _ordered_buttons():
		if button.is_hovered():
			selected = button
			break
	if selected == null:
		selected = get_viewport().gui_get_focus_owner() as Button
	if selected == null or not is_ancestor_of(selected): return "Wähle deine nächste Schicht."
	if selected in mode_buttons: return MODE_DETAILS[mode_buttons.find(selected)]
	if selected == story_button: return STORY_DETAIL
	if selected == continue_button:
		var saved_environment := str(_campaign_preview.get("environment", "ash_foundry"))
		for entry: Dictionary in environments:
			if str(entry.id) == saved_environment:
				return L.format("Gesicherten Spielstand in %s fortsetzen.", L.text(str(entry.title)).capitalize())
	if selected in utility_buttons: return UTILITY_DETAILS[utility_buttons.find(selected)]
	if selected==friends_button: return "Freunde finden, Anfragen annehmen und gemeinsam spielen."
	if selected == quit_button: return "Bunkercrew schließen."
	if selected == release_button: return "Neue Versionen und Verbesserungen nachlesen."
	if selected in [preview_previous, preview_next]: return PREVIEW_DETAIL
	return "Wähle deine nächste Schicht."

func _draw() -> void:
	draw_rect(hud.screen_rect(), Color("111c20"))

func _shade(rect: Rect2, left: Color, right: Color) -> void:
	decoration.draw_polygon(PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]), PackedColorArray([left, right, right, left]))

func _landscape_text(at: Vector2, value: String, font_size: int, font: Font = UiArt.FONT) -> void:
	# Snow and reflected water can be bright behind these unframed labels.
	var translated := L.text(value)
	decoration.draw_string_outline(font, at, translated, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 2, Color(.025, .04, .04, .72))
	UiArt.text(decoration, at, translated, font_size, UiArt.IVORY, font)

func _draw_foreground() -> void:
	var bounds: Rect2 = hud.screen_rect()
	_shade(Rect2(bounds.position, Vector2(600 - bounds.position.x, bounds.size.y)), Color(.024, .040, .044, .96), Color(.024, .040, .044, .79))
	_shade(Rect2(600, bounds.position.y, 470, bounds.size.y), Color(.024, .040, .044, .79), Color(.024, .040, .044, 0))
	# Preserve the existing soft header shade over bright snow skies.
	decoration.draw_polygon(PackedVector2Array([Vector2(bounds.position.x,bounds.position.y), Vector2(bounds.end.x,bounds.position.y), Vector2(bounds.end.x,190), Vector2(bounds.position.x,190)]), PackedColorArray([Color(.025,.04,.04,.50), Color(.025,.04,.04,.50), Color(.025,.04,.04,0), Color(.025,.04,.04,0)]))
	# Local feathered shadows keep bright sky/reflections below the reading
	# contrast without dimming the full landscape or adding a rectangular panel.
	for shade: Rect2 in [Rect2(1030, -68, 490, 310), Rect2(814, 590, 624, 216)]:
		var center := shade.get_center()
		var radius := shade.size * .5
		for segment in 20:
			var start := TAU * float(segment) / 20.0
			var end := TAU * float(segment + 1) / 20.0
			decoration.draw_polygon(PackedVector2Array([center, center + Vector2(cos(start), sin(start)) * radius, center + Vector2(cos(end), sin(end)) * radius]), PackedColorArray([Color(.025,.04,.04,.68), Color(.025,.04,.04,0), Color(.025,.04,.04,0)]))
	# A soft foot vignette separates the roster without building another panel.
	decoration.draw_polygon(PackedVector2Array([Vector2(bounds.position.x, 710), Vector2(bounds.end.x, 710), bounds.end, Vector2(bounds.position.x, bounds.end.y)]), PackedColorArray([Color(.025,.04,.04,0), Color(.025,.04,.04,0), Color(.025,.04,.04,.96), Color(.025,.04,.04,.96)]))
	UiArt.text(decoration, Vector2(99, 108), "Bunker verteidigen. Gemeinsam überleben.", 16, UiArt.MUTED)
	UiArt.text(decoration, Vector2(100, 230), "Eine Mauer. Ein verlorenes Signal. Eure letzte Schicht.", 15, UiArt.MUTED)
	var hint := selection_hint()
	var lines := UiArt.wrap_text(hint, 452, 15)
	for index in lines.size(): UiArt.text(decoration, Vector2(100, 557 + index * 21), lines[index], 15, UiArt.MUTED)
	var entry: Dictionary = environments[environment_index]
	_landscape_text(Vector2(914, 666), "Schauplatz-Vorschau", 13)
	var title := L.text(str(entry.title)).capitalize()
	var title_size := 24
	while title_size > 14 and UiArt.MENU_FONT.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, title_size).x > 308: title_size -= 1
	_landscape_text(Vector2(914, 705), title, title_size, UiArt.MENU_FONT)
	UiArt.text(decoration, Vector2(100, 731), "Die Crew", 14, UiArt.MUTED)
	for index in CharacterCatalog.CHARACTERS.size():
		var character: Dictionary = CharacterCatalog.CHARACTERS[index]
		var center := Vector2(130 + index * 93, 0)
		Portraits.draw_selection_portrait(decoration, str(character.id), Rect2(center.x - 35, 744, 70, 70), elapsed)
		UiArt.centered(decoration, Vector2(center.x, 837), CharacterCatalog.selection_title(character.id), 14 if CharacterCatalog.is_unlocked(character.id) else 12, UiArt.IVORY if CharacterCatalog.is_unlocked(character.id) else UiArt.MUTED)
	UiArt.text(decoration, Vector2(100, 879), "Pfeile / Steuerkreuz: wählen · Enter / A: bestätigen", 13, UiArt.MUTED)
	UiArt.text(decoration, Vector2(1000, 879), "Space: Solo · F2: Koop", 13, UiArt.MUTED)

func refresh_locale() -> void:
	queue_redraw()
	if is_instance_valid(decoration): decoration.queue_redraw()
