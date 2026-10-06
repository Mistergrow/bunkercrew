extends SceneTree
## Accelerated real-scene campaign integration, not a human balance playtest.
## The scripted gunner uses real turret projectiles, finite crates and reloads.
## A named fixture quartermaster bypasses travel only: it collects actual drops,
## excavates real room terrain, pays shaft/room costs and runs ore/scrap -> steel
## -> ammunition with real timers. Excavated cargo and overflow remain in the world.
## The fixture worker is deliberately absent from game.players/player_count.
## The real gunner retains normal player physics, damage, knockback and knockout
## recovery. Scripted logistics and turret use stop whenever can_act() is false.

var game
var checks := 0
var shots := 0
var phase_history: Array[String] = []
var last_phase := ""
var gunner: Worker
var quartermaster: Worker
var test_start_msec := 0
var coop := "--coop" in OS.get_cmdline_user_args()
var stock_taken: Dictionary = {}
var gunner_stock_crates := 0
var crafted_crates := 0
var steel_collected := 0
var mined_ore := 0
var collected_scrap := 0
var rooms_built: Array[String] = []
var room_cells_mined: Dictionary = {}
var room_cells_expected: Dictionary = {}
var room_yield: Dictionary = {}
var room_cargo_dropped := 0
var mining_target
var ammo_press
var furnace
var gunner_damage := 0.0
var gunner_knockouts := 0
var last_gunner_hp := float(Balance.WORKER_HP)
var was_gunner_downed := false
var production
var flak_build_crates := 0
var flak_service_crates := 0
var flak_repairs := 0
var flak_tiers: Array[int] = []
var diagnostic_clock := 0.0
var flak_lowest_health_ratio := 1.0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> bool:
	if not value:
		push_error("FAILED: " + message)
		quit(1)
		return false
	checks += 1
	print("PASS ", message)
	return true

func create_game():
	paused = false
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	scene.start(2 if coop else 1)
	return scene

func find_supply(kind: String):
	for supply in get_nodes_in_group("supplies"):
		if supply.kind == kind and supply.amount > 0:
			return supply
	return null

func take_stock(worker: Worker, kind: String, delta: float) -> bool:
	var supply = find_supply(kind)
	if not is_instance_valid(supply) or worker.carried_count() >= worker.capacity():
		return false
	worker.global_position = supply.global_position + Vector2(-30, 0)
	var before: int = supply.amount
	supply.interact(worker, delta)
	var taken: int = before - supply.amount
	stock_taken[kind] = int(stock_taken.get(kind, 0)) + taken
	if worker == gunner and kind == "ammo":
		gunner_stock_crates += taken
	return true

func build_site(site, cost: Dictionary, delta: float) -> void:
	# Keep excavation products as real piles instead of silently clearing a full bag.
	for resource: String in quartermaster.inventory.keys():
		if not cost.has(resource):
			quartermaster.global_position = site.global_position + Vector2(-122, 0)
			var amount: int = quartermaster.inventory[resource]
			if game.drop_material(quartermaster, resource, amount):
				room_cargo_dropped += amount
			return
	for resource: String in cost:
		var missing := int(cost[resource]) - int(site.materials.get(resource, 0))
		if int(quartermaster.inventory.get(resource, 0)) < missing:
			take_stock(quartermaster, resource, delta)
			return
	quartermaster.global_position = site.global_position + Vector2(-32, 0)
	site.interact(quartermaster, delta)

