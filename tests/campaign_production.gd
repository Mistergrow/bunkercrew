extends RefCounted
## Test-only quartermaster: omits walking, never creates/deletes any material.
## Every ingredient still comes from a finite supply/pile or real exposed mine cell.
var fixture
var game
var worker
var outputs: Dictionary = {}
var ingredient_used: Dictionary = {}
var mined: Dictionary = {}
var material_used: Dictionary = {}
var mining_target
var diagnostic := ""
const STATIONS := {"concrete":"mixer", "steel":"furnace", "glass":"glass", "alloy":"alloy"}

func setup(owner) -> void:
	fixture = owner
	game = owner.game
	worker = owner.quartermaster

func clear_space(keep: Array) -> bool:
	if worker.carried_count()<worker.capacity(): return true
	for kind: String in worker.inventory.keys():
		if keep.has(kind): continue
		worker.position = Vector2(440,800)
		if game.drop_material(worker,kind,int(worker.inventory[kind])):
			return false
	return false

func collect_pile(kind: String, delta: float) -> bool:
	for pile in fixture.get_nodes_in_group("pickups"):
		if pile.kind!=kind or pile.amount<=0 or pile.is_queued_for_deletion(): continue
		if not clear_space([kind]): return true
		worker.global_position = pile.global_position
		var before: int = pile.amount
		pile.interact(worker,delta)
		if kind=="scrap": fixture.collected_scrap += before-pile.amount
		return true
	return false

func supply_exists(kind: String) -> bool:
	return is_instance_valid(fixture.find_supply(kind))

func station(kind: String):
	for item in fixture.get_nodes_in_group("stations"):
		if item.kind==kind: return item
	return null

func ensure(kind: String, amount: int, delta: float) -> bool:
	if int(worker.inventory.get(kind,0))>=amount: return true
	diagnostic = "obtain "+kind
	if supply_exists(kind):
		if not clear_space([kind]): return false
		fixture.take_stock(worker,kind,delta)
		return false
	if collect_pile(kind,delta): return false
	if not STATIONS.has(kind):
		mine(kind,delta)
		return false
	var processor = station(STATIONS[kind])
	if not is_instance_valid(processor): return false
	if processor.working:
		diagnostic = "wait "+kind
		return false
	worker.global_position = processor.global_position+Vector2(-32,0)
	if processor.output_amount>0:
		if not clear_space([kind]): return false
		var before: int = processor.output_amount
		processor.interact(worker,delta)
		var moved: int = before-processor.output_amount
		outputs[kind] = int(outputs.get(kind,0))+moved
		if kind=="steel": fixture.steel_collected += moved
		return false
	for canonical: String in processor.recipe().inputs:
		var buffered: int = processor.amount_for(canonical) if processor.has_method("amount_for") else processor.input_amount
		if buffered>=processor.input_cost(canonical): continue
		var ingredient := canonical
		if kind=="steel" and fixture.mined_ore>0:
			if int(worker.inventory.get("scrap",0))>0 or fixture.get_nodes_in_group("pickups").any(func(pile): return pile.kind=="scrap" and pile.amount>0):
				ingredient = "scrap"
		if int(worker.inventory.get(ingredient,0))>0:
			worker.selected_kind = ingredient
			var before: int = worker.inventory[ingredient]
			processor.interact(worker,delta)
			ingredient_used[ingredient] = int(ingredient_used.get(ingredient,0))+before-int(worker.inventory.get(ingredient,0))
		else:
			ensure(ingredient,1,delta)
		return false
	return false

func mine(kind: String, delta: float) -> void:
	if not is_instance_valid(mining_target) or mining_target.is_queued_for_deletion() or mining_target.kind!=kind:
		mining_target = null
		for block in fixture.get_nodes_in_group("mine_blocks"):
			if block.kind!=kind or block.is_queued_for_deletion(): continue
			for offset in [Vector2(48,22),Vector2(-48,22),Vector2(0,-27),Vector2(0,71)]:
				worker.position = block.global_position+offset
				if block.can_interact(worker):
					mining_target = block
					break
			if is_instance_valid(mining_target): break
	if not is_instance_valid(mining_target):
		diagnostic = "no exposed "+kind
		return
	for offset in [Vector2(48,22),Vector2(-48,22),Vector2(0,-27),Vector2(0,71)]:
		worker.position = mining_target.global_position+offset
		if mining_target.can_interact(worker): break
	mining_target.interact(worker,delta)
	if mining_target.depleted:
		mined[kind] = int(mined.get(kind,0))+mining_target.yield_amount
		if kind=="ore": fixture.mined_ore += mining_target.yield_amount

func build(site, cost: Dictionary, delta: float) -> void:
	for kind: String in cost:
		if int(site.materials.get(kind,0))>=int(cost[kind]): continue
		if int(worker.inventory.get(kind,0))==0:
			ensure(kind,1,delta)
			return
		worker.position = site.global_position+Vector2(-32,0)
		worker.selected_kind = kind
		var before: int = worker.inventory[kind]
		site.interact(worker,delta)
		material_used[kind] = int(material_used.get(kind,0))+before-int(worker.inventory.get(kind,0))
		return
	worker.position = site.global_position+Vector2(-32,0)
	site.interact(worker,delta)

func feed_ammo(delta: float) -> void:
	var press = station("ammo_press")
	if not is_instance_valid(press) or press.working or press.output_amount>0: return
	if int(worker.inventory.get("steel",0))>0:
		worker.position = press.global_position+Vector2(-32,0)
		worker.selected_kind = "steel"
		press.interact(worker,delta)
	else:
		ensure("steel",1,delta)
