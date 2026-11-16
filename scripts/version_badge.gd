extends Label
## The tester identity (version and build). It shows where a tester looks for
## it, in the main menu, the options (with the microphone page) and the pause
## menu, and stays out of the picture everywhere else: in play it sat over the
## fence line and the edge threat arrows like a watermark. The support report
## carries the same identity on every screen. Never captures input.
const Identity := preload("res://scripts/build_identity.gd")
## HUD overlays on which the identity is shown.
const SHOWN_ON := ["menu","audio","microphone","pause"]
## The helper-label size (UiArt.TEXT_LABEL); it grows in small windows.
const BADGE_SIZE := 13
var hud: Node

func _ready() -> void:
	name="VersionBadge"
	process_mode=Node.PROCESS_MODE_ALWAYS
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	focus_mode=Control.FOCUS_NONE
	z_index=90
	add_theme_font_override("font",UiArt.FONT)
	add_theme_font_size_override("font_size",BADGE_SIZE)
	add_theme_color_override("font_color",UiArt.MUTED)
	# A small opaque ink chip: over the dimmed match (options, pause) the
	# identity never prints straight onto the scene.
	var chip := StyleBoxFlat.new()
	chip.bg_color = Color(.024,.040,.044)
	chip.content_margin_left = 6
	chip.content_margin_right = 6
	chip.border_width_top = 1
	chip.border_color = Color(UiArt.EDGE,.45)
	add_theme_stylebox_override("normal",chip)
	get_viewport().size_changed.connect(_layout)
	var localization:=get_node_or_null("/root/Localization")
	if localization!=null: localization.locale_changed.connect(_refresh)
	_refresh()
	_sync_visibility()

func _process(_delta: float) -> void:
	_sync_visibility()

## True on the screens that show the identity (see SHOWN_ON).
func wanted() -> bool:
	return is_instance_valid(hud) and str(hud.get("overlay")) in SHOWN_ON

func _sync_visibility() -> void:
	var shown:=wanted()
	if shown!=visible:
		visible=shown
		if shown: _layout()

func _refresh(_locale: String="") -> void:
	text=Identity.display_text()
	_layout()

func _layout() -> void:
	if not is_instance_valid(hud): return
	var bounds: Rect2=hud.screen_rect()
	# Menus keep the authored canvas, so in a small window the identity grows
	# like their helper copy (UiArt.compact_boost, 16 px at 960x600: 11 real
	# pixels). It only shows on menu screens, the pause one included.
	var font_size:=roundi(BADGE_SIZE*UiArt.compact_boost(self))
	add_theme_font_size_override("font_size",font_size)
	# The identity lives in the screen margin below every HUD strip and menu
	# hint row, so it never sits on a player panel (four-player HUD).
	var line_height:=ceilf(UiArt.FONT.get_height(font_size))
	size=Vector2(UiArt.FONT.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x+12,line_height)
	position=Vector2(bounds.end.x-size.x-6,bounds.end.y-line_height-2)
