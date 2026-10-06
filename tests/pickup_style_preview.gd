extends SceneTree
## Native world captures. Enemy loot is produced by real enemy death code;
## waves and workers are frozen only to keep the inspection repeatable.
const DEST := "res://artifacts/pickup-style/"
const Cleanup := preload("res://tests/scene_cleanup.gd")
var view: SubViewport
var game
var checks := 0
var failures := 0
var before := false

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func frames(count := 4) -> void:
	for frame in count: await process_frame

func capture(label: String) -> void:
	await frames()
	await RenderingServer.frame_post_draw
	var target := DEST + ("before/" if before else "after/") + label + ".png"
	check(view.get_texture().get_image().save_png(target) == OK, "Native capture: " + label)

func focus_view(zoom_value: float) -> void:
	game.camera.position = Vector2(1160,335)
	game.camera.zoom = Vector2.ONE * zoom_value
	game.camera.force_update_scroll()

func spawn_enemy_drops() -> void:
	var worker = game.players[0]
	worker.set_physics_process(false)
	worker.position = Vector2(985,430)
	worker.focus = null
	worker.facing = 1
	for index in 3:
		var enemy = load("res://scenes/enemy.tscn").instantiate()
		enemy.kind = ["runner","strider","breaker"][index]
		# The third machine is a genuine wave-three campaign reward carrier.
		enemy.wave = 3 if index == 2 else 1
		enemy.game = game
		enemy.position = Vector2([1100,1200,1296][index],430)
		game.add_child(enemy)
		enemy.set_physics_process(false)
		enemy.take_damage(enemy.max_hp+1)
	await frames(5)
	for frame in 45: await physics_frame
	var pickups := get_nodes_in_group("pickups").filter(func(pile): return pile.game == game)
	check(pickups.size() == 6, "Three defeated machines create six real material/module drops")
	for pile in pickups:
		check(pile.kind in ["scrap","core"] and pile.amount > 0, "Enemy loot retains its actual material kind and positive amount")
		check(absf(pile.position.y-429.5) < 1.0, "Real loot physics settles on the surface")
		pile.set_physics_process(false)
	var route_data := get_nodes_in_group("campaign_salvage").filter(func(pile): return pile.game == game)
	check(route_data.size() == 1, "A real wave-three kill also drops its reserved campaign data")
	for data in route_data:
		check(data.amount == 1 and not data.claim_id.is_empty(), "Campaign data keeps its real claim and reward amount")
		check(absf(data.position.y-429.5) < 1.0, "Campaign data settles with ordinary ground physics")
		data.set_physics_process(false)
	worker.focus = pickups.filter(func(pile): return pile.kind == "scrap")[0]
	worker.position.x = 1050
	game.notice_time = 0
	game.hud.combat_overlay.numbers.clear()

func resource_lineup() -> void:
	# A catalogue view keeps the real level, floor, worker and pickup nodes;
	# only optional foreground scenery is hidden to expose every silhouette.
	game.scenery.props_layer.visible = false
	for pile in get_nodes_in_group("pickups"):
		if pile.game == game: pile.queue_free()
	for data in get_nodes_in_group("campaign_salvage"):
		if data.game == game: data.queue_free()
	await frames()
	game.players[0].position = Vector2(870,430)
	game.players[0].focus = null
	var kinds := ["sand","ore","steel","concrete","ammo","scrap","core","limestone","glass","tungsten","alloy","jaw_trap","blast_trap","sentry_kit"]
	for index in kinds.size():
		game.spawn_pickup(kinds[index],3,Vector2(940+index*43,429.5))
	await frames(5)
	for pile in get_nodes_in_group("pickups"):
		if pile.game == game: pile.set_physics_process(false)
	game.camera.position = Vector2(1195,349)
	game.camera.zoom = Vector2.ONE * 2.0
	game.camera.force_update_scroll()
	await capture("resource-lineup-desktop")

func run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless":
		quit(2)
		return
	before = "--before" in OS.get_cmdline_user_args()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DEST+("before" if before else "after")))
	AudioServer.set_bus_mute(0,true)
	root.size = Vector2i(320,180)
	root.set_flag(Window.FLAG_NO_FOCUS,true)
	view = SubViewport.new()
	view.world_2d = World2D.new()
	view.size = Vector2i(1440,900)
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	for environment in ["frozen_rail_yard","ash_foundry"]:
		view.size = Vector2i(1440,900)
		view.size_2d_override = Vector2i(1440,900)
		view.size_2d_override_stretch = true
		LocaleText.set_locale("de",false)
		game = load("res://scenes/main.tscn").instantiate()
		view.add_child(game)
		game.start_scenario(1,{"environment":environment,"build_type":"bastion","position":"left"})
		game.rounds.running = false
		game.rounds.set_process(false)
		game.set_process(false)
		game.medic.set_physics_process(false)
		game.dialogue.reset()
		await spawn_enemy_drops()
		focus_view(2.5)
		await capture(environment+"-desktop-close-de")
		if not before:
			focus_view(1.25)
			await capture(environment+"-desktop-default-de")
			focus_view(.45)
			await capture(environment+"-desktop-min-de")
			view.size = Vector2i(2560,1440)
			view.size_2d_override = Vector2i(1600,900)
			game.hud._layout_viewport()
			LocaleText.set_locale("en",false)
			focus_view(2.5)
			await capture(environment+"-qhd-close-en")
			if environment == "ash_foundry":
				view.size = Vector2i(1440,900)
				view.size_2d_override = Vector2i(1440,900)
				game.hud._layout_viewport()
				await resource_lineup()
		check(await Cleanup.free_scene(game,self), "Prepared scene and audio handles release")
	view.queue_free()
	await process_frame
	print("PICKUP STYLE PREVIEW: %d/%d passed" % [checks-failures,checks])
	quit(1 if failures else 0)
