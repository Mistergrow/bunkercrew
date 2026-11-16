extends RefCounted
## Environment shots of the visual-review instrument.

## Digs out one basement field through the real mining interaction.
static func clear_field(c, index: int) -> bool:
	var bunker = c.game.scenario_bunker
	if not is_instance_valid(bunker) or index >= bunker.fields.size() or not is_instance_valid(bunker.fields[index]): return false
	var field = bunker.fields[index]
	var worker = c.game.players[0]
	var keep: Dictionary = worker.inventory.duplicate()
	var home: Vector2 = worker.global_position
	for pass_index in 400:
		if field.is_cleared(): break
		var worked := false
		for block in field.blocks.duplicate():
			if not is_instance_valid(block) or block.is_queued_for_deletion() or bool(block.depleted): continue
			worker.global_position = block.interaction_point() if block.has_method("interaction_point") else block.global_position
			if block.has_method("can_interact") and not block.can_interact(worker): continue
			worker.inventory.clear()
			block.interact(worker, float(block.mining_duration()) + 0.1)
			worked = true
		if not worked: break
	worker.inventory = keep
	worker.global_position = home
	worker.velocity = Vector2.ZERO
	# Mined material lies around as pickups; the review shows the rooms, not the spoil.
	for pickup in c.get_nodes_in_group("pickups"):
		if pickup.get("game") == c.game: pickup.queue_free()
	return field.is_cleared()

## Builds every underground room the room catalog offers: real excavation,
## then the site's paid-and-cured state, then the bunker's own completion.
static func build_rooms(c) -> int:
	var bunker = c.game.scenario_bunker
	c.game.rounds.wave = Balance.TOTAL_WAVES
	c.game.set_view_stage(4)
	var built := 0
	for index in ScenarioRoomCatalog.ROOMS.size():
		if index >= bunker.modules.size(): break
		if not bunker.prepare_excavation(index): break
		if not clear_field(c, index): break
		var site = bunker.modules[index]
		site.support_materials = site.support_cost()
		site.supported = true
		site.materials = site.room_cost()
		site.curing = true
		site.curing_remaining = 0.0
		if not bunker.complete_room(index):
			# The site finishes itself on its next tick when completion is its own job.
			await c.frames(3)
			if int(bunker.open_depths) <= index: break
		built += 1
		await c.frames(2)
	if bunker.modules.size() > built: bunker.prepare_excavation(built)
	return built

static func wide(c, spec: Dictionary) -> void:
	await c.play(2, str(spec.args.environment), {"hud": false})
	if c.failed(): return
	# Fixed authored framing: bunker on the left third, horizon and sky above,
	# the first basement below. Independent of the player's camera settings.
	var bunker = c.game.scenario_bunker
	c.camera_fit(Rect2(float(bunker.room_left) - 120.0, 20.0, 1500.0, 650.0), 10.0, 2.0)
	await c.frames(60)
	await c.still()

static func interior(c, spec: Dictionary) -> void:
	await c.play(2, str(spec.args.environment), {"hud": false})
	if c.failed(): return
	var bunker = c.game.scenario_bunker
	c.camera_fit(Rect2(bunker.room_left - 20, 215, bunker.room_right - bunker.room_left + 40, 250), 10.0)
	await c.frames(60)
	await c.still()

static func underground(c, spec: Dictionary) -> void:
	await c.play(2, str(spec.args.environment), {"hud": false})
	if c.failed(): return
	var built: int = await build_rooms(c)
	c.note("%d of %d underground rooms built" % [built, ScenarioRoomCatalog.ROOMS.size()])
	if built == 0: c.fail("no underground room could be built")
	var bunker = c.game.scenario_bunker
	var index := 0
	for worker in c.game.players:
		worker.global_position = Vector2(bunker.room_left + 300 + index * 60, float(c.game.floor_levels[mini(2 + index, c.game.floor_levels.size() - 1)]))
		worker.velocity = Vector2.ZERO
		index += 1
	var deepest := float(c.game.floor_levels[-1])
	c.camera_fit(Rect2(float(bunker.room_left) - 260.0, 150.0, float(bunker.room_right - bunker.room_left) + 520.0, deepest - 150.0 + 40.0), 10.0, 2.0)
	await c.frames(90)
	await c.still()

static func weather(c, spec: Dictionary) -> void:
	await c.play(2, str(spec.args.environment), {"hud": false})
	if c.failed(): return
	var bunker = c.game.scenario_bunker
	var workers: Array = c.game.players
	# One worker outside in the weather, one under the roof.
	workers[0].global_position = Vector2(bunker.room_right + 150, bunker.ground_y)
	c.camera_at(Vector2(bunker.room_right + 60, 300), 1.4)
	await c.frames(60 * 8)
	await c.still()

static func storm(c, spec: Dictionary) -> void:
	await c.play(2, str(spec.args.environment), {"hud": false})
	if c.failed(): return
	var bunker = c.game.scenario_bunker
	c.camera_fit(Rect2(float(bunker.room_left) - 120.0, -60.0, 1500.0, 600.0), 10.0, 2.0)
	var sky = c.game.weather
	if not c.need(sky, "lightning_wait"): return
	await c.frames(60 * 4)
	await c.sequence(14, 3, func(index: int) -> void:
		if index == 2: sky.lightning_wait = 0.0)
	if float(sky.lightning_age) > 5.0: c.note("no lightning strike was observed during the sequence")
