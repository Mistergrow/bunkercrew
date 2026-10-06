extends RefCounted
## Prepared construction fixtures use real paid interactions. Moving the worker
## beside an exposed face is intentional; the input playtest covers walking.

static func clear_field(game: Node, index: int, worker: Node2D) -> bool:
	var bunker: ScenarioBunker = game.scenario_bunker if "scenario_bunker" in game else game.get_node_or_null("ScenarioBunker")
	if not is_instance_valid(bunker): return false
	return await clear_terrain(bunker.fields[index], worker)

static func clear_terrain(field: DiggableTerrain, worker: Node2D) -> bool:
	var was_physics := worker.is_physics_processing()
	worker.set_physics_process(false)
	var tree := worker.get_tree()
	for column in int(field.bounds.size.x / DiggableTerrain.CELL):
		worker.global_position = Vector2(field.bounds.position.x + column * 48 - 20, field.bounds.end.y)
		if "velocity" in worker: worker.velocity = Vector2.ZERO
		for row in [2, 1, 0]:
			var block := field.cell_at(Vector2i(column, row))
			if not is_instance_valid(block): continue
			await tree.physics_frame
			if row < 2: worker.global_position.x = block.global_position.x
			if not block.can_interact(worker):
				worker.set_physics_process(was_physics)
				return false
			block.interact(worker, block.mining_duration() + .01)
			await tree.physics_frame
	worker.set_physics_process(was_physics)
	return field.is_cleared()

static func pay_supports(site: ScenarioRoomSite, worker: Node2D) -> void:
	for kind: String in site.support_cost():
		for amount in int(site.support_cost()[kind]): site.interact(worker, Balance.TRANSFER_TIME)
	site.interact(worker, ScenarioRoomCatalog.SUPPORT_TIME)

static func pay_room(site: ScenarioRoomSite, worker: Node2D) -> void:
	for kind: String in site.room_cost():
		for amount in int(site.room_cost()[kind]): site.interact(worker, Balance.TRANSFER_TIME)
	site.interact(worker, ScenarioRoomCatalog.BUILD_TIME)
	site._process(ScenarioRoomCatalog.CURE_TIME + .01)

static func build_room(game: Node, index: int, worker: Node2D) -> bool:
	game.scenario_bunker.ensure_excavation()
	if index >= game.scenario_bunker.fields.size(): return false
	if not await clear_field(game, index, worker): return false
	var site: ScenarioRoomSite = game.scenario_bunker.modules[index]
	# Fixture cargo is supplied one unit at a time through the real transfer
	# path, so even late recipes respect the selected worker's carrying limit.
	worker.inventory.clear()
	for kind: String in site.support_cost():
		for unit in int(site.support_cost()[kind]):
			if worker.add_item(kind, 1) != 1: return false
			site.interact(worker, Balance.TRANSFER_TIME + .01)
	site.interact(worker, ScenarioRoomCatalog.SUPPORT_TIME + .01)
	for kind: String in site.room_cost():
		for unit in int(site.room_cost()[kind]):
			if worker.add_item(kind, 1) != 1: return false
			site.interact(worker, Balance.TRANSFER_TIME + .01)
	site.interact(worker, ScenarioRoomCatalog.BUILD_TIME + .01)
	site._process(ScenarioRoomCatalog.CURE_TIME + .01)
	return site.built
