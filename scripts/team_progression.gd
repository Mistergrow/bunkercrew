class_name TeamProgression
extends RefCounted
## Host-owned, finite rewards for completed work. Moving or holding a button is
## not participation. The clock advances only during unpaused gameplay.
const ACTIVE_SECONDS := 90.0
const ROLE_CAPS := {"repair":18.0,"production":16.0,"supply":12.0,"aid":12.0,"craft":12.0,"drive":40.0}
var game: Node
var elapsed := 0.0
var activity: Dictionary = {}
var budgets: Dictionary = {}
var drive_records: Dictionary = {}

func authoritative() -> bool:
	if not is_instance_valid(game): return false
	var network = game.get("network")
	return not is_instance_valid(network) or not network.active or network.is_host

func advance(delta: float) -> void:
	if not authoritative() or not is_finite(delta) or delta<=0: return
	if game.get_tree().paused or ("started" in game and not game.started): return
	elapsed += delta

func participate(player: Node) -> void:
	if authoritative() and _connected(player): activity[player.get_instance_id()] = elapsed

func _connected(player: Node) -> bool:
	if not is_instance_valid(player) or not is_instance_valid(player.get("progression")): return false
	if "players" in game and player not in game.players: return false
	var network = game.get("network")
	return not is_instance_valid(network) or not network.active or not network.has_method("is_player_connected") or network.is_player_connected(int(player.player_id))

func recipients(source: Node) -> Array:
	var result: Array = []
	var candidates: Array = game.players if "players" in game else [source]
	for player in candidates:
		if _connected(player) and elapsed-float(activity.get(player.get_instance_id(), -ACTIVE_SECONDS-1))<=ACTIVE_SECONDS:
			result.append(player)
	return result

func combat_share(source: Node) -> Dictionary:
	if not authoritative(): return {"players":[],"share":0.0}
	var crew := recipients(source)
	return {"players":crew,"share":(1.0 + 0.35 * (crew.size()-1))/maxi(1,crew.size())}

func award_role(player: Node, action: String, amount: float) -> float:
	if not authoritative() or not _connected(player) or not ROLE_CAPS.has(action) or not is_finite(amount) or amount<=0: return 0.0
	participate(player)
	var rounds = game.get("rounds")
	var wave: int = int(rounds.wave) if is_instance_valid(rounds) else 1
	var key := "%d:%d:%s" % [wave,player.player_id,action]
	var earned := minf(amount, maxf(0.0,float(ROLE_CAPS[action])-float(budgets.get(key,0.0))))
	if earned<=0: return 0.0
	budgets[key] = float(budgets.get(key,0.0))+earned
	player.progression.award_team(earned,action)
	return earned

func record_drive(player: Node, vehicle: Node2D, distance: float) -> void:
	if not authoritative() or not _connected(player) or not is_instance_valid(vehicle) or not is_finite(distance) or distance<=0: return
	var expedition = game.get("expedition")
	if is_instance_valid(expedition) and "stage" in expedition and expedition.stage not in ["travel","stop"]: return
	var id := vehicle.get_instance_id()
	# The vehicle owns the spatial record, so changing driver cannot repeat it.
	var record: Dictionary = drive_records.get(id,{"x":vehicle.global_position.x-distance,"distance":0.0})
	var forward_gain := maxf(0.0,minf(distance,vehicle.global_position.x-float(record.x)))
	record.x = maxf(float(record.x),vehicle.global_position.x)
	var useful := minf(forward_gain,maxf(0,2400.0-float(record.distance)))
	var previous_steps := floori(float(record.distance)/60.0)
	record.distance = float(record.distance)+useful
	drive_records[id] = record
	if useful>0: participate(player)
	var steps := floori(float(record.distance)/60.0)-previous_steps
	if steps>0: award_role(player,"drive",float(steps))
