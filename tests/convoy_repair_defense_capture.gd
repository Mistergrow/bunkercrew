extends SceneTree
## Actual four-person departure and tire defense. Only scenario completion,
## research/cargo and the approach position are prepared; all trip transitions,
## enemy spawns, service input and defense shots run through production code.
const OUTPUT := "res://artifacts/expedition-production/actual"
const Cleanup := preload("res://tests/scene_cleanup.gd")
const Journey := preload("res://scripts/convoy_journey.gd")
const Controller := preload("res://scripts/expedition_controller.gd")
var game
var checks := 0
var failures := 0
var captures: Array[Dictionary] = []
var evidence: Dictionary = {}

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func wait_for_world(old_id: int, stage: String, phase: String = "", timeout_ms: int = 12000) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if not is_instance_valid(current_scene) or current_scene.get_instance_id() == old_id:
			continue
		game = current_scene
		if game.started and game.expedition.stage == stage:
			if phase.is_empty() or game.expedition.vehicle.journey_state.phase == phase:
				return true
	return false

func guards() -> Array:
	return get_nodes_in_group("enemies").filter(func(enemy):
		return enemy.game == game and bool(enemy.get_meta("expedition_guard", false)) and not enemy.dead)

func mg_rounds(truck: Node) -> int:
	# An unopened cargo pack contains twenty rounds in ConvoyVehicle.refill_ammo.
	return int(truck.ammo) + int(truck.reserve) + int(truck.open_pack) + 20 * int(truck.cargo.get("ammo", 0))

func settle_hud() -> void:
	game.notice_time = 0
	game.hud.combat_overlay.banners.clear()
	game.hud.chat_panel._process(0.0)
	game.hud._process(0.0)

func capture(name: String, resolution: Vector2i, locale: String) -> void:
	LocaleText.set_locale(locale, false)
	root.size = resolution
	for unused in 3:
		await process_frame
	settle_hud()
	game.expedition._sync_vehicle()
	game.player_camera.update_view(0, true)
	game.camera.force_update_scroll()
	# Pause happened on the real input/shot frame, before cosmetic _process.
	# Refresh drawings from that unchanged state so the frozen muzzle flashes
	# and the current mounted/service rig match the already recorded shots.
	var vehicle = game.expedition.vehicle
	if is_instance_valid(vehicle):
		vehicle.visual.queue_redraw()
		vehicle.weapon_visual.queue_redraw()
		vehicle.get_node("ConvoyPresentation").queue_redraw()
		vehicle.queue_redraw()
	for worker in game.players:
		worker.get_node("PixelVisual")._process(0.0)
		worker.get_node("PixelVisual").queue_redraw()
		worker.get_node("WorkerWeapon").queue_redraw()
	for node in game.get_children():
		if node.get_script() != null and node.get_script().resource_path == "res://scripts/expedition_road_art.gd":
			node.depth._update_view()
			node.queue_redraw()
	if is_instance_valid(game.hud.expedition_panel):
		game.hud.expedition_panel._refresh()
		game.hud.expedition_panel.queue_redraw()
	for unused in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	var path := OUTPUT + "/" + name + ".png"
	var image := root.get_texture().get_image()
	check(image.save_png(path) == OK, "Save actual gameplay capture " + name)
	check(image.get_size() == resolution, "Actual physical window capture matches " + str(resolution))
	var truck = game.expedition.vehicle
	var item := {"file": "actual/" + name + ".png", "locale": locale, "resolution": [resolution.x, resolution.y], "stage": game.expedition.stage, "overlay": game.hud.overlay, "tree_paused_for_capture": paused, "guard_count": guards().size()}
	if is_instance_valid(truck):
		item["vehicle_position"] = [truck.position.x, truck.position.y]
		item["fuel"] = truck.fuel
		item["max_fuel"] = truck.max_fuel
		item["zoom"] = game.camera.zoom.x
		item["journey_state"] = truck.journey_state.duplicate(true)
		item["mg_ammo"] = truck.ammo
		item["repairer_interacting"] = game.players[0]._interacting
		item["repairer_focus_is_vehicle"] = game.players[0].focus == truck
		item["mg_flash"] = truck.flash
		item["seat_player_ids"] = truck.seats.map(func(seat): return seat.occupant.player_id if is_instance_valid(seat.occupant) else 0)
	captures.append(item)

