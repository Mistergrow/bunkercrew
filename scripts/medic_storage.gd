extends RefCounted
## Research installs empty physical containers once. Existing quantities never
## change; removed/full stores are handled by the medic's cargo transaction.
static var MATERIALS: Array[String]:
	get: return ItemCatalog.storage_kinds()
const PROVISIONED := "medic_storage_provisioned"
const RESERVE_META := "bunker_storage_reserve"
const RESERVE_ACTIVE_META := "bunker_storage_reserve_active"

static func authoritative(game: Node) -> bool:
	var session=game.get("network") if is_instance_valid(game) else null
	return is_instance_valid(game) and (not is_instance_valid(session) or not session.active or session.is_host)

static func clear_reserve(game: Node) -> void:
	for key: String in [RESERVE_META,RESERVE_ACTIVE_META]:
		if game.has_meta(key): game.remove_meta(key)

static func reserved(game: Node) -> Dictionary:
	return game.get_meta(RESERVE_META,{}).duplicate() if is_instance_valid(game) else {}

static func visible_reserve(game: Node) -> Dictionary:
	if not is_instance_valid(game): return {}
	if authoritative(game): return reserved(game)
	var controller=game.get("expedition")
	return controller.storage_reserve() if is_instance_valid(controller) else {}

static func reserve_amount(game: Node,kind: String) -> int:
	return int(visible_reserve(game).get(kind,0))

static func reserve_active(game: Node) -> bool:
	if not is_instance_valid(game): return false
	if bool(game.get_meta(RESERVE_ACTIVE_META,false)): return true
	var controller=game.get("expedition")
	return is_instance_valid(controller) and controller.can_manage()

static func add_reserve(game: Node,kind: String,amount: int) -> bool:
	if not authoritative(game) or not kind in MATERIALS or amount<=0: return false
	var stock:=reserved(game)
	var current:=int(stock.get(kind,0))
	if current<0 or current>CampaignState.MAX_STOCK_PER_KIND or amount>CampaignState.MAX_STOCK_PER_KIND-current: return false
	stock[kind]=current+amount
	game.set_meta(RESERVE_META,stock)
	game.set_meta(RESERVE_ACTIVE_META,true)
	return true

static func stored_amount(game: Node,kind: String) -> int:
	var amount:=reserve_amount(game,kind)
	for crate in game.get_tree().get_nodes_in_group("supplies"):
		if crate.get("game")==game and not crate.is_queued_for_deletion() and crate.kind==kind: amount+=int(crate.amount)
	return amount

static func can_deposit(crate: Node) -> bool:
	if not is_instance_valid(crate) or not crate.is_inside_tree() or crate.is_queued_for_deletion(): return false
	# An empty additional container is still part of the same bounded warehouse.
	# Check the aggregate before debit even when this particular crate has room.
	if reserve_active(crate.game):
		return stored_amount(crate.game,str(crate.kind))<CampaignState.MAX_STOCK_PER_KIND
	return int(crate.amount)<Balance.PICKUP_STACK_MAX

static func store_unit(crate: Node) -> bool:
	if not is_instance_valid(crate) or not authoritative(crate.game) or not can_deposit(crate): return false
	if int(crate.amount)<Balance.PICKUP_STACK_MAX:
		crate.amount+=1
	else:
		if not add_reserve(crate.game,str(crate.kind),1): return false
	crate.queue_redraw()
	return true

static func refill(crate: Node) -> void:
	if not is_instance_valid(crate) or not crate.is_inside_tree() or crate.is_queued_for_deletion() or not authoritative(crate.game): return
	if not crate.game.has_meta(RESERVE_META): return
	var stock: Dictionary=crate.game.get_meta(RESERVE_META)
	var available:=int(stock.get(crate.kind,0))
	var moved:=mini(available,maxi(0,Balance.PICKUP_STACK_MAX-int(crate.amount)))
	if moved<=0: return
	# Most per-tick probes move nothing. Preserve detached snapshot ownership
	# by copying only when this finite debit actually commits.
	stock=stock.duplicate()
	crate.amount+=moved
	stock[crate.kind]=available-moved
	if stock[crate.kind]==0: stock.erase(crate.kind)
	crate.game.set_meta(RESERVE_META,stock)
	crate.queue_redraw()

static func provision(game: Node) -> void:
	if not game.has_method("_entity") or not is_instance_valid(game.get("medic")) or game.has_meta(PROVISIONED): return
	var session = game.get("network")
	if is_instance_valid(session) and session.active and not session.is_host: return
	var medic: FieldMedic = game.medic
	var existing: Array[String] = []
	for crate in game.get_tree().get_nodes_in_group("supplies"):
		if crate.get("game") == game and not crate.is_queued_for_deletion(): existing.append(str(crate.kind))
	var positions := _positions(game, medic)
	for kind: String in MATERIALS:
		if existing.has(kind): continue
		if positions.is_empty(): return
		var point: Vector2 = positions.pop_front()
		# This existing audited Supply subtype is allowed to appear after the
		# initial world snapshot. A fixed starter crate would be rejected by guests.
		# Runtime loading avoids a preload cycle with Supply's reserve handoff.
		var crate: Node2D = load("res://scripts/convoy_supply.gd").new()
		crate.game = game
		crate.position = point
		crate.kind = kind
		crate.amount = 0
		game.add_child(crate)
	game.set_meta(PROVISIONED, true)

static func _positions(game: Node, medic: FieldMedic) -> Array[Vector2]:
	var left := 75.0
	var right := 750.0
	var bunker = game.get("scenario_bunker")
	if is_instance_valid(bunker):
		left = float(bunker.room_left)
		right = float(bunker.room_right)
	var candidates: Array[Vector2] = []
	# Prefer the actual built bunker. The continuous surface beside its gate
	# is a fallback storage bay, never an undug room or an invented floor.
	for floor_y: float in game.floor_levels:
		for x in range(roundi(left + 100), roundi(right - 30), 56):
			candidates.append(Vector2(x, floor_y))
	for side in [1.0, -1.0]:
		for index in 7:
			candidates.append(Vector2((right if side > 0 else left) + side * (56 + index * 56), 430))
	# Large recovered stores may need additional containers. Search both
	# playable surface edges rather than extending crates beyond the arena.
	for x in range(roundi(float(game.world_left)+32), roundi(float(game.world_right)-32), 56):
		candidates.append(Vector2(x,430))
	var result: Array[Vector2] = []
	var interactables := game.get_tree().get_nodes_in_group("interactables")
	for point: Vector2 in candidates:
		if point.x < float(game.world_left)+24 or point.x > float(game.world_right)-24: continue
		if not medic.navigation.support_at(point) or not medic.navigation.body_clear(point): continue
		if point.distance_to(medic._home()) < 45: continue
		var free := true
		for ladder: Rect2 in game.ladders:
			if ladder.grow(22).has_point(point): free = false
		for node in interactables:
			if node.get("game") != game or node.is_queued_for_deletion(): continue
			if absf(node.global_position.y-point.y) < 45 and absf(node.global_position.x-point.x) < 62: free = false
		for used: Vector2 in result:
			if used.distance_to(point) < 62: free = false
		if is_instance_valid(bunker) and is_equal_approx(point.y, 245) and point.x > left + 145 and point.x < left + 284: free = false
		if free: result.append(point)
	return result
