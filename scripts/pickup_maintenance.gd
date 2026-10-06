extends Node
## Preserve every resource. Compact only settled reachable piles; sleeping
## support probes and one periodic spatial pass keep long sessions inexpensive.
var elapsed := 0.0

func _process(delta: float) -> void:
	elapsed+=delta
	if elapsed<Balance.PICKUP_COMPACT_INTERVAL: return
	elapsed=0.0
	compact()

func compact() -> void:
	var game := get_parent()
	var network = game.get("network")
	if is_instance_valid(network) and network.active and not network.is_host: return
	var cells: Dictionary = {}
	for pile in get_tree().get_nodes_in_group("pickups"):
		if not is_instance_valid(pile) or pile.is_queued_for_deletion() or pile.game!=game or pile.amount<=0 or not pile.supported(): continue
		if not cells.has(pile.kind): cells[pile.kind]={}
		var kind_cells: Dictionary = cells[pile.kind]
		var cell := Vector2i(floori(pile.global_position.x/Balance.PICKUP_COMPACT_RADIUS),floori(pile.global_position.y/12.0))
		var merged := false
		for x in range(cell.x-1,cell.x+2):
			for y in range(cell.y-1,cell.y+2):
				for existing in kind_cells.get(Vector2i(x,y),[]):
					if existing.amount>=Balance.PICKUP_STACK_MAX or absf(existing.global_position.y-pile.global_position.y)>12.0 or existing.global_position.distance_to(pile.global_position)>Balance.PICKUP_COMPACT_RADIUS: continue
					var query := PhysicsRayQueryParameters2D.create(pile.global_position-Vector2(0,10),existing.global_position-Vector2(0,10),1|2)
					query.hit_from_inside=true
					if not game.get_world_2d().direct_space_state.intersect_ray(query).is_empty(): continue
					var moved := mini(pile.amount,Balance.PICKUP_STACK_MAX-existing.amount)
					existing.amount+=moved
					pile.amount-=moved
					if pile.amount==0:
						pile.queue_free()
						merged=true
						break
				if merged: break
			if merged: break
		if merged: continue
		var key := cell
		if not kind_cells.has(key): kind_cells[key]=[]
		kind_cells[key].append(pile)
