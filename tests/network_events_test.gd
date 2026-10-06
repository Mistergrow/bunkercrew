extends SceneTree

const CLEANUP := preload("res://tests/scene_cleanup.gd")
const PROTOCOL := preload("res://scripts/network_protocol.gd")
const SESSION := preload("res://scripts/network_session.gd")
const WORLD := preload("res://scripts/network_world.gd")
var game
var passed := 0
var failed := 0
var observed: Array = []

class HostContext extends Node:
	var combat_events: CombatEvents

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.start_scenario(2,{"environment":"sector07","build_type":"workshop","position":"left"})
	game.rounds.running = false
	game.combat_events.persistence_enabled = false
	game.combat_events.unlocked.clear()
	game.combat_events.earned_this_shift.clear()
	game.combat_events.event.connect(func(kind: String,data: Dictionary): observed.append({"kind":kind,"data":data.duplicate(true)}))
	var network = game.network
	network.active = true
	network.is_host = false
	network.local_player_id = 2
	network.peer_connected = true
	network._authenticated = true
	network._generation = 3
	network.state = "playing"
	network.world = WORLD.new()
	network.world.bind(game)
	network.world.freeze_client()
	var overlay = game.hud.combat_overlay
	overlay.numbers.clear()
	overlay.banners.clear()
	game.audio.sfx_volume = 0.65
	game.audio.cooldowns.clear()
	var original_hp: float = game.players[1].hp
	var original_xp: float = game.players[1].progression.xp
	var hit := {"player_id":2,"enemy_id":987654,"position":Vector2(1000,390),"amount":16.0,"earned":1.6}
	var before_effects := get_nodes_in_group(ImpactBurst.GROUP).size()
	deliver_events([
		{"category":"sound","payload":{"kind":"shot"}},
		{"category":"fx","payload":{"at":Vector2(400,410),"color":Color(0.5,0.25,0.75,1),"count":6}},
		{"category":"impact","payload":{"at":Vector2(960,410),"material":"metal","direction":Vector2.LEFT,"power":1.25}},
		{"category":"combat","payload":{"kind":"hit","data":hit}},
		{"category":"combat","payload":{"kind":"level_up","data":{"player_id":2,"level":5}}},
		{"category":"combat","payload":{"kind":"boss_phase","data":{"title":"ANTRIEB OFFEN","subtitle":"DOPPELSALVE","portrait":"siege"}}},
	])
	check(game.audio.cooldowns.has("shot"),"wire sound reaches the actual audio API")
	check(get_nodes_in_group(ImpactBurst.GROUP).size()==before_effects+2,"wire fx and impact create actual transient effects")
	check(overlay.numbers.size()==1 and overlay.numbers[0].amount==16.0 and overlay.numbers[0].earned==1.6,"combat overlay displays exact remote damage and XP")
	check(overlay.banners.size()==1 and overlay.banners[0].title.contains("LEVEL 05"),"remote level event reaches actual overlay")
	check(overlay.boss.get("title","")=="ANTRIEB OFFEN","remote boss phase reaches actual overlay")
	check(game.players[1].hp==original_hp and game.players[1].progression.xp==original_xp,"cosmetic replay never awards damage or XP")
	check(network._events.is_empty(),"guest does not echo received cosmetics back to host")
	for mineral in ["ore","limestone","tungsten","sand"]:
		deliver_events([{"category":"impact","payload":{"at":Vector2(950,410),"material":"mining_"+mineral,"direction":Vector2.LEFT,"power":0.25}}])
		var mining_burst = get_nodes_in_group(ImpactBurst.GROUP)[-1]
		check(mining_burst.surface_material=="mining_"+mineral and mining_burst.bits.all(func(bit): return bit.type!="sparks"),"Remote %s mining contact retains its mineral chips without a combat flash"%mineral)
	var observed_before := observed.size()
	for corruption in [
		{"player_id":{}}, {"enemy_id":Vector2.ONE}, {"amount":{}},
		{"earned":[]}, {"xp":"many"}, {"position":"950,400"}, {"player_id":5},
	]:
		var bad: Dictionary = hit.duplicate(true)
		bad.merge(corruption,true)
		deliver_events([{"category":"combat","payload":{"kind":"hit","data":bad}}])
		check(observed.size()==observed_before,"malformed combat numeric/position field is ignored before overlay casts")
	for invalid in [
		{"kind":"level_up","data":{"player_id":2,"level":{}}},
		{"kind":"boss","data":{"title":[]}},
		{"kind":"achievement","data":{"id":[]}},
		{"kind":"execute","data":{}},
	]:
		deliver_events([{"category":"combat","payload":invalid}])
		check(observed.size()==observed_before,"invalid combat kind or string field is ignored")
	var effects_before_bad := get_nodes_in_group(ImpactBurst.GROUP).size()
	deliver_events([
		{"category":"fx","payload":{"at":"bad","color":Color.WHITE,"count":4}},
		{"category":"impact","payload":{"at":Vector2.ZERO,"direction":[],"power":1.0}},
	])
	check(get_nodes_in_group(ImpactBurst.GROUP).size()==effects_before_bad,"malformed particle payload cannot create an effect")
	deliver_events([{"category":"combat","payload":{"kind":"hit","data":hit}}],2)
	check(observed.size()==observed_before,"events from a previous match generation are ignored")
	var too_many: Array = []
	for index in 65:
		too_many.append({"category":"combat","payload":{"kind":"hit","data":hit}})
	deliver_events(too_many)
	check(observed.size()==observed_before,"oversized cosmetic event batch is ignored")
	# The host has this achievement in its saved profile before the match. Its
	# new earning attempt must still reach a guest who has never unlocked it.
	var host := HostContext.new()
	root.add_child(host)
	host.combat_events = CombatEvents.new()
	host.add_child(host.combat_events)
	host.combat_events.persistence_enabled = false
	host.combat_events.unlocked = {"first_kill":true,"armor":true}
	var host_events: Array = []
	host.combat_events.event.connect(func(kind: String,_data: Dictionary): host_events.append(kind))
	check(not host.combat_events.unlock("first_kill"),"previously saved achievement is not announced twice on host")
	check(host_events.is_empty(),"host emitted no new achievement event")
	check(host.combat_events.earned_this_shift.has("first_kill"),"current match records achievement despite existing host profile")
	check(not host.combat_events.unlock("unknown"),"unknown achievement is rejected")
	check(not host.combat_events.earned_this_shift.has("unknown"),"unknown IDs never enter earned record")
	var host_session = SESSION.new()
	host_session.game = host
	host.add_child(host_session)
	var earned: Array = host_session._earned_achievement_ids()
	check(earned==["first_kill"],"snapshot includes only achievements earned this match, not old host profile")
	var world: Dictionary = network.world.capture()
	var invalid_world: Dictionary = world.duplicate(true)
	invalid_world.version = -1
	var snapshot := {"kind":"snapshot","generation":3,"seq":1,"paused":false,"world":invalid_world,"achievements":earned}
	network._packet(PROTOCOL.encode(snapshot))
	check(not game.combat_events.unlocked.has("first_kill"),"rejected world snapshot cannot unlock achievements")
	snapshot.world = world
	network._packet(PROTOCOL.encode(snapshot))
	check(network.received_snapshots==1,"achievement packet uses successful actual world replication")
	check(game.combat_events.unlocked.has("first_kill"),"guest unlocks achievement host had already earned before this match")
	check(not game.combat_events.unlocked.has("armor"),"guest never inherits unrelated saved host achievements")
	var achievements_before := observed.filter(func(event): return event.kind=="achievement").size()
	snapshot.seq = 2
	network._packet(PROTOCOL.encode(snapshot))
	check(observed.filter(func(event): return event.kind=="achievement").size()==achievements_before,"repeated snapshots do not duplicate achievement banners")
	game.combat_events.unlocked.erase("first_kill")
	snapshot.seq = 3
	network._packet(PROTOCOL.encode(snapshot))
	check(game.combat_events.unlocked.has("first_kill"),"later snapshot restores an achievement even after cosmetic event loss")
	var retained: Dictionary = game.combat_events.unlocked.duplicate()
	network._receive_achievements(["unknown",{}])
	check(game.combat_events.unlocked==retained,"invalid achievement entries are ignored")
	network.leave()
	host.queue_free()
	paused = false
	check(await CLEANUP.free_scene(game,self),"actual game and audio scene clean up")
	print("Network effects and achievements: %d passed, %d failed"%[passed,failed])
	quit(1 if failed else 0)

func deliver_events(events: Array,generation: int=3) -> void:
	var packet: PackedByteArray = PROTOCOL.encode({"kind":"effects","generation":generation,"events":events})
	check(not packet.is_empty(),"event fixture traverses real protocol encoding")
	game.network._packet(packet)

func check(condition: bool,label: String) -> void:
	if condition:
		passed += 1
	else:
		failed += 1
		push_error(label)
