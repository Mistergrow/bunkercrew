extends SceneTree
## Before/after specimen of the Bunkercrew faces in the real text renderer at the
## sizes the interface uses. The "before" column loads archived TTFs when
## `--before=res://artifacts/...` names a folder holding them; without it only
## the shipped faces are drawn. No game or profile state is loaded.
const DESTINATION := "res://artifacts/visual-pass-ui/font/"
const LINES := ["Aschewerk Akte Anzeigemodus Alex Aus 100% 50%", "Spiel Hilfe Gemeinsam million Öl 1lI 0OD 5S 8B", "SCHICHTZEIT · WOHNTRAKT / 00 · 30 / 30 +90", "rn m ä a ö o ü u ß B · Änderungen Größe Übung"]
const FACES := [["BunkercrewField-Regular.ttf", [11, 12, 13, 14, 16], true], ["BunkercrewField-Medium.ttf", [24, 28], true], ["BunkercrewSignal-Bold.ttf", [28, 36], false]]
var before_directory := ""
var sheet: Control
var failures := 0
var _faces: Dictionary = {}

func _initialize() -> void:
	run.call_deferred()

func face(directory: String, filename: String, field: bool) -> FontFile:
	# Glyph atlases upload on a later frame, so one instance serves every draw.
	if not _faces.has(directory + filename): _faces[directory + filename] = _load_face(directory, filename, field)
	return _faces[directory + filename]

func _load_face(directory: String, filename: String, field: bool) -> FontFile:
	# Same raster policy as the import settings the generator maintains.
	var font := FontFile.new()
	font.multichannel_signed_distance_field = field
	font.msdf_size = 112
	font.msdf_pixel_range = 4
	font.hinting = TextServer.HINTING_NONE
	font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	font.antialiasing = TextServer.FONT_ANTIALIASING_GRAY if field else TextServer.FONT_ANTIALIASING_NONE
	font.data = FileAccess.get_file_as_bytes(directory + filename)
	return font if not font.data.is_empty() else null

func draw_sheet() -> void:
	sheet.draw_rect(Rect2(Vector2.ZERO, sheet.size), Color("101a17"))
	var columns: Array = [["NEU", "res://assets/fonts/bunkercrew/"]]
	if not before_directory.is_empty(): columns.push_front(["ALT", before_directory])
	for column in columns.size():
		var left := 24.0 + column * 708.0
		var y := 34.0
		sheet.draw_string(ThemeDB.fallback_font, Vector2(left, 20), columns[column][0], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UiArt.AMBER)
		for entry: Array in FACES:
			var font := face(columns[column][1], entry[0], entry[2])
			if font == null:
				failures += 1
				continue
			for text_size: int in entry[1]:
				for line: String in LINES:
					y += text_size * 1.45
					sheet.draw_string(font, Vector2(left, roundf(y)), line, HORIZONTAL_ALIGNMENT_LEFT, -1, text_size, UiArt.IVORY)
				y += 8

func run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args(): quit(2); return
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--before="): before_directory = argument.trim_prefix("--before=").trim_suffix("/") + "/"
	# The confusable pairs must differ in outline, not only in the capture.
	var shipped := face("res://assets/fonts/bunkercrew/", "BunkercrewField-Regular.ttf", true)
	for pair: String in ["AR", "l1", "lI", "0O", "5S", "8B", "%X"]:
		var first := shipped.get_string_size(pair[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 14)
		if not shipped.has_char(pair.unicode_at(0)) or not shipped.has_char(pair.unicode_at(1)) or first.x <= 0: failures += 1
	if DisplayServer.get_name() == "headless": quit(1 if failures else 0); return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DESTINATION))
	sheet = Control.new()
	sheet.size = Vector2(1440, 900)
	sheet.draw.connect(draw_sheet)
	root.add_child(sheet)
	for output: Vector2i in [Vector2i(960, 600), Vector2i(1440, 900), Vector2i(2560, 1440)]:
		root.size = output
		sheet.scale = Vector2.ONE * minf(output.x / 1440.0, output.y / 900.0)
		sheet.queue_redraw()
		for unused in 6:
			sheet.queue_redraw()
			await process_frame
		await RenderingServer.frame_post_draw
		if root.get_texture().get_image().save_png(DESTINATION + "specimen-godot-%d.png" % output.x) != OK: failures += 1
	print("FONT SPECIMEN: %d failures" % failures)
	quit(1 if failures else 0)
