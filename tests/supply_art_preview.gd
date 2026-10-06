extends SceneTree
## Visual fixture: prepared full and empty stores at 1x and 4x, beside the real
## production artwork. It does not claim to be a played campaign state.

class CratePreview extends Node2D:
	const Crates := preload("res://scripts/supply_art.gd")
	const KINDS := ["sand", "ore", "steel", "concrete", "ammo", "glass", "limestone", "alloy"]
	func _draw() -> void:
		draw_rect(Rect2(0, 0, 1280, 760), Color("242b29"))
		UiArt.text(self, Vector2(35, 39), "Vorratskisten · tatsächliche Spielgrafik", 22)
		UiArt.text(self, Vector2(35, 67), "Oben Originalgröße · unten 4× zur Materialprüfung · rechte Kisten leer", 13, UiArt.MUTED)
		for index in KINDS.size():
			var at := Vector2(86 + index * 155, 174)
			draw_set_transform(at)
			Crates.draw(self, KINDS[index], 12)
			UiArt.world_label(self, Vector2(0, -60), Balance.RESOURCE_NAMES[KINDS[index]], "12 verfügbar", UiArt.MUTED, 125)
			draw_set_transform(Vector2.ZERO)
		for index in 4:
			var at := Vector2(154 + index * 319, 444)
			draw_set_transform(at, 0, Vector2(4, 4))
			Crates.draw(self, KINDS[index * 2], 0 if index == 3 else 12)
			draw_set_transform(Vector2.ZERO)
		MachineryArt.paint(self, "furnace", Rect2(377, 548, 124, 111))
		MachineryArt.paint(self, "mixer_frame", Rect2(700, 586, 110, 73))
		MachineryArt.paint(self, "mixer_drum", Rect2(718, 560, 74, 65))
		for index in 4:
			draw_set_transform(Vector2(295 + index * 276, 659))
			Crates.draw(self, KINDS[index * 2 + 1], 0 if index == 3 else 12)
			draw_set_transform(Vector2.ZERO)
		UiArt.text(self, Vector2(35, 731), "Referenz: vorhandene Maschinen, unveränderte 58 × 38 Pixel große Kisten", 13, UiArt.MUTED)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		print("SUPPLY ART PREVIEW: graphical display required")
		quit(0)
		return
	root.size = Vector2i(1280, 760)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	var preview := CratePreview.new()
	preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	root.add_child(preview)
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://artifacts/quality-pass/supply-art")
	var error := root.get_texture().get_image().save_png("res://artifacts/quality-pass/supply-art/crates-review.png")
	print("SUPPLY ART PREVIEW: saved, result %d" % error)
	preview.queue_free()
	await process_frame
	quit(0 if error == OK else 1)