func excavate_room(site, delta: float) -> bool:
	var field = site.get("excavation")
	if not is_instance_valid(field):
		return true
	if not room_cells_expected.has(site.kind):
		room_cells_expected[site.kind] = field.remaining_count()
		room_cells_mined[site.kind] = 0
	if field.is_cleared():
		return true
	for block in field.blocks:
		if not is_instance_valid(block) or block.depleted or block.is_queued_for_deletion():
			continue
		# Adjacent placement omits walking/jumping only. Line-of-sight, reach,
		# held work, actual solid-cell removal and material yield stay in MineBlock.
		for offset in [Vector2(-48,22), Vector2(48,22), Vector2(0,-27), Vector2(0,71)]:
			quartermaster.global_position = block.global_position + offset
			if not block.can_interact(quartermaster):
				continue
			block.interact(quartermaster, delta)
			if block.depleted:
				room_cells_mined[site.kind] += 1
				room_yield[block.kind] = int(room_yield.get(block.kind,0)) + block.yield_amount
			return false
	check(false, "The room excavation fixture must find a reachable exposed cell")
	return false

func recover_cores() -> void:
	for pickup in get_nodes_in_group("pickups"):
		if pickup.kind == "core" and pickup.amount > 0:
			quartermaster.global_position = pickup.global_position
			pickup._collect_upgrade_points()
			return

func work_logistics(delta: float) -> void:
	if not game.upgrades.has_upgrade("bunker_workshop"):
		recover_cores()
		game.upgrades.purchase("bunker_workshop")
	if not game.depth_unlocked:
		return
	if game.expansion.open_depths == 0:
		for site in get_nodes_in_group("excavation_sites"):
			if site.depth == 1:
				build_site(site,site.cost(),delta)
				return
	for kind in ["ammo_press","depot"]:
		for site in get_nodes_in_group("expansion_sites"):
			if site.kind==kind and not site.built:
				if not excavate_room(site,delta): return
				if not site.tech_ready(): return
				build_site(site,ExpansionSite.SPECS[kind].cost,delta)
				if site.built:
					rooms_built.append(kind)
					print("BUILT ",kind," t=",snappedf(game.elapsed,0.1)," stock_paid=",stock_taken)
				return
	if not is_instance_valid(ammo_press):
		ammo_press = production.station("ammo_press")
	# Keep the real ammunition chain alive while optional upgrade batches run.
	# One worker still performs at most one held material transfer per tick.
	var usable_ammo: int = game.turret.ammo+game.turret.reserve+int(gunner.inventory.get("ammo",0))*20
	if game.flak_station.built and usable_ammo<80 and is_instance_valid(ammo_press) and not ammo_press.working and ammo_press.output_amount==0:
		production.feed_ammo(delta)
		return
	if service_flak_construction(delta): return
	production.feed_ammo(delta)

func service_flak_construction(delta: float) -> bool:
	var console = game.flak_station
	if not console.available: return false
	# Ownership comes from a real first payment by P1. The logistical helper is
	# not a selected player and is never made owner or given any combat XP.
	if not is_instance_valid(console.builder):
		if gunner.can_act() and int(gunner.inventory.get("ammo",0))>0:
			gunner.position = console.position+Vector2(-32,0)
			gunner.selected_kind = "ammo"
			var before: int = gunner.inventory.ammo
			console.interact(gunner,delta)
			flak_build_crates += before-int(gunner.inventory.get("ammo",0))
			gunner.position = game.turret.position+Vector2(-29,0)
		return true
	if console.built and console.turret.hp<console.turret.max_hp-40:
		if production.ensure("steel",1,delta):
			quartermaster.position = console.position+Vector2(-32,0)
			quartermaster.selected_kind = "steel"
			var before: int = quartermaster.inventory.steel
			console.interact(quartermaster,delta)
			flak_repairs += before-int(quartermaster.inventory.get("steel",0))
		return true
	var wanted := 3 if game.rounds.wave>=16 else (2 if game.rounds.wave>=11 else 1)
	if console.tier>=wanted: return false
	if wanted==3 and game.expansion.open_depths<2:
		for site in get_nodes_in_group("excavation_sites"):
			if site.depth==2:
				production.build(site,site.cost(),delta)
				return true
		return true
	if wanted==3:
		for site in get_nodes_in_group("expansion_sites"):
			if site.kind=="alloy" and not site.built:
				if not excavate_room(site,delta): return true
				production.build(site,ExpansionSite.SPECS.alloy.cost,delta)
				if site.built:
					rooms_built.append("alloy")
					print("BUILT alloy t=",snappedf(game.elapsed,0.1)," stock_paid=",stock_taken)
				return true
	var tier_before: int = console.tier
	production.build(console,console.next_spec().cost,delta)
	if console.tier!=tier_before:
		flak_tiers.append(console.tier)
		print("BUILT FLAK ",console.tier," t=",snappedf(game.elapsed,0.1)," paid=",production.material_used," outputs=",production.outputs)
	return true

