class_name SocialUiArt
extends RefCounted
## Shared quiet menu controls and original pixel glyphs for social screens.
const Scenery := preload("res://scripts/menu_scenery.gd")
static var _icons: Dictionary = {}

static func icon(id: String) -> Texture2D:
	if _icons.has(id): return _icons[id]
	var path := "res://assets/ui/social/%s.png" % id
	var result: Texture2D
	if ResourceLoader.exists(path): result = load(path)
	elif FileAccess.file_exists(path): result = ImageTexture.create_from_image(Image.load_from_file(path))
	if result != null: _icons[id] = result
	return result

static func button(control: Button, font_size: int = 18, glyph: String = "", inset: float = 16.0, bottom_inset: float = 0.0) -> void:
	control.alignment = HORIZONTAL_ALIGNMENT_LEFT
	control.focus_mode = Control.FOCUS_ALL
	control.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	control.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	control.add_theme_font_override("font", UiArt.MENU_FONT if font_size >= 22 else UiArt.FONT)
	control.add_theme_font_size_override("font_size", font_size)
	control.add_theme_constant_override("h_separation", 12)
	if not glyph.is_empty(): control.icon = icon(glyph)
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color.TRANSPARENT
		style.content_margin_left = inset
		style.content_margin_right = 8
		style.content_margin_bottom = bottom_inset
		if state in ["pressed", "focus"]:
			style.border_width_bottom = 1
			style.border_color = Color(UiArt.AMBER, .55)
		control.add_theme_stylebox_override(state, style)
	control.add_theme_color_override("font_color", UiArt.IVORY)
	control.add_theme_color_override("icon_normal_color", UiArt.MUTED)
	for state in ["font_hover_color", "font_pressed_color", "font_focus_color", "icon_hover_color", "icon_pressed_color", "icon_focus_color"]:
		control.add_theme_color_override(state, UiArt.AMBER)
	control.add_theme_color_override("font_disabled_color", Color(UiArt.MUTED, .56))
	control.add_theme_color_override("icon_disabled_color", Color(UiArt.MUTED, .4))

static func field(control: LineEdit, font_size: int = 17) -> void:
	control.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	control.add_theme_font_override("font", UiArt.FONT)
	control.add_theme_font_size_override("font_size", font_size)
	control.add_theme_color_override("font_color", UiArt.IVORY)
	control.add_theme_color_override("caret_color", UiArt.AMBER)
	control.add_theme_color_override("selection_color", Color(UiArt.AMBER, .3))
	for state in ["normal", "focus", "read_only"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(.024, .040, .044, .24)
		style.border_width_bottom = 1
		style.border_color = UiArt.AMBER if state == "focus" else Color(UiArt.MUTED, .3)
		style.content_margin_left = 12
		style.content_margin_right = 12
		control.add_theme_stylebox_override(state, style)

static func popup(menu: PopupMenu) -> void:
	menu.add_theme_font_override("font", UiArt.FONT)
	menu.add_theme_font_size_override("font_size", 16)
	menu.add_theme_color_override("font_color", UiArt.IVORY)
	menu.add_theme_color_override("font_hover_color", UiArt.AMBER)
	menu.add_theme_constant_override("v_separation", 13)
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color("111c1f")
	panel.content_margin_left = 14
	panel.content_margin_right = 14
	panel.content_margin_top = 10
	panel.content_margin_bottom = 10
	menu.add_theme_stylebox_override("panel", panel)
	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(.36, .30, .19, .25)
	menu.add_theme_stylebox_override("hover", hover)

static func bounds(hud: Node) -> Rect2:
	return hud.screen_rect() if hud.has_method("screen_rect") else Rect2(0, 0, 1440, 900)

static func create_landscape(parent: Control, game: Node, hud: Node, environment: String) -> Dictionary:
	var state := {"preview":null, "clip":null, "environment":environment, "bounds":Rect2()}
	# Small UI probes do not have the full world services required by scenery.
	if "weather" in game and hud.has_method("screen_rect"):
		var clip := Control.new()
		clip.name = "SocialLandscape"
		clip.clip_contents = true
		clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.add_child(clip)
		state.clip = clip
		var preview := Scenery.new()
		preview.game = game
		preview.environment_id = environment
		clip.add_child(preview)
		state.preview = preview
		layout_landscape(state, hud)
	return state

static func layout_landscape(state: Dictionary, hud: Node) -> void:
	if not is_instance_valid(state.get("preview")): return
	var screen := bounds(hud)
	state.bounds = screen
	state.clip.position = screen.position
	state.clip.size = screen.size
	state.preview.transform = preload("res://scripts/menu_composition.gd").frame(str(state.environment), state.preview.panorama_rect, screen)

static func reading_shade(node: CanvasItem, screen: Rect2, left_end: float = 460.0, right_start: float = 990.0) -> void:
	var ink := Color(.024, .040, .044)
	_gradient(node, Rect2(screen.position, Vector2(left_end - screen.position.x, screen.size.y)), Color(ink, .95), Color(ink, .84))
	_gradient(node, Rect2(left_end, screen.position.y, 310, screen.size.y), Color(ink, .84), Color(ink, 0))
	_gradient(node, Rect2(right_start - 190, screen.position.y, 220, screen.size.y), Color(ink, 0), Color(ink, .84))
	_gradient(node, Rect2(right_start + 30, screen.position.y, screen.end.x - right_start - 30, screen.size.y), Color(ink, .84), Color(ink, .95))
	node.draw_polygon(PackedVector2Array([screen.position, Vector2(screen.end.x, screen.position.y), Vector2(screen.end.x, 205), Vector2(screen.position.x, 205)]), PackedColorArray([Color(ink, .72), Color(ink, .72), Color(ink, 0), Color(ink, 0)]))
	node.draw_polygon(PackedVector2Array([Vector2(screen.position.x, 655), Vector2(screen.end.x, 655), screen.end, Vector2(screen.position.x, screen.end.y)]), PackedColorArray([Color(ink, 0), Color(ink, 0), Color(ink, .96), Color(ink, .96)]))

static func sheet(node: CanvasItem, rect: Rect2) -> void:
	# Chat needs a readable local surface, but no industrial frame ornament.
	node.draw_rect(rect, Color(.024, .040, .044, .95))
	node.draw_line(rect.position + Vector2(16, 0), rect.position + Vector2(rect.size.x - 16, 0), Color(UiArt.MUTED, .22), 1)

static func _gradient(node: CanvasItem, rect: Rect2, left: Color, right: Color) -> void:
	node.draw_polygon(PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]), PackedColorArray([left, right, right, left]))
