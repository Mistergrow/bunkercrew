extends SceneTree
## Real main-scene workers, projectiles and enemies exercise the new enclosure.
## Wave/research and cargo are arranged; all construction uses held InputMap E.

const DOME = preload("res://scripts/dome_controller.gd")
const PANE = preload("res://scripts/dome_segment.gd")
var game
var dome
var worker
var partner
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, label: String) -> void:
	checks += 1
	print("DOME %s: %s" % ["PASS" if value else "FAIL", label])
	if not value:
		failures += 1
		push_error(label)

func step(frames: int = 3) -> void:
	for _frame in frames:
		await physics_frame

func hold(action: String, seconds: float) -> void:
	Input.action_press(action)
	await create_timer(seconds, false, true).timeout
	Input.action_release(action)
	await step()

func load_cargo(player, cargo: Dictionary) -> void:
	player.inventory.clear()
	for kind: String in cargo:
		player.add_item(kind, int(cargo[kind]))

func enemy_at(at: Vector2):
	var enemy = load("res://scenes/enemy.tscn").instantiate()
	enemy.game = game
	enemy.position = at
	game.add_child(enemy)
	enemy.set_physics_process(false)
	return enemy

func run() -> void:
	Engine.time_scale = 3.0
	Engine.physics_ticks_per_second = 180
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	# Construction timings and eight-slot harness assertions use neutral stats.
	# Branko's larger inventory and slower work are covered by progression tests.
	game.selected_characters.assign(["mara", "mara"])
	game.start(2)
	game.rounds.set_process(false)
	dome = game.get("dome")
	if not is_instance_valid(dome):
		dome = DOME.new()
		dome.game = game
		game.add_child(dome)
	worker = game.players[0]
	partner = game.players[1]
	worker.position = Vector2(1240, 430)
	partner.position = Vector2(1235, 430)
	await step()
	check(not dome.available and not dome.visible and not dome.can_interact(worker), "The late dome is hidden and cannot intercept early-game interactions")
	game.rounds.wave = 14
	dome.unlock()
	check(not dome.available, "Calling unlock early cannot expose the late construction site")
	game.rounds.wave = 15
	dome.unlock()
	check(not dome.available, "Wave fifteen must actually finish before the site appears")
	game.rounds.phase = "salvage"
	game._round_phase_changed()
	dome.unlock()
	dome.unlock()
	await step()
	check(dome.available and dome.visible and dome.segments.size() == 13 and not dome.built, "After wave fifteen, repeated unlock exposes twelve curved roof panels and one front portal")
	var roof_panels: Array = dome.segments.filter(func(pane): return not pane.front_line)
	check(roof_panels.size() == 12 and roof_panels.all(func(pane): return pane.curve.size() == 7), "Twelve independently damageable panels form a smooth seventy-two-edge roof")
	check(roof_panels[0].to_global(roof_panels[0].curve[0]).is_equal_approx(Vector2(75,245)) and roof_panels[-1].to_global(roof_panels[-1].curve[-1]).is_equal_approx(Vector2(1290,245)), "The ellipse springs from the real hilltop and the raised front portal")
	var roof_geometry_valid := true
	var roof_stays_above_soil := true
	var apex := INF
	for pane in roof_panels:
		roof_geometry_valid = roof_geometry_valid and not Geometry2D.triangulate_polygon(pane.polygon).is_empty()
		for point in pane.polygon:
			roof_stays_above_soil = roof_stays_above_soil and pane.to_global(point).y <= 245.01
		for point in pane.curve:
			var world_point: Vector2 = pane.to_global(point)
			var normalized: Vector2 = (world_point - Vector2(682.5,245)) / Vector2(607.5,190)
			roof_geometry_valid = roof_geometry_valid and absf(normalized.length_squared() - 1.0) < 0.0001
			apex = minf(apex, world_point.y)
	check(roof_geometry_valid and is_equal_approx(apex,55.0), "Every roof point lies on the true ellipse and every curved collision strip triangulates")
	check(roof_stays_above_soil, "No roof glass or curve section descends into the hill or buried bunker wall")
	check(game.view_stage == 4 and game.camera_target_zoom == 0.48, "The real salvage transition exposes the expanded dome yard and final camera framing")
	check(worker.focus == dome and dome.prompt(worker).contains("Welle 16"), "The outside assembly console is reachable and explains its wave requirement")
	load_cargo(worker, {"steel": 2})
	await hold("p1_interact", 0.7)
	check(worker.inventory.get("steel", 0) == 2 and dome.materials.is_empty(), "Early-wave interaction preserves materials")
	game.rounds.wave = Balance.DOME_WAVE
	await hold("p1_interact", 0.7)
	check(worker.inventory.get("steel", 0) == 2 and dome.prompt(worker).contains("FESTUNG"), "Wave sixteen still requires fortress research before construction")
	game.upgrades.owned["bunker_fortress"] = true
	await hold("p1_interact", 0.75)
	check(worker.carried_count() == 0 and dome.materials.get("steel", 0) == 2 and not dome.frame_built, "Partial steel delivery remains safely buffered at the dome")
	load_cargo(partner, {"steel": 2})
	await hold("p2_interact", 0.75)
	check(partner.carried_count() == 0 and dome.materials.get("steel", 0) == 4, "The second worker contributes to the same conserved construction buffer")
	await hold("p1_interact", 1.3)
	check(not dome.frame_built and dome.materials.get("steel", 0) == 4, "Ordinary steel alone cannot replace the required deep-mine armor alloy")
	load_cargo(worker, {"alloy": 2})
	await hold("p1_interact", 0.75)
	load_cargo(partner, {"alloy": 2})
	await hold("p2_interact", 0.75)
	check(dome.materials.get("alloy", 0) == 4 and worker.carried_count() + partner.carried_count() == 0, "Four armor-alloy units are conserved across separate deliveries")
	await hold("p1_interact", 1.3)
	check(dome.frame_built and not dome.built and dome.segments.all(func(pane): return pane.stage == PANE.Stage.FRAME and pane.collider.disabled), "Paid steel becomes visible framing without pretending open scaffolds are glass")
	load_cargo(worker, {"glass": 6})
	await hold("p1_interact", 1.9)
	check(dome.materials.get("glass", 0) == 6 and worker.carried_count() == 0 and not dome.built, "A full six-slot glass load is buffered without completing the twelve-glass recipe")
	game.upgrades.owned["harness"] = true
	load_cargo(partner, {"glass": 8})
	await hold("p2_interact", 1.95)
	check(partner.capacity() == 8 and partner.inventory.get("glass", 0) == 2 and dome.materials.get("glass", 0) == 12, "An eight-slot delivery fills only missing glass and preserves its two surplus units")
	await hold("p1_interact", 0.65)
	var glazed: int = dome.segments.filter(func(pane): return pane.stage == PANE.Stage.GLASS).size()
	check(glazed > 0 and glazed < 13 and not dome.built, "Glazing installs individually visible and collidable panes progressively")
	await hold("p1_interact", 1.6)
	check(dome.built and dome.front.hp == 1200 and dome.segments.all(func(pane): return pane.is_blocking() and pane.colliders.all(func(shape): return not shape.disabled)), "Steel, armor alloy and twelve glass finish a physically collidable 1200-HP front")
	check(dome.materials.get("steel", 0) == 4 and dome.materials.get("alloy", 0) == 4 and dome.materials.get("glass", 0) == 12 and worker.carried_count() + partner.carried_count() == 2, "The staged build consumes its exact twenty-unit recipe and leaves surplus cargo intact")
	partner.take_item("glass", 2)
	check(dome.front.is_in_group("walls") and dome.segments.filter(func(pane): return pane.is_in_group("walls")).size() == 1, "Only the reachable ground front becomes an enemy path obstacle")
	load_cargo(worker, {"glass": 1})
	await hold("p1_interact", 1.1)
	check(worker.inventory.get("glass", 0) == 1 and dome.front.hp == 1200, "Holding work on an intact dome cannot waste repair glass")
	check(dome.cover_height(600) < 90 and dome.cover_height(1195) < 300 and is_inf(dome.cover_height(1340)), "Weather cover reaches beyond the expanded bunker while the exterior remains open")
	check([75, 250, 600, 1000, 1195].all(func(x): return not is_inf(dome.cover_height(x))) and dome.front.global_position.x == 1290, "The dome covers the entire bunker footprint from x75 to x1195")
	var farthest := -INF
	for pane in dome.segments:
		for shape: PackedVector2Array in pane.polygons:
			for vertex in shape:
				farthest = maxf(farthest, pane.to_global(vertex).x)
	check(farthest > 1290 and dome.front.polygons.size() == 2, "Physical glazing extends beyond the enlarged bunker and frames a real two-piece opening")
	var port_ray := PhysicsRayQueryParameters2D.create(Vector2(735, 206), Vector2(1290, 390), 1 | 2)
	check(game.get_world_2d().direct_space_state.intersect_ray(port_ray).is_empty(), "The turret-to-front ray crosses the actual empty firing window at y390")
	var high_port_ray := PhysicsRayQueryParameters2D.create(Vector2(735,206),Vector2(1290,320),1|2)
	check(game.get_world_2d().direct_space_state.intersect_ray(high_port_ray).is_empty(), "The widened real firing window also allows elevated shots toward heavy machines")
	var upper_port_glass := PhysicsRayQueryParameters2D.create(Vector2(1240,280),Vector2(1340,280),2)
	var lower_port_glass := PhysicsRayQueryParameters2D.create(Vector2(1240,410),Vector2(1340,410),2)
	check(game.get_world_2d().direct_space_state.intersect_ray(upper_port_glass).get("collider") == dome.front and game.get_world_2d().direct_space_state.intersect_ray(lower_port_glass).get("collider") == dome.front, "Physical upper and lower portal glazing still block shots outside the opening")
	var upper = dome.segments[5]
	var behind_glass = enemy_at(Vector2(600, 35))
	await step()
	var upper_hp: float = upper.hp
	var protected_hp: float = behind_glass.hp
	var blocked = load("res://scenes/projectile.tscn").instantiate()
	blocked.game = game
	blocked.position = Vector2(600, 180)
	blocked.direction = Vector2.UP
	game.add_child(blocked)
	await step(12)
	check(upper.hp == upper_hp and behind_glass.hp == protected_hp and not is_instance_valid(blocked), "Friendly projectile stops at closed glass without damaging it or the target behind it")
	upper.take_damage(Balance.SHOT_DAMAGE) # Prepared enemy damage for the subsequent repair fixture.
	behind_glass.queue_free()
	var outside = enemy_at(Vector2(1400, 430))
	await step()
	game.turret.aim_angle = (Vector2(1400, 400) - Vector2(735, 206)).angle()
	game.turret.cooldown = 0.0
	var outside_hp: float = outside.hp
	check(game.turret.fire(), "The real roof turret can fire toward the physical port")
	await step(48)
	check(outside.hp == outside_hp - Balance.SHOT_DAMAGE, "A normal turret projectile passes through the empty port and hits the outside machine")
	outside.queue_free()
	var contact = enemy_at(Vector2(1353, 430))
	await step()
	game.turret.aim_angle = (Vector2(1353, 400) - Vector2(735, 206)).angle()
	game.turret.cooldown = 0.0
	var contact_hp: float = contact.hp
	game.turret.fire()
	await step(48)
	check(contact.hp == contact_hp - Balance.SHOT_DAMAGE and dome.front.hp == 1200, "The normal firing window also reaches a machine at front-attack distance without damaging glass")
	contact.queue_free()
	var attacker = enemy_at(Vector2(1353, 430))
	await step()
	attacker.target = attacker.nearest_obstacle()
	check(attacker.target == dome.front, "Approaching machines target the dome before the bunker walls")
	var core_hp: float = game.core.hp
	check(attacker.attack_obstacle() and is_equal_approx(dome.front.hp,1200-attacker.attack_damage) and game.core.hp == core_hp, "A machine attacks the actual lower glass while the core remains protected")
	await hold("p1_interact", 1.0)
	check(dome.front.hp == 1200 and worker.carried_count() == 0 and upper.hp < upper.max_hp, "One carried glass repairs the front first and cannot also repair another pane")
	dome.front.take_damage(200)
	await hold("p1_interact", 1.0)
	check(dome.front.hp == 1000, "No glass means no free dome repair")
	load_cargo(worker, {"glass": 1})
	await hold("p1_interact", 1.0)
	check(dome.front.hp == 1150 and worker.carried_count() == 0, "One glass restores exactly 150 front HP instead of a free full rebuild")
	dome.front.take_damage(10000)
	await step()
	check(dome.front.stage == PANE.Stage.BROKEN and dome.front.colliders.all(func(shape): return shape.disabled) and not dome.front.is_in_group("walls"), "Shattered front glass visibly changes state and removes both real barrier pieces")
	attacker.target = attacker.nearest_obstacle()
	check(attacker.target != dome.front and attacker.target.is_in_group("walls"), "After a breach the next intact bunker wall becomes the enemy target")
	attacker.position = Vector2(1306, 430)
	attacker.set_physics_process(true)
	await step(90)
	attacker.set_physics_process(false)
	check(attacker.position.x < 1290, "The real enemy movement advances through the shattered dome opening")
	upper.take_damage(10000)
	check(is_inf(dome.cover_height(600)), "A shattered upper pane lets weather enter through that column")
	load_cargo(worker, {"glass": 8})
	await hold("p1_interact", 7.4)
	await step()
	check(dome.front.is_blocking() and dome.front.hp == 1200 and worker.carried_count() == 0, "Eight paid glass repairs rebuild the shattered 1200-HP front to full durability")
	check(upper.stage == PANE.Stage.BROKEN, "Front repairs do not silently restore an unrelated broken pane")
	load_cargo(worker, {"glass": 1})
	await hold("p1_interact", 1.0)
	check(upper.is_blocking() and upper.hp == 140 and dome.cover_height(600) < 90 and worker.carried_count() == 0, "A separate paid pane repair restores both projectile and weather protection")
	check(dome.segments.size() == 13 and dome.materials.get("steel", 0) == 4 and dome.materials.get("alloy", 0) == 4 and dome.materials.get("glass", 0) == 12, "Repairs never duplicate construction segments or their completed recipe")
	print("DOME: %d passed, %d failed. Construction used real held inputs; firing and breach used real collision/movement." % [checks - failures, failures])
	await preload("res://tests/scene_cleanup.gd").free_scene(game,self)
	quit(1 if failures else 0)
