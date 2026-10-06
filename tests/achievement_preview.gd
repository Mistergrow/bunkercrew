extends SceneTree
## Prepared UI fixture; progress is arranged, never saved to a player profile.
const Cleanup := preload("res://tests/scene_cleanup.gd")
var game
var view: SubViewport

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	root.size=Vector2i(1600,900)
	view=SubViewport.new()
	view.size=Vector2i(2560,1440)
	view.size_2d_override=Vector2i(1600,900)
	view.size_2d_override_stretch=true
	view.world_2d=World2D.new()
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	game=load("res://scenes/main.tscn").instantiate()
	view.add_child(game)
	game.start_scenario(1,{"environment":"ash_foundry","build_type":"bastion","position":"left"})
	game.rounds.running=false
	game.combat_events.persistence_enabled=false
	game.combat_events.unlocked.clear()
	game.combat_events.unlock("first_kill")
	game.combat_events.unlock("cargo_full")
	game.combat_events.unlock("epic_weapon")
	game.combat_events.counters.mined=32
	game.combat_events.counters.crafted=2
	game.hud._toggle_personnel(true)
	for unused in 3: await process_frame
	for code in ["de","en"]:
		LocaleText.set_locale(code,false)
		for page in 3:
			game.hud.personal_panel.achievement_page=page
			game.hud.personal_panel._refresh()
			for unused in 3: await process_frame
			await RenderingServer.frame_post_draw
			var error:=view.get_texture().get_image().save_png("res://artifacts/expedition/achievements-%s-page%d.png"%[code,page+1])
			if error!=OK:
				push_error("Could not save achievement preview")
				quit(1)
				return
	game.combat_events.unlock("last_drop")
	game.combat_events.unlock("all_routes")
	game.hud.personal_panel._refresh()
	for unused in 3: await process_frame
	await RenderingServer.frame_post_draw
	view.get_texture().get_image().save_png("res://artifacts/expedition/achievements-revealed.png")
	paused=false
	await Cleanup.free_scene(game,self)
	print("ACHIEVEMENT PREVIEW: six localized QHD pages and revealed secret fixture")
	quit()
