extends SceneTree
const Cleanup := preload("res://tests/scene_cleanup.gd")
var game
var view: SubViewport
func _initialize() -> void: run.call_deferred()
func freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children(): freeze(child)
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
	game.selected_characters = PartyConfig.normalize_characters(["mara","branko","ivo","mara"])
	game.start_scenario(4,{"environment":"ash_foundry","build_type":"bastion","position":"left"})
	for unused in 3: await physics_frame
	freeze(game)
	game.hud.hide()
	var vehicle=load("res://scenes/convoy_vehicle.tscn").instantiate()
	vehicle.game=game
	game.add_child(vehicle)
	vehicle.set_physics_process(false)
	vehicle.configure_trip(Vector2(1150,430),Vector2(900,3300),{"hp":600,"fuel":12,"ammo":40,"reserve":0,"cargo":{"steel":4}})
	vehicle.has_mg=false
	vehicle.velocity.x=90
	vehicle.wheel_phase=2.4
	vehicle.aim_angle=-0.12
	for worker in game.players: worker.position=vehicle.position
	for worker in game.players: vehicle.board_any(worker)
	for worker in game.players:
		var weapon = worker.get_node("WorkerWeapon")
		weapon._update_origin()
		weapon.aiming = worker.player_id>1
		weapon.aim_direction = Vector2.LEFT if worker.player_id==3 else Vector2.RIGHT
		weapon._aim_hold = 1.0
		weapon.queue_redraw()
		var visual=worker.get_node("PixelVisual")
		visual._process(.02)
		visual.queue_redraw()
	game.camera.position=Vector2(1150,377)
	game.camera.zoom=Vector2(3.2,3.2)
	game.camera.reset_smoothing()
	game.camera.force_update_scroll()
	for unused in 5: await process_frame
	await RenderingServer.frame_post_draw
	view.get_texture().get_image().save_png("res://artifacts/expedition/convoy-passengers.png")
	vehicle.vehicle_upgrades=["convoy_mg"]
	vehicle.has_mg=true
	vehicle.sync_replica()
	for worker in game.players:
		var weapon: WorkerWeapon=worker.get_node("WorkerWeapon")
		weapon._update_origin()
		weapon.aim_direction=Vector2(worker.facing,0)
		weapon.queue_redraw()
		worker.get_node("PixelVisual")._process(.02)
		worker.get_node("PixelVisual").queue_redraw()
	vehicle.sync_replica()
	for unused in 5: await process_frame
	await RenderingServer.frame_post_draw
	var error:=view.get_texture().get_image().save_png("res://artifacts/expedition/convoy-crew-close.png")
	print("CONVOY PREVIEW capture=",error)
	vehicle.facing=-1
	vehicle.aim_angle=-PI+0.1
	vehicle.sync_replica()
	for worker in game.players:
		var weapon: WorkerWeapon=worker.get_node("WorkerWeapon")
		weapon._update_origin()
		weapon.aim_direction=Vector2(worker.facing,0)
		weapon.queue_redraw()
		worker.get_node("PixelVisual")._process(.02)
		worker.get_node("PixelVisual").queue_redraw()
	for unused in 5: await process_frame
	await RenderingServer.frame_post_draw
	view.get_texture().get_image().save_png("res://artifacts/expedition/convoy-crew-left.png")
	await Cleanup.free_scene(game,self)
	quit(0 if error==OK else 1)
