class_name AmmoTransfer
extends RefCounted
## One standard crate contains twenty rounds. Open crates travel with their
## worker; transferring a partial box never discards or creates ammunition.
const PACK_SIZE := 20
const NetInput := preload("res://scripts/network_input.gd")
static func weapon_for(worker: Node) -> Node:
	if not is_instance_valid(worker): return null
	var named:=worker.get_node_or_null("WorkerWeapon")
	if named!=null: return named
	for child in worker.get_children():
		if child is WorkerWeapon: return child
	return null
static func remainder(worker: Node) -> int:
	var weapon:=weapon_for(worker)
	return int(weapon.open_pack) if weapon!=null else int(worker.get_meta("open_ammo_pack",0))
static func _set_remainder(worker: Node,value: int) -> void:
	var weapon:=weapon_for(worker)
	if weapon!=null: weapon.open_pack=value
	else: worker.set_meta("open_ammo_pack",value)
static func available(worker: Node) -> bool:
	return is_instance_valid(worker) and (remainder(worker)>0 or ("inventory" in worker and int(worker.inventory.get("ammo",0))>0))
static func take(worker: Node, maximum: int, supply: Node=null) -> Dictionary:
	var result: Dictionary={"rounds":0,"crates":0}
	if not is_instance_valid(worker) or maximum<=0 or maximum>1000: return result
	if worker.has_method("can_act") and not worker.can_act(): return result
	var session=NetInput.session(worker)
	if session!=null and not session.is_host: return result
	if is_instance_valid(supply):
		if not supply is Supply or supply.kind!="ammo" or not supply.can_interact(worker): return result
	var open:=remainder(worker)
	while int(result.rounds)<maximum:
		if open==0:
			if is_instance_valid(supply):
				if supply.amount<=0: break
				supply.amount-=1
				supply.queue_redraw()
			elif not worker.take_item("ammo",1): break
			open=PACK_SIZE
			result.crates+=1
		var moved:=mini(open,maximum-int(result.rounds))
		open-=moved
		result.rounds+=moved
	_set_remainder(worker,open)
	return result
static func reward_delivery(game: Node,worker: Node,rounds: int) -> void:
	if rounds<=0 or not is_instance_valid(game): return
	var events=game.get("combat_events")
	if is_instance_valid(events) and events.has_method("record_role"):
		events.record_role(worker,"supply",float(rounds)*.1)