func refill_flak(delta: float) -> void:
	var console = game.flak_station
	if not console.built or not gunner.can_act() or console.turret.reserve>=40 or int(gunner.inventory.get("ammo",0))<=2:
		return
	gunner.position = console.position+Vector2(-32,0)
	gunner.selected_kind = "ammo"
	var before: int = gunner.inventory.ammo
	console.interact(gunner,delta)
	flak_service_crates += before-int(gunner.inventory.get("ammo",0))
	gunner.position = game.turret.position+Vector2(-29,0)

func make_steel(delta: float) -> void:
	if not is_instance_valid(furnace):
		for station in get_nodes_in_group("stations"):
			if station.kind == "furnace": furnace = station
	if not is_instance_valid(furnace) or furnace.working:
		return
	quartermaster.global_position = furnace.global_position + Vector2(-35, 0)
	if furnace.output_amount > 0:
		var before: int = furnace.output_amount
		furnace.interact(quartermaster, delta)
		steel_collected += before - furnace.output_amount
		return
	if int(quartermaster.inventory.get("ore", 0)) + int(quartermaster.inventory.get("scrap", 0)) > 0:
		furnace.interact(quartermaster, delta)
		return
	# At least the first batch comes from a real mined ore block. Later scrap is
	# recovered from the machines actually destroyed by the gunner.
	if mined_ore > 0:
		for pickup in get_nodes_in_group("pickups"):
			if pickup.kind == "scrap" and pickup.amount > 0:
				quartermaster.global_position = pickup.global_position
				var before: int = pickup.amount
				pickup.interact(quartermaster, delta)
				collected_scrap += before - pickup.amount
				return
	mine_ore(delta)

func mine_ore(delta: float) -> void:
	if not is_instance_valid(mining_target) or mining_target.is_queued_for_deletion():
		mining_target = null
		for block in get_nodes_in_group("mine_blocks"):
			if block.kind != "ore" or block.is_queued_for_deletion():
				continue
			for offset in [Vector2(48,22), Vector2(-48,22), Vector2(0,-27), Vector2(0,71)]:
				quartermaster.global_position = block.global_position + offset
				if block.can_interact(quartermaster):
					mining_target = block
					break
			if is_instance_valid(mining_target): break
	if not is_instance_valid(mining_target):
		return
	# Re-evaluate a reachable neighboring placement; no mine collision is disabled.
	for offset in [Vector2(48,22), Vector2(-48,22), Vector2(0,-27), Vector2(0,71)]:
		quartermaster.global_position = mining_target.global_position + offset
		if mining_target.can_interact(quartermaster): break
	mining_target.interact(quartermaster, delta)
	if mining_target.is_queued_for_deletion():
		mined_ore += mining_target.yield_amount

func refill_gunner(delta: float) -> void:
	if gunner.carried_count() >= gunner.capacity():
		return
	# Existing finite roof/depot crates are used first; empty sources remain empty.
	if take_stock(gunner, "ammo", delta):
		gunner.global_position = game.turret.global_position + Vector2(-29, 0)
		return
	if is_instance_valid(ammo_press) and ammo_press.output_amount > 0:
		gunner.global_position = ammo_press.global_position + Vector2(-32, 0)
		var before: int = ammo_press.output_amount
		ammo_press.interact(gunner, delta)
		crafted_crates += before - ammo_press.output_amount
	gunner.global_position = game.turret.global_position + Vector2(-29, 0)

