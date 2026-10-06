extends SceneTree
## Actual story scene; later act and authored long dialogue are prepared solely
## to exercise the UI. No gameplay completion or saved progression is implied.
const Catalog := preload("res://scripts/story_dialogue_catalog.gd")
const Cleanup := preload("res://tests/scene_cleanup.gd")
const OUTPUT := "res://artifacts/crew-overlays"
var checks := 0
var failures := 0
var capture_images := false
var game
var view: SubViewport

func _initialize() -> void: run.call_deferred()

func check(ok: bool,message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func frames(count: int = 4) -> void:
	for unused in count: await process_frame

func longest_radio_line() -> String:
	var best := "story_open"
	var length := 0
	for id: String in Catalog.LINES:
		var entry := Catalog.line(id,"san")
		if entry.is_empty() or bool(entry.ending): continue
		if str(entry.text).length() > length:
			best = id
			length = str(entry.text).length()
	return best

func run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args(): quit(2); return
	capture_images = "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless"
	if capture_images: DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	AudioServer.set_bus_mute(0,true)
	view = SubViewport.new()
	view.size = Vector2i(1440,900)
	view.size_2d_override = Vector2i(1440,900)
	view.size_2d_override_stretch = true
	view.world_2d = World2D.new()
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	game = load("res://scenes/main.tscn").instantiate()
	view.add_child(game)
	game.story_mode = true
	game.start_scenario(4,{"environment":"ash_foundry","position":"center","build_type":"bastion"})
	game.rounds.running = false
	game.rounds.set_process(false)
	game.story.set_process(false)
	game.dialogue.set_process(false)
	for worker in game.players: worker.set_physics_process(false)
	await frames()
	var panel
	for candidate in get_nodes_in_group("story_objective_panels"):
		if game.is_ancestor_of(candidate): panel = candidate
	check(panel != null and game.story.enabled and game.story_mode,"Real four-player story start creates the objective panel")
	if panel == null: quit(1); return
	for pixels in [Vector2i(1440,900),Vector2i(2560,1440)]:
		view.size = pixels
		view.size_2d_override = Vector2i(1440,900) if pixels.x == 1440 else Vector2i(1600,900)
		await frames()
		for language in ["de","en"]:
			LocaleText.set_locale(language,false)
			game.dialogue.reset()
			check(game.dialogue.enqueue(longest_radio_line(),"san",1),language+" longest authored radio caption queued")
			game.dialogue.advance(.4)
			game.dialogue.advance(.25)
			check(game.dialogue.active_age >= .13 and game.dialogue.canvas.visible,"Long caption has completed its entrance fade and is visibly rendered")
			var screen: Rect2 = game.hud.screen_rect()
			var caption_layout: Dictionary = game.dialogue.caption_layout()
			var raw_caption: Rect2 = caption_layout.rect
			var caption := Rect2(raw_caption.position+screen.position,raw_caption.size)
			for stage in 10:
				game.story.stage = stage
				var layout: Dictionary = panel.objective_layout()
				var bounds: Rect2 = panel.objective_bounds()
				check(not bounds.intersects(caption) and bounds.position.y >= caption.end.y + 12,language+" objective stays below full caption at stage "+str(stage))
				check(screen.encloses(bounds),language+" complete objective stays inside the viewport")
				check(" ".join(layout.rows) == game.story.objective(),language+" every objective word remains visible")
				for row: String in layout.rows:
					check(UiArt.FONT.get_string_size(row,HORIZONTAL_ALIGNMENT_LEFT,-1,14).x <= bounds.size.x-32,language+" objective line fits at readable14px")
				var safe: Rect2 = panel.marker_safe_bounds()
				for direction in [Vector2.LEFT,Vector2.RIGHT,Vector2.UP,Vector2.DOWN]:
					var marker: Dictionary = panel.marker_layout(safe.get_center()+direction*5000,safe)
					check(screen.grow(-16).has_point(marker.point) and screen.grow(-16).has_point(marker.label),"Direction cue stays inside real viewport")
					check(not bounds.has_point(marker.point) and not caption.has_point(marker.point),"Direction cue avoids objective and dialogue")
					for occupied: Rect2 in game.hud.occupied_gameplay_bounds():
						check(not occupied.grow(3).has_point(marker.point),"Direction cue avoids occupied HUD and player docks")
			game.story.stage = 3
			if capture_images:
				await frames()
				await RenderingServer.frame_post_draw
				var filename := "story-objective-%s-%d.png" % [language,pixels.x]
				check(view.get_texture().get_image().save_png(OUTPUT+"/"+filename)==OK,"Captured true story mode with long dialogue and complete objective")
			game.dialogue.reset()
			check(is_equal_approx(panel.objective_bounds().position.y,screen.position.y+74),"Objective returns to its top edge slot after speech")
			check(game.dialogue.enqueue("story_victory","san",1),"Authored ending caption is queued")
			game.dialogue.advance(.1)
			game.dialogue.advance(.25)
			var ending_layout: Dictionary = game.dialogue.caption_layout()
			var raw_ending: Rect2 = ending_layout.rect
			var ending := Rect2(raw_ending.position+screen.position,raw_ending.size)
			check(screen.encloses(panel.objective_bounds()) and not panel.objective_bounds().intersects(ending),"Bottom ending caption never pushes objective outside the viewport")
			check(panel.marker_safe_bounds().end.y < ending.position.y,"Objective marker stays above an ending subtitle")
	game.hud.overlay = "personal"
	check(not panel.objective_bounds().has_area(),"Objective is absent while menus are open")
	game.hud.overlay = ""
	check(await Cleanup.free_scene(game,self),"Story layout scene and dialogue clean up")
	view.queue_free()
	await frames()
	if capture_images:
		var html := "<!doctype html><meta charset='utf-8'><title>Bunkercrew – Story UI</title><style>body{background:#101816;color:#ddd;font:16px sans-serif;max-width:1440px;margin:30px auto}img{width:100%}h2{margin-top:40px}</style><h1>Story objectives and dialogue</h1><p>Actual four-player story mode. Act II and the longest authored radio line are prepared for layout review. German and English, native 1440×900 and 2560×1440. No profile saving.</p>"
		for pixels in [1440,2560]:
			for language in ["de","en"]:
				var id := "story-objective-%s-%d" % [language,pixels]
				html += "<h2>"+id+"</h2><a href='"+id+".png'><img src='"+id+".png'></a>"
		FileAccess.open(OUTPUT+"/story-objectives.html",FileAccess.WRITE).store_string(html)
	print("STORY OBJECTIVE LAYOUT: %d/%d passed" % [checks-failures,checks])
	quit(1 if failures else 0)
