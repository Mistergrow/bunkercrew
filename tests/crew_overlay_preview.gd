extends SceneTree
## Prepared presentation fixture: progression, achievement state and voiced
## events are arranged; actual scene/UI rendered, profile persistence disabled.
const DEST := "res://artifacts/crew-overlays"
var game
var captures: Array[String] = []
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func frames(count: int = 4) -> void:
	for unused in count: await process_frame

func capture(id: String) -> void:
	await frames(5)
	await RenderingServer.frame_post_draw
	if root.get_texture().get_image().save_png(DEST + "/" + id + ".png") != OK:
		failures += 1
		push_error("Overlay capture failed: " + id)
	captures.append(id)

func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("This preview requires a graphical display")
		quit(1)
		return
	AudioServer.set_bus_mute(0,true)
	root.size = Vector2i(1440,900)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DEST))
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await frames()
	game.start_scenario(1,{"environment":"ash_foundry","build_type":"bastion","position":"left"})
	game.rounds.running = false
	game.rounds.set_process(false)
	game.combat_events.persistence_enabled = false
	game.combat_events.unlocked.clear()
	game.combat_events.unlock("first_kill")
	game.combat_events.unlock("cargo_full")
	game.combat_events.unlock("epic_weapon")
	game.combat_events.counters.mined = 32
	game.players[0].progression.level = 7
	game.players[0].progression.skill_points = 3
	game.players[0].progression.skills.engineering = 2
	game.players[0].progression.equip_armor(1)
	game.hud._toggle_personnel()
	await frames()
	for code in ["de","en"]:
		LocaleText.set_locale(code,false)
		game.hud.personal_panel.select_tab("skills")
		await capture(code + "-skills")
		game.hud.personal_panel.select_tab("achievements")
		for page in 3:
			game.hud.personal_panel.achievement_page = page
			game.hud.personal_panel._refresh()
			await capture(code + "-achievements-" + str(page+1))
	game.hud._close_personnel()
	game.hud.combat_overlay.numbers.clear()
	game.hud.combat_overlay.banners.clear()
	game.hud.combat_overlay.boss.clear()
	for code in ["de","en"]:
		LocaleText.set_locale(code,false)
		game.hud.combat_overlay.banners.clear()
		game.hud.combat_overlay.handle_event("level_up",{"player_id":1,"level":7})
		game.dialogue.reset()
		game.dialogue.enqueue("crew_reply","mara",1)
		game.dialogue.advance(.35)
		await capture(code + "-docked-feedback")
	game.dialogue.reset()
	paused = false
	await preload("res://tests/scene_cleanup.gd").free_scene(game,self)
	var html := "<!doctype html><meta charset='utf-8'><title>Bunkercrew – Crew UI</title><style>body{background:#101816;color:#ddd;font:16px sans-serif;max-width:1440px;margin:30px auto}img{width:100%}h2{margin-top:40px}</style><h1>Crew, progression and dialogue</h1><p>Prepared presentation fixture: actual game scene, arranged progression/achievement states and triggered authored dialogue. German and English, 1440×900; profile saving disabled.</p>"
	for id in captures: html += "<h2>" + id + "</h2><a href='" + id + ".png'><img loading='lazy' src='" + id + ".png'></a>"
	FileAccess.open(DEST + "/index.html",FileAccess.WRITE).store_string(html)
	print("CREW OVERLAYS: %d rendered captures, %d failures" % [captures.size(),failures])
	quit(1 if failures else 0)