func expected_kills() -> int:
	var total := 0
	for count in Balance.WAVE_COUNTS:
		total += int(ceil(count * (Balance.wave_multiplier(2) if coop else 1.0)))
	return total

func expected_phases() -> Array[String]:
	var result: Array[String] = []
	for wave in range(1, Balance.TOTAL_WAVES + 1):
		for phase in ["build", "warning", "attack"]:
			result.append("%s_%d" % [phase, wave])
		result.append("%s_%d" % ["victory" if wave == Balance.TOTAL_WAVES else "salvage", wave])
	return result

func run() -> void:
	seed(27)
	Engine.time_scale = 10.0
	test_start_msec = Time.get_ticks_msec()
	game = create_game()
	if not check(game.players.size() == (2 if coop else 1), "Actual main scene creates the requested independent player count"): return
	gunner = game.players[0]
	gunner.position = game.turret.position + Vector2(-29, 0)
	quartermaster = Worker.new()
	quartermaster.name = "FixtureQuartermaster_TravelOmitted"
	quartermaster.game = game
	game.add_child(quartermaster)
	quartermaster.set_physics_process(false)
	production = preload("res://tests/campaign_production.gd").new()
	production.setup(self)
	if not check(not game.players.has(quartermaster) and game.player_count == (2 if coop else 1), "Accounted-material logistics fixture does not inflate the selected solo/coop enemy count"): return
	for i in range(gunner.capacity()):
		take_stock(gunner, "ammo", Balance.TRANSFER_TIME + 0.01)
	gunner.position = game.turret.position + Vector2(-29, 0)
	game.turret.enter(gunner)
	if not check(gunner.inventory.get("ammo", 0) == gunner.capacity() and gunner_stock_crates == gunner.capacity(), "Gunner starts with six accounted ammo crates from the finite roof supply"): return
	var delta := Engine.time_scale / float(Engine.physics_ticks_per_second)
	while game.rounds.running and game.elapsed < 5000:
		await physics_frame
		gunner_damage += maxf(0.0, last_gunner_hp-gunner.hp)
		last_gunner_hp = gunner.hp
		if gunner.is_downed() and not was_gunner_downed:
			gunner_knockouts += 1
			print("GUNNER KNOCKOUT wave=", game.rounds.wave, " t=", snappedf(game.elapsed,0.1))
		was_gunner_downed = gunner.is_downed()
		if game.rounds.phase != last_phase:
			last_phase = game.rounds.phase
			phase_history.append("%s_%d" % [last_phase, game.rounds.wave])
			print("PHASE ", last_phase, " wave=", game.rounds.wave, " t=", snappedf(game.elapsed, 0.1), " core=", game.core.hp, " ammo=", game.turret.ammo, " crafted=", crafted_crates)
		if game.rounds.running:
			work_logistics(delta)
			if gunner.can_act():
				refill_gunner(delta)
				refill_flak(delta)
		var turret = game.turret
		if gunner.can_act() and not is_instance_valid(turret.occupant):
			turret.enter(gunner)
		if gunner.can_act() and turret.ammo == 0 and turret.reload_timer <= 0:
			turret.start_reload()
		var target
		var nearest_x := INF
		for enemy in get_nodes_in_group("enemies"):
			if enemy.is_in_group("air_enemies"): continue
			if enemy.global_position.x < nearest_x:
				target = enemy
				nearest_x = enemy.global_position.x
		if gunner.can_act() and is_instance_valid(target):
			var aim: Vector2 = target.get_node("MachineHitbox").global_position - (turret.global_position + turret.PIVOT)
			turret.aim_angle = clampf(aim.angle(), deg_to_rad(-10), deg_to_rad(65))
			if turret.fire(): shots += 1
		if game.flak_station.built:
			var gun = game.flak_station.turret
			flak_lowest_health_ratio = minf(flak_lowest_health_ratio,gun.hp/gun.max_hp)
		diagnostic_clock += delta
		if diagnostic_clock>=90:
			diagnostic_clock = 0
			print("LOGISTICS wave=",game.rounds.wave," task=",production.diagnostic," cargo=",quartermaster.inventory," flak=",game.flak_station.tier," flakHP=",game.flak_station.turret.hp if game.flak_station.built else 0," flakammo=",game.flak_station.turret.ammo+game.flak_station.turret.reserve if game.flak_station.built else 0)

		if Time.get_ticks_msec() - test_start_msec > 480000:
			push_error("Campaign victory watchdog exceeded 480 real seconds")
			quit(1)
			return
	if phase_history.is_empty() or phase_history[-1] != "victory_%d" % Balance.TOTAL_WAVES:
		phase_history.append("%s_%d" % [game.rounds.phase, game.rounds.wave])
	if not check(game.rounds.phase == "victory" and game.core.hp > 0, "Actual projectile combat wins all twenty waves with finite material supplies"): return
	var minimum_duration: float = Balance.BUILD_TIMES.reduce(func(total, seconds): return total + seconds, 0.0) + Balance.TOTAL_WAVES * Balance.WARNING_TIME + (Balance.TOTAL_WAVES-1) * Balance.SALVAGE_TIME
	if not check(game.elapsed >= minimum_duration, "All twenty construction pauses and warning/salvage intervals run without skipping (%.1f simulated seconds)" % game.elapsed): return
	if not check(game.stats.kills == expected_kills() and shots > 0, "All %d machines die through projectile combat (%d shots)" % [expected_kills(), shots]): return
	if not check(gunner.progression.kills == game.stats.kills and gunner.progression.level > 1 and gunner.max_hp == Balance.WORKER_HP + (gunner.progression.level-1)*PlayerProgression.HP_PER_LEVEL, "Every ground/flak kill credits the real firing worker or first-paying builder and grants cumulative level health"): return
	if coop and not check(game.players[1].progression.kills == 0 and game.players[1].progression.level == 1, "The inactive local partner receives no duplicated personal kill credit or XP"): return
	if not check(phase_history == expected_phases(), "Complete build/warning/attack/salvage sequence reaches wave twenty victory"): return
	if not check(game.expansion.open_depths==2 and rooms_built.has("ammo_press") and rooms_built.has("depot") and rooms_built.has("alloy") and stock_taken.get("steel",0)==6 and stock_taken.get("concrete",0)==8, "Both shafts, ammunition press, depot and alloy works use finite starting supplies and real extra production"): return
	if not check(room_cells_expected.size()==3 and room_cells_mined==room_cells_expected and ["ammo_press","depot","alloy"].all(func(kind): return int(room_cells_mined.get(kind,0))==12), "All three production rooms were physically excavated through twelve real held-mining cells each"): return
	var world_sand := 0
	for pickup in get_nodes_in_group("pickups"):
		if pickup.kind == "sand": world_sand += pickup.amount
	if not check(room_cargo_dropped>0 and world_sand+int(quartermaster.inventory.get("sand",0))+int(production.ingredient_used.get("sand",0)) == int(room_yield.get("sand",0))+int(stock_taken.get("sand",0))+int(production.mined.get("sand",0)), "Excavation sand remains in world/cargo or enters real concrete/glass production without material loss"): return
	if not check(game.upgrades.has_upgrade("bunker_workshop") and game.upgrades.earned >= 2 and game.upgrades.points == game.upgrades.earned-2, "The workshop unlock is paid with recovered enemy cores"): return
	if not check(crafted_crates > 0 and mined_ore > 0 and collected_scrap > 0 and steel_collected >= crafted_crates, "Mined ore and recovered scrap became steel and %d usable crafted ammo boxes" % crafted_crates): return
	var flak = game.flak_station.turret
	if not check(flak_tiers==[1,2,3] and game.flak_station.builder==gunner and flak.builder==gunner and quartermaster.progression.kills==0, "All three flak tiers were paid in order and ownership remains with the real first-paying player"): return
	if not check(int(production.outputs.get("glass",0))>=5 and int(production.outputs.get("alloy",0))>=3 and int(production.outputs.get("concrete",0))>=2 and int(production.mined.get("tungsten",0))>0, "Actual sand/lime, mined tungsten and steel produce the glass/alloy/concrete needed by paid flak expansion"): return
	if not check(flak_build_crates==1 and 20+flak_service_crates*20-flak.flash_tick==flak.ammo+flak.reserve, "Flak rounds are accounted for by its paid build crate and real resupply; upgrades add no free ammunition"): return
	var consumed_crates := gunner_stock_crates + crafted_crates - int(gunner.inventory.get("ammo",0))
	if not check(int(Balance.MAGAZINE) + consumed_crates*20 - shots - flak.flash_tick == game.turret.ammo + game.turret.reserve + flak.ammo + flak.reserve, "Every fired or remaining roof/flak round is accounted for by initial ammunition and consumed crates"): return
	print("VICTORY DETAIL mode=", "coop" if coop else "solo", " simulated_seconds=", snappedf(game.elapsed,0.1), " core=", game.core.hp, " shots=", shots, " kills=", game.stats.kills, " stock_crates=", gunner_stock_crates, " crafted_crates=", crafted_crates, " smelted_steel=", steel_collected, " mined_ore=", mined_ore, " recovered_scrap=", collected_scrap, " stock_paid=", stock_taken, " excavated_cells=", room_cells_mined, " excavation_yield=", room_yield, " dropped_excavation_cargo=", room_cargo_dropped, " wall_hp=", get_nodes_in_group("walls").map(func(w): return w.hp), " gunner_damage=", gunner_damage, " gunner_knockouts=", gunner_knockouts, " gunner_hp=", gunner.hp, " gunner_max_hp=",gunner.max_hp," gunner_level=",gunner.progression.level," personal_kills=",gunner.progression.kills," flak_shots=",flak.flash_tick," flak_crates=",flak_build_crates+flak_service_crates," flak_repairs=",flak_repairs," flak_lowest_health_ratio=",flak_lowest_health_ratio," extra_production=",production.outputs)
	# Exercise the actual restart API, then let the new scene suffer a real defeat.
	var previous_game_id: int = game.get_instance_id()
	game.restart()
	for frame in 5: await process_frame
	game = current_scene
	if not check(is_instance_valid(game) and game.get_instance_id() != previous_game_id and game.started and game.player_count==(2 if coop else 1) and game.core.hp == Balance.CORE_HP, "Victory restart loads a fresh playable scene, intact core and the original party"): return
	game.rounds.begin_warning()
	while game.rounds.running and game.elapsed < 600:
		await physics_frame
		if Time.get_ticks_msec() - test_start_msec > 540000:
			push_error("Campaign defeat watchdog exceeded 540 real seconds")
			quit(1)
			return
	if not check(game.rounds.phase == "defeat" and game.core.hp == 0, "Unattended machines breach actual walls, enter the bunker and destroy its core"): return
	if not check(get_nodes_in_group("walls").all(func(w): return not w.is_blocking()), "All defensive walls were genuinely destroyed before core defeat"): return
	print("DEFEAT DETAIL simulated_seconds=", game.elapsed, " enemies=", get_nodes_in_group("enemies").size())
	# Defeat restart must also produce a playable build phase without process restart.
	previous_game_id = game.get_instance_id()
	game.restart()
	for frame in 5: await process_frame
	game = current_scene
	if not check(game.get_instance_id() != previous_game_id and game.rounds.wave == 1 and game.rounds.phase == "build" and game.rounds.running and game.core.hp == Balance.CORE_HP, "Defeat restart begins a fresh playable first wave"): return
	print("INTEGRATED CAMPAIGN CHECKS PASSED: ", checks)
	paused = false
	await preload("res://tests/scene_cleanup.gd").free_scene(game,self)
	quit(0)
