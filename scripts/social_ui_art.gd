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
	# The authored size; boost_fonts() scales from it in small windows.
	control.set_meta("base_font_size", font_size)
	control.add_theme_constant_override("h_separation", 12)
	control.set_meta("quiet_focus", true)
	if not glyph.is_empty(): control.icon = icon(glyph)
	# Two separate states that may sit on different rows of one list:
	# - selected (a toggled tab or row, the "pressed" state): amber type on a
	#   solid amber rule; screens add their own marker beside it;
	# - focus (where keys or pad act next, drawn over any state): a warm wash
	#   behind bright type, never the selection's colour or rule.
	# Hover shares the focus language at half strength. Text that starts at the
	# control's edge (inset 0) gets the wash a little beyond it, not under it.
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color.TRANSPARENT
		style.content_margin_left = inset
		style.content_margin_right = 8
		style.content_margin_bottom = bottom_inset
		match state:
			"pressed", "hover_pressed":
				style.border_width_bottom = 2
				style.border_color = UiArt.AMBER
			"focus", "hover":
				style.bg_color = Color(UiArt.AMBER, .15 if state == "focus" else .07)
				style.expand_margin_left = maxf(0.0, 10.0 - inset)
		control.add_theme_stylebox_override(state, style)
	control.add_theme_color_override("font_color", UiArt.IVORY)
	control.add_theme_color_override("icon_normal_color", UiArt.MUTED)
	for state in ["font_hover_color", "font_focus_color", "icon_hover_color", "icon_focus_color"]:
		control.add_theme_color_override(state, UiArt.TEXT_HOVER)
	for state in ["font_pressed_color", "font_hover_pressed_color", "icon_pressed_color", "icon_hover_pressed_color"]:
		control.add_theme_color_override(state, UiArt.AMBER)
	control.add_theme_color_override("font_disabled_color", Color(UiArt.MUTED, .7))
	control.add_theme_color_override("icon_disabled_color", Color(UiArt.MUTED, .5))

## A one-shot command inside a page (calibrate, open the music lab, start the
## tutorial): the quiet menu type of button(), on a framed, raised plate with a
## lit upper bevel, a firm lower edge and a small pixel chevron, so it reads as
## something to press next to plain labels and value fields. Disabled, the
## plate stays (dim, no chevron), so an unavailable command still reads as one.
static func action(control: Button, font_size: int = 17) -> void:
	button(control, font_size, "", 14)
	control.alignment = HORIZONTAL_ALIGNMENT_CENTER
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		var style := StyleBoxFlat.new()
		style.anti_aliasing = false
		style.content_margin_left = 14
		style.content_margin_right = 26
		style.content_margin_top = 5 + (1 if state in ["pressed", "hover_pressed"] else 0)
		style.content_margin_bottom = 5 - (1 if state in ["pressed", "hover_pressed"] else 0)
		style.set_border_width_all(1)
		style.border_width_bottom = 1 if state in ["pressed", "hover_pressed"] else 2
		match state:
			"normal":
				style.bg_color = Color(.115, .152, .136, .9)
				style.border_color = Color(UiArt.BORDER, .62)
			"hover":
				style.bg_color = Color(.165, .208, .178, .94)
				style.border_color = Color(UiArt.AMBER, .72)
			"pressed", "hover_pressed":
				style.bg_color = Color(.07, .095, .086, .94)
				style.border_color = UiArt.AMBER
			"disabled":
				# Sunken and dimmer than the enabled plate, but still a framed
				# plate with readable type; the trim adds a lock where the
				# chevron was (see UiArt.lock_glyph).
				style.bg_color = Color(UiArt.SURFACE_DISABLED, .9)
				style.border_color = UiArt.BORDER_DISABLED
				style.border_width_bottom = 1
			"focus":
				style.draw_center = false
				style.set_border_width_all(2)
				style.border_color = UiArt.AMBER
		control.add_theme_stylebox_override(state, style)
	control.add_theme_color_override("font_disabled_color", UiArt.TEXT_DISABLED)
	if not control.has_meta("action_trim"):
		control.set_meta("action_trim", true)
		control.draw.connect(_action_trim.bind(control))

static func _action_trim(control: Button) -> void:
	var size := control.size
	if size.x < 24.0 or size.y < 12.0: return
	var pressed := control.button_pressed or (control.is_hovered() and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT))
	# Lit upper bevel inside the frame.
	if not control.disabled and not pressed:
		control.draw_rect(Rect2(Vector2(1, 1), Vector2(size.x - 2, 1)), Color(.86, .86, .72, .16))
	if control.disabled:
		UiArt.lock_glyph(control, Vector2(size.x - 24, roundf(size.y * .5) - 7), Color(UiArt.TEXT_DISABLED, .85))
		return
	# Pixel chevron at the right end, in 2x2 design-pixel cells.
	var lit := control.has_focus() or control.is_hovered()
	var color := UiArt.AMBER if lit else Color(UiArt.MUTED, .85)
	var at := Vector2(size.x - 17, roundf(size.y * .5) - 5 + (1 if pressed else 0))
	for row in 5:
		var column := 2 - absi(row - 2)
		control.draw_rect(Rect2(at + Vector2(column * 2, row * 2), Vector2(2, 2)), color)

