extends SceneTree
## Native pixel lettering specimen; no game/profile state is loaded.
const DESTINATION := "res://artifacts/bunkercrew-typography"
const FIELD := preload("res://assets/fonts/bunkercrew/body.tres")
const MENU := preload("res://assets/fonts/bunkercrew/menu.tres")
const SIGNAL := preload("res://assets/fonts/bunkercrew/title.tres")
var sheet: Control
var checks := 0
var failed := false

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failed = true
		push_error(label)

func _run() -> void:
	var sample := "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789ÄÖÜäöüßẞ.,:;!?%+-/()[]…·×–’←→↓−◇●✓‹›"
	for face: FontVariation in [FIELD, MENU, SIGNAL]:
		for character in sample:
			check(face.base_font.has_char(character.unicode_at(0)), "Original glyph missing: "+character)
		for locale in ["de", "en"]:
			var entries: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://locales/%s.json" % locale))
			for entry: String in entries.values():
				for character in entry:
					if character.unicode_at(0) > 32:
						if not face.base_font.has_char(character.unicode_at(0)):
							check(false, "Locale glyph missing in %s: %s" % [locale, character])
		check(face.base_font.font_name.begins_with("Bunkercrew"), "Original font family")
		if face == SIGNAL:
			check(not face.base_font.multichannel_signed_distance_field, "Display font uses crisp bitmap rendering")
			check(face.base_font.antialiasing == TextServer.FONT_ANTIALIASING_NONE, "Large display outlines remain crisp")
		else:
			check(face.base_font.multichannel_signed_distance_field, "Small pixel lettering preserves strokes at fractional viewport scales")
			check(face.base_font.msdf_size == 112 and face.base_font.msdf_pixel_range == 4, "Field atlas preserves the original stepped contours")
	for text_size in [11, 12, 13, 14, 16, 28]:
		for sample_text in ["Bunker sichern", "Ausrüstung verbessern", "Build the next room", "Geschütz nachladen"]:
			for line in UiArt.wrap_text(sample_text, 220, text_size, FIELD):
				check(FIELD.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, text_size).x <= 220, "Body wrap exceeds its column")
	check(SIGNAL.get_string_size("BUNKERCREW", HORIZONTAL_ALIGNMENT_LEFT, -1, 64).x <= 494, "Wordmark fits main-menu title bounds")
	if DisplayServer.get_name() != "headless":
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DESTINATION))
		sheet = Control.new()
		sheet.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sheet.size = Vector2(1440, 900)
		sheet.draw.connect(_draw_specimen)
		root.add_child(sheet)
		for viewport_size: Vector2i in [Vector2i(1440, 900), Vector2i(2560, 1440)]:
			root.size = viewport_size
			var ratio := float(viewport_size.y)/900.0
			sheet.scale = Vector2.ONE*ratio
			sheet.position.x = (viewport_size.x-1440*ratio)*.5
			sheet.queue_redraw()
			await process_frame
			await process_frame
			await RenderingServer.frame_post_draw
			var filename := "specimen.png" if viewport_size.x == 1440 else "specimen-qhd.png"
			check(root.get_texture().get_image().save_png(DESTINATION+"/"+filename) == OK, "Specimen capture")
		sheet.queue_free()
		await process_frame
	print("Bunkercrew typography: %d checks, %s" % [checks, "FAILED" if failed else "PASS"])
	quit(1 if failed else 0)

func _line(at: Vector2, value: String, text_size: int = 14, color: Color = UiArt.IVORY, face: Font = FIELD) -> void:
	sheet.draw_string(face, at.round(), value, HORIZONTAL_ALIGNMENT_LEFT, -1, text_size, color)

func _draw_specimen() -> void:
	sheet.draw_rect(Rect2(0, 0, 1440, 900), Color("13201e"))
	sheet.draw_rect(Rect2(0, 0, 5, 900), UiArt.AMBER)
	_line(Vector2(58, 47), "BUNKERCREW / FIELD LETTERING / 02", 14, UiArt.MUTED)
	_line(Vector2(56, 136), "BUNKERCREW", 84, UiArt.IVORY, SIGNAL)
	_line(Vector2(59, 185), "Eine Crew. Ein Bunker. Gemeinsam durch die Nacht.", 21)
	sheet.draw_line(Vector2(58, 220), Vector2(1382, 220), UiArt.EDGE, 1)
	_line(Vector2(58, 269), "Kampagne fortsetzen", 28, UiArt.AMBER, MENU)
	_line(Vector2(760, 269), "Continue campaign", 28, UiArt.AMBER, MENU)
	_line(Vector2(58, 313), "Verstärkte Stützen", 28, UiArt.IVORY, MENU)
	_line(Vector2(760, 313), "Reinforced supports", 28, UiArt.IVORY, MENU)
	_line(Vector2(58, 351), "Trägt den nächsten Raum. Benötigt 2 Stahl.", 16)
	_line(Vector2(760, 351), "Supports the next room. Requires 2 steel.", 16)
	_line(Vector2(58, 383), "E halten  ·  Stützen bauen  /  Geschütz nachladen", 14, UiArt.MUTED)
	_line(Vector2(760, 383), "Hold E  ·  Build supports  /  Reload turret", 14, UiArt.MUTED)
	_line(Vector2(58, 425), "14 px: Stahl bereit / 28 / 30 / Welle 04 / 20", 14)
	_line(Vector2(760, 425), "16 px: Steel ready / 28 / 30 / Wave 04 / 20", 16)
	sheet.draw_line(Vector2(58, 465), Vector2(1382, 465), UiArt.EDGE, 1)
	_line(Vector2(58, 510), "ABCDEFGHIJKLMNOPQRSTUVWXYZ", 28, UiArt.IVORY, MENU)
	_line(Vector2(58, 554), "abcdefghijklmnopqrstuvwxyz  ÄÖÜ äöü ßẞ", 28)
	_line(Vector2(58, 600), "0123456789  I l 1 | O 0  ·  15 / 30  ·  2.5 s", 28)
	_line(Vector2(58, 646), "Ausrüstung  Munitionslager  Fahrzeug  Geschützturm", 28, UiArt.AMBER, MENU)
	_line(Vector2(58, 694), "← → ↓ ↑   − × + =   ‘ ’ „ “ ”   ◇ ● ✓   ‹ ›   ! ? & %", 28)
	sheet.draw_line(Vector2(58, 734), Vector2(1382, 734), UiArt.EDGE, 1)
	_line(Vector2(58, 778), "FIELD REGULAR / Sätze und Spielwerte / Body copy and status", 16)
	_line(Vector2(58, 815), "FIELD MEDIUM / Menüs und Aktionen / Menus and actions", 16, UiArt.IVORY, MENU)
	_line(Vector2(58, 862), "Original grid outlines. Genuine lowercase. No borrowed font outlines. SIL Open Font License 1.1.", 14, UiArt.MUTED)
