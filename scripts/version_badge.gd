extends Label
## An unobtrusive always-visible tester identity; never captures gameplay input.
const Identity := preload("res://scripts/build_identity.gd")
var hud: Node

func _ready() -> void:
	name="VersionBadge"
	process_mode=Node.PROCESS_MODE_ALWAYS
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	focus_mode=Control.FOCUS_NONE
	z_index=90
	add_theme_font_override("font",UiArt.FONT)
	add_theme_font_size_override("font_size",11)
	add_theme_color_override("font_color",UiArt.MUTED)
	add_theme_color_override("font_outline_color",Color(.025,.04,.04,.95))
	add_theme_constant_override("outline_size",3)
	get_viewport().size_changed.connect(_layout)
	var localization:=get_node_or_null("/root/Localization")
	if localization!=null: localization.locale_changed.connect(_refresh)
	_refresh()

func _refresh(_locale: String="") -> void:
	text=Identity.display_text()
	_layout()

func _layout() -> void:
	if not is_instance_valid(hud): return
	var bounds: Rect2=hud.screen_rect()
	size=Vector2(UiArt.FONT.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,11).x+4,18)
	position=bounds.end-size-Vector2(12,7)
