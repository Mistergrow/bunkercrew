extends SceneTree
## Articulated crew poses for every identity, drawn exactly as the game draws
## them (WorkerPoseArt.draw_identity_pose on a canvas at a whole-pixel zoom).
## Presentation review only; needs a graphical display.
##   --poses=downed:0.2,rise:0.5,...   kind:phase per column (WorkerPoseArt.sample)
##   --zoom=4  --out=<abs png>  --ids=mara,branko,...
const PoseArt := preload("res://scripts/worker_pose_art.gd")
const CELL := Vector2(96, 84)

class Sheet extends Node2D:
	var poses: Array = []
	var ids: Array = []
	func _draw() -> void:
		for row in ids.size():
			for column in poses.size():
				var spec: Array = poses[column]
				var pose := PoseArt.sample(str(spec[0]), float(spec[1]), float(spec[2]) if spec.size() > 2 else 0.0, Vector2(24, -13), str(ids[row]))
				draw_set_transform(Vector2(column * CELL.x + 40, row * CELL.y + 74))
				draw_rect(Rect2(-40, 0, CELL.x, 2), Color("4b4237"))
				PoseArt.draw_identity_pose(self, pose, str(ids[row]))
		draw_set_transform(Vector2.ZERO)

func _initialize() -> void: run.call_deferred()

func _argument(prefix: String, fallback: String) -> String:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with(prefix): return argument.trim_prefix(prefix)
	return fallback

## --infantry=rifle_guard,grenadier --ages=0,0.2,...: real ground_infantry_art
## corpses (the drawn defeat) at fixed ages instead of crew poses.
func _infantry_sheet(viewport: SubViewport, zoom: float) -> void:
	var kinds := _argument("--infantry=", "").split(",")
	var ages := _argument("--ages=", "0,0.1,0.2,0.3,0.4,0.5,0.6,0.7,0.9,1.5").split(",")
	viewport.size = Vector2i(Vector2(CELL.x * ages.size(), CELL.y * kinds.size()) * zoom)
	var holder := Node2D.new()
	holder.scale = Vector2.ONE * zoom
	viewport.add_child(holder)
	var start := preload("res://scripts/worker_pose_art.gd").neutral()
	start.hip = Vector2(-1, -25)
	start.shoulder = Vector2(2, -42)
	for row in kinds.size():
		for column in ages.size():
			var art = preload("res://scripts/ground_infantry_art.gd").new()
			art.corpse = true
			art.troop_kind = kinds[row]
			art.squad_slot = column % 3
			art.fall_start = start.duplicate(true)
			art.fall_gun = Transform2D(-0.2, Vector2(6, -35))
			art.pose = start.duplicate(true)
			art.position = Vector2(column * CELL.x + 48, row * CELL.y + 74)
			art.scale = Vector2(-1 if column % 2 == 1 else 1, 1)
			holder.add_child(art)
			art.corpse_age = float(ages[column])
			art.pose = art.fall_pose(art.fall_start, art.corpse_age, false)
			art.gun = art.fall_gun_transform(art.fall_gun, art.corpse_age, false)
			art.shown = art.pose
			art.shown_gun = art.gun
			art.set_process(false)
			art.queue_redraw()

func run() -> void:
	if DisplayServer.get_name() == "headless": quit(2); return
	if not _argument("--infantry=", "").is_empty():
		var view := SubViewport.new()
		view.transparent_bg = false
		view.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
		view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(view)
		var backdrop := ColorRect.new()
		backdrop.color = Color("3a4650")
		backdrop.size = Vector2(4000, 4000)
		view.add_child(backdrop)
		_infantry_sheet(view, float(_argument("--zoom=", "3")))
		for frame in 4: await RenderingServer.frame_post_draw
		var picture := view.get_texture().get_image()
		var result := picture.save_png(_argument("--out=", "/tmp/pose_gallery.png"))
		print("POSE GALLERY ", picture.get_size(), " ", result)
		view.free()
		quit(0 if result == OK else 1)
		return
	var sheet := Sheet.new()
	for item in _argument("--poses=", "idle:0").split(","):
		var parts := item.split(":")
		sheet.poses.append(Array(parts))
	sheet.ids = Array(_argument("--ids=", "mara,branko,ivo,nora,levin,selma,oskar,rika").split(","))
	var zoom := float(_argument("--zoom=", "4"))
	var viewport := SubViewport.new()
	viewport.size = Vector2i(Vector2(CELL.x * sheet.poses.size(), CELL.y * sheet.ids.size()) * zoom)
	viewport.transparent_bg = false
	viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var back := ColorRect.new()
	back.color = Color("3a4650")
	back.size = Vector2(viewport.size)
	viewport.add_child(back)
	sheet.scale = Vector2.ONE * zoom
	viewport.add_child(sheet)
	for frame in 3: await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	var code := image.save_png(_argument("--out=", "/tmp/pose_gallery.png"))
	print("POSE GALLERY ", image.get_size(), " ", code)
	viewport.free()
	quit(0 if code == OK else 1)