## Small windows draw a menu's 1440x900 design canvas at down to 2/3 scale,
## where 17 px control type lands at 11 real pixels and 15 px notes at 10.
## Re-sizes every menu control below `root` from its authored size by
## UiArt.compact_boost (1.0 from a 0.95 output scale up, 1.25 at 960x600);
## positions and rectangles stay as authored. Returns the boost applied.
static func boost_fonts(root: Node, boost: float) -> float:
	for child in root.get_children():
		if child is Button and child.has_meta("base_font_size"):
			var base := int(child.get_meta("base_font_size"))
			(child as Button).add_theme_font_size_override("font_size", roundi(base * boost))
			if child is OptionButton: (child as OptionButton).get_popup().add_theme_font_size_override("font_size", roundi(16 * boost))
		boost_fonts(child, boost)
	return boost

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

## Reading surface for a full-screen menu. Over the painted menu landscape the
## centre stays open to show the site. Over a running match (`over_match`) an
## open window would expose actors, name tags and machinery behind the text
## (even at 93 % ink the crew tags still read through), so every word sits on
## one opaque sheet (match_sheet) and the HUD's curtain dims the match around
## it.
static func reading_shade(node: CanvasItem, screen: Rect2, left_end: float = 460.0, right_start: float = 990.0, over_match: bool = false) -> void:
	var ink := Color(.024, .040, .044)
	if over_match:
		match_sheet(node, left_end)
		return
	_gradient(node, Rect2(screen.position, Vector2(left_end - screen.position.x, screen.size.y)), Color(ink, .95), Color(ink, .84))
	_gradient(node, Rect2(left_end, screen.position.y, 310, screen.size.y), Color(ink, .84), Color(ink, 0))
	_gradient(node, Rect2(right_start - 190, screen.position.y, 220, screen.size.y), Color(ink, 0), Color(ink, .84))
	_gradient(node, Rect2(right_start + 30, screen.position.y, screen.end.x - right_start - 30, screen.size.y), Color(ink, .84), Color(ink, .95))
	node.draw_polygon(PackedVector2Array([screen.position, Vector2(screen.end.x, screen.position.y), Vector2(screen.end.x, 205), Vector2(screen.position.x, 205)]), PackedColorArray([Color(ink, .72), Color(ink, .72), Color(ink, 0), Color(ink, 0)]))
	node.draw_polygon(PackedVector2Array([Vector2(screen.position.x, 655), Vector2(screen.end.x, 655), screen.end, Vector2(screen.position.x, screen.end.y)]), PackedColorArray([Color(ink, 0), Color(ink, 0), Color(ink, .96), Color(ink, .96)]))

## The opaque sheet of a full-screen panel over the match, inset in the design
## canvas so the dimmed match frames it: the HUD ink with the plates' grain, an
## inked rim with a lit upper edge, and the navigation column (up to
## `left_end`) set slightly deeper. Everything the panel writes lies inside.
const MATCH_SHEET := Rect2(40, 36, 1360, 840)
static func match_sheet(node: CanvasItem, left_end: float = 420.0) -> void:
	var rect := MATCH_SHEET
	node.draw_rect(rect.grow(2), Color(.01, .016, .018))
	node.draw_rect(rect, Color(.024, .040, .044))
	node.draw_texture_rect(UiArt.steel_grain(), rect, true)
	_gradient(node, Rect2(rect.position, Vector2(left_end - rect.position.x, rect.size.y)), Color(.012, .02, .022, .6), Color(.012, .02, .022, 0))
	node.draw_rect(Rect2(rect.position, Vector2(rect.size.x, 1)), Color(.42, .46, .37, .7))
	node.draw_rect(Rect2(rect.position + Vector2(0, 1), Vector2(1, rect.size.y - 1)), Color(UiArt.EDGE, .35))
	node.draw_rect(Rect2(rect.position + Vector2(rect.size.x - 1, 1), Vector2(1, rect.size.y - 1)), Color(UiArt.EDGE, .35))

static func sheet(node: CanvasItem, rect: Rect2, opacity: float = .95) -> void:
	# Chat needs a readable local surface, but no industrial frame ornament.
	# Panels that hold reading content over a live match pass 1.0 (opaque).
	node.draw_rect(rect, Color(.024, .040, .044, opacity))
	node.draw_line(rect.position + Vector2(16, 0), rect.position + Vector2(rect.size.x - 16, 0), Color(UiArt.MUTED, .22), 1)

static func _gradient(node: CanvasItem, rect: Rect2, left: Color, right: Color) -> void:
	node.draw_polygon(PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]), PackedColorArray([left, right, right, left]))