func finish() -> void:
	key(KEY_E, false)
	for action in ["p2_fire", "p3_fire", "p4_fire"]:
		Input.action_release(action)
	paused = false
	if is_instance_valid(game):
		await Cleanup.free_scene(game, self)
	var output := FileAccess.open(OUTPUT + "/capture.json", FileAccess.WRITE)
	output.store_string(JSON.stringify({"fixture": "Prepared wave20 victory, 30 research points, finite ammo/steel cargo and x1740 approach. Actual departure, four seat boards, countdown/scene reload/start, tire guard spawn, physical E service input and held fire actions. Damage limited only after actual guard spawn; scene paused at a real firing/service moment for translated/resized captures.", "renderer": RenderingServer.get_video_adapter_name(), "checks": checks, "passed": checks - failures, "evidence": evidence, "captures": captures}, "\t"))
	output.close()
	print("ACTUAL CONVOY TIRE DEFENSE: %d/%d passed; %d native captures" % [checks - failures, checks, captures.size()])
	quit(1 if failures else 0)

func run() -> void:
	if DisplayServer.get_name() == "headless" or "--no-profile-save" not in OS.get_cmdline_user_args():
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	root.size = Vector2i(1920, 1080)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.selected_characters = PartyConfig.normalize_characters(["mara", "branko", "ivo", "mara"])
	game.start_scenario(4, {"environment": "ash_foundry", "position": "left", "build_type": "bastion"})
	game.rounds.running = false
	game.rounds.wave = 20
	game.upgrades.points = 30
	game.players[0].inventory = {"ammo": 2, "steel": 4}
	check(game.expedition.on_victory(), "Real completed mission unlocks the garage")
	check(game.upgrades.purchase("convoy_mg"), "Actual research fits the convoy MG")
	check(game.expedition.handle_command("prepare", {}, 1), "Actual garage opens its expedition panel")
	check(game.expedition.handle_command("route", {"id": "harbor"}, 1), "Choose actual harbor route")
	check(game.expedition.handle_command("stop", {"id": "harbor:fuel"}, 1), "Choose actual fuel depot")
	check(game.expedition.handle_command("load", {"kind": "ammo", "amount": 2}, 1), "Load finite travel ammunition")
	check(game.expedition.handle_command("load", {"kind": "steel", "amount": 4}, 1), "Load finite repair steel")
	for person in game.players:
		person.set_physics_process(false)
		person.global_position = game.expedition.vehicle.global_position + Vector2(-75 + person.player_id * 12, 0)
	var garage_id: int = game.get_instance_id()
	check(game.expedition.handle_command("depart", {}, 1), "Departure starts actual boarding")
	game.players[0].preferred_focus = game.expedition.vehicle
	game.players[0].focus = game.expedition.vehicle
	paused = true
	await capture("boarding-de-1920", Vector2i(1920, 1080), "de")
	paused = false
	for person in game.players:
		check(game.expedition.vehicle.board(person, game.expedition.vehicle.SEAT_ROLES[person.player_id - 1]), "Actual Seat.board accepts crew slot " + str(person.player_id))
	evidence["garage_scene_id"] = garage_id
	evidence["garage_seat_player_ids"] = game.expedition.vehicle.seats.map(func(seat): return seat.occupant.player_id)
	var departed: bool = await wait_for_world(garage_id, "travel", "driving")
	check(departed, "Real 1.2s countdown, scene reload and 0.8s engine start reach driving")
	if not departed:
		await finish()
		return
	evidence["travel_scene_id"] = game.get_instance_id()
	evidence["after_reload_seat_player_ids"] = game.expedition.vehicle.seats.map(func(seat): return seat.occupant.player_id if is_instance_valid(seat.occupant) else 0)
	check(evidence.after_reload_seat_player_ids == [1, 2, 3, 4], "Actual scene handoff preserves four distinct seat owners")
	var truck = game.expedition.vehicle
	var before_reload: int = mg_rounds(truck)
	key(KEY_DELETE, true)
	for unused in 2:
		await physics_frame
	key(KEY_DELETE, false)
	var reload_deadline := Time.get_ticks_msec() + 3000
	while truck.ammo == 0 and Time.get_ticks_msec() < reload_deadline:
		await process_frame
	check(truck.ammo > 0 and truck.reload_timer == 0, "Real gunner reload input fills the MG from finite cargo")
	check(mg_rounds(truck) == before_reload, "Actual MG reload conserves finite rounds across magazine/reserve/packs")
	evidence["mg_reload"] = {"key": "KEY_DELETE", "rounds_before": before_reload, "rounds_after": mg_rounds(truck), "loaded": truck.ammo, "remaining_cargo_ammo": truck.cargo.get("ammo", 0)}
	truck.position.x = Controller.ROAD_START + (Controller.ROAD_END - Controller.ROAD_START) * Journey.BREAKDOWN_PROGRESS + .1
	var deadline := Time.get_ticks_msec() + 3000
	while truck.journey_state.phase != "repair" and Time.get_ticks_msec() < deadline:
		await process_frame
	check(truck.journey_state.phase == "repair" and absf(truck.position.x - 1740.0) < .5, "Production threshold stops at x1740 and begins the tire mission")
	check(guards().size() >= 3, "The actual tire mission spawns live guarding attackers")
	if truck.journey_state.phase != "repair" or guards().is_empty():
		await finish()
		return
	evidence["spawned_guards"] = guards().map(func(enemy): return {"id": enemy.get_instance_id(), "kind": enemy.kind, "x": enemy.position.x, "hp": enemy.hp, "target_is_vehicle": enemy.target == truck})
	# Keep the real enemies and their attack/movement callbacks running. Reducing
	# their damage preserves readable crew/tool poses through the capture setup.
	for enemy in guards():
		enemy.attack_damage = minf(enemy.attack_damage, 1.0)
	evidence["fixture_enemy_damage_ceiling"] = 1.0
	check(not is_instance_valid(game.players[0].mounted_turret), "Breakdown really dismounts the driver beside the rear wheel")
	check(truck.can_service(game.players[0]), "Auto-dismounted driver can reach the actual repair service point")
	game.hud.overlay = ""
	game.player_camera.set_zoom(1.25)
	var before_work: float = truck.journey_state.repair_work
	key(KEY_E, true)
	deadline = Time.get_ticks_msec() + 3500
	while float(truck.journey_state.repair_work) < .30 and truck.journey_state.repair_step == "jack" and Time.get_ticks_msec() < deadline:
		await process_frame
	check(game.players[0]._interacting and game.players[0].focus == truck and truck.journey_state.repair_work > before_work, "Physical E through the real player input performs tool work")
	check(truck.journey_state.repair_operator == 1, "Actual tire service records the driver as repair operator")
	evidence["service_input"] = {"key": "KEY_E", "before_work": before_work, "after_work": truck.journey_state.repair_work, "repair_step": truck.journey_state.repair_step, "operator": truck.journey_state.repair_operator, "player_focus_is_vehicle": game.players[0].focus == truck}
	var mg_before: int = truck.ammo
	var mg_shots_before: int = truck.flash_tick
	var mg_rounds_before: int = mg_rounds(truck)
	var side_weapon = game.players[3].get_node("WorkerWeapon")
	var rear_weapon = game.players[2].get_node("WorkerWeapon")
	var side_before: int = side_weapon.current_ammo()
	var rear_before: int = rear_weapon.current_ammo()
	truck.aim_angle = .12
	side_weapon._aim_pitch = .06
	for action in ["p2_fire", "p3_fire", "p4_fire"]:
		Input.action_press(action)
	deadline = Time.get_ticks_msec() + 2000
	while (truck.flash_tick == mg_shots_before or side_weapon.current_ammo() == side_before or rear_weapon.current_ammo() == rear_before) and Time.get_ticks_msec() < deadline:
		await process_frame
	check(truck.flash_tick > mg_shots_before and truck.ammo < mg_before, "Gunner input fires a real convoy MG shot during tool work")
	check(mg_rounds_before - mg_rounds(truck) == truck.flash_tick - mg_shots_before, "Each actual MG shot consumes exactly one finite round")
	check(side_weapon.current_ammo() < side_before, "Side passenger input fires a real personal weapon during tool work")
	check(rear_weapon.current_ammo() < rear_before, "Rear passenger input fires a real personal covering shot during tool work")
	check(truck.journey_state.phase == "repair" and truck.journey_state.repair_operator == 1, "Actual defense shots overlap the actual service mission")
	evidence["defense_shots"] = {"mg_ammo_before": mg_before, "mg_ammo_after": truck.ammo, "mg_rounds_before": mg_rounds_before, "mg_rounds_after": mg_rounds(truck), "mg_shots_before": mg_shots_before, "mg_shots_after": truck.flash_tick, "side_ammo_before": side_before, "side_ammo_after": side_weapon.current_ammo(), "rear_ammo_before": rear_before, "rear_ammo_after": rear_weapon.current_ammo(), "side_shot_index": side_weapon._shot_index, "rear_shot_index": rear_weapon._shot_index, "mg_flash": truck.flash, "side_flash": side_weapon.flash, "rear_flash": rear_weapon.flash}
	paused = true
	for resolution in [Vector2i(1920, 1080), Vector2i(960, 600)]:
		for locale in ["de", "en"]:
			await capture("defense-%s-%d" % [locale, resolution.x], resolution, locale)
	key(KEY_E, false)
	for action in ["p2_fire", "p3_fire", "p4_fire"]:
		Input.action_release(action)
	paused = false
	key(KEY_M, true)
	await process_frame
	key(KEY_M, false)
	check(game.hud.overlay == "expedition" and paused, "Actual M input opens and pauses the mission map")
	for resolution in [Vector2i(1920, 1080), Vector2i(960, 600)]:
		for locale in ["de", "en"]:
			await capture("map-%s-%d" % [locale, resolution.x], resolution, locale)
	check(is_instance_valid(game.hud.expedition_panel) and game.hud.expedition_panel.garage_button.visible and not game.hud.expedition_panel.garage_button.disabled, "Mission map exposes its actual enabled garage-return action")
	var road_id: int = game.get_instance_id()
	game.hud.expedition_panel.garage_button.pressed.emit()
	var returned: bool = await wait_for_world(road_id, "preparation")
	check(returned, "Pressing the actual garage button reloads the secured departure garage")
	evidence["garage_return"] = {"departed_scene_id": road_id, "returned_scene_id": game.get_instance_id() if returned else 0, "actual_button_signal": "ExpeditionPanel.garage_button.pressed", "stage": game.expedition.stage, "finite_garage_stock": game.campaign.expedition.garage_stock.duplicate(true)}
	if returned:
		for locale in ["de", "en"]:
			await capture("returned-garage-%s-1920" % locale, Vector2i(1920, 1080), locale)
	check(captures.all(func(item): return not item.has("fuel") or (float(item.fuel) >= 0.0 and float(item.fuel) <= float(item.max_fuel))), "All actual captured fuel values remain within their real tank capacity")
	await finish()
