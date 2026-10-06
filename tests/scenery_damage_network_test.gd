extends SceneTree
const World := preload("res://scripts/network_world.gd")
const Damage := preload("res://scripts/scenery_damage.gd")
const Cleanup := preload("res://tests/scene_cleanup.gd")
var checks := 0
var failures := 0

func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks += 1
	print("SCENERY NETWORK %s: %s"%["PASS" if ok else "FAIL",label])
	if not ok:
		failures += 1
		push_error(label)

func scene() -> Node:
	var game: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.start_scenario(2,{"environment":"overgrown_steelworks","build_type":"bastion","position":"left"})
	game.rounds.set_process(false)
	return game

func freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children(): freeze(child)

func frames(count: int = 2) -> void:
	for frame in count:
		await physics_frame
		await process_frame

func record(snapshot: Dictionary) -> Dictionary:
	for entity: Dictionary in snapshot.entities:
		if entity.type=="scenery_damage": return entity
	return {}

func run() -> void:
	var host := scene()
	await frames()
	freeze(host)
	var source: Node = Damage.for_game(host)
	check(is_instance_valid(source),"Real scenario creates the damage controller")
	if not is_instance_valid(source):
		await Cleanup.free_scene(host,self)
		quit(1)
		return
	var trees: Array[int] = []
	var metal := -1
	for entry: Dictionary in source.props.entries:
		if entry.kind=="tree" and not source.state_for(int(entry.index)).broken: trees.append(int(entry.index))
		if entry.kind=="fan": metal = int(entry.index)
	check(trees.size()>=2 and metal>=0,"Fixture uses actual authored trees and a metal machine")
	var burned := trees[0]
	var destroyed := trees[1]
	source.damage_entry(burned,10.0,"arcgun",source.target_point(burned),Vector2.RIGHT)
	source.damage_entry(destroyed,200.0,"rifle",source.target_point(destroyed),Vector2.LEFT)
	host.weather.rain_strength = 0.0
	source._process(.7)
	var authority := World.new()
	authority.bind(host)
	var snapshot := authority.capture()
	var damage_record := record(snapshot)
	check(damage_record.get("id")=="system:scenery_damage" and damage_record.state.states==source.states,"Bounded damage states are a fixed world system entity")
	check(Damage.valid_states(damage_record.state.states,source.props.entries),"Authoritative real-scene state meets strict wire constraints")
	var wire := var_to_bytes(snapshot)
	check(bytes_to_var(wire)==snapshot and wire.size()<512*1024,"Destroyed and burning objects survive full world serialization")
	var expected: Dictionary = source.states.duplicate(true)
	await Cleanup.free_scene(host,self)
	var guest := scene()
	await frames()
	var replica := World.new()
	replica.bind(guest)
	check(replica.apply(snapshot),"Late joining client accepts authoritative scenery: "+replica.last_error)
	var target: Node = Damage.for_game(guest)
	check(target.states==expected and target.state_for(burned).charred and target.state_for(destroyed).broken,"Late join reproduces damage, burn scars, hit direction and broken state")
	check(target.props.debris.burst_count==0 and target.props.debris._seen[destroyed].fall_age>=target.props.debris.FALL_SECONDS,"Late join settles old wrecks without replaying historical hit bursts")
	check(target.replica_only and not target.is_processing(),"Network freeze disables client burn simulation")
	var before: Dictionary = target.states.duplicate(true)
	target._process(20.0)
	target.damage_entry(burned,100.0,"fire")
	check(target.states==before,"Direct client calls cannot advance fuel or cause additional destruction")
	await frames(3)
	check(target.states==before and target.props.debris.is_processing(),"Visual effects remain live while authoritative damage is frozen")
	var bad_cases := ["nan","negative_hp","missing_field","bad_type","extra_index","serial","metal_fire","inconsistent_break","bad_direction","bad_id","missing_controller"]
	for bad_case: String in bad_cases:
		var invalid := snapshot.duplicate(true)
		invalid.game.elapsed = 9999.0
		var invalid_record := record(invalid)
		var invalid_state: Dictionary = invalid_record.state.states[burned]
		match bad_case:
			"nan": invalid_state.hp = NAN
			"negative_hp": invalid_state.hp = -1.0
			"missing_field": invalid_state.erase("charred")
			"bad_type": invalid_state.charred = "yes"
			"extra_index": invalid_record.state.states[999] = invalid_state.duplicate(true)
			"serial": invalid_state.serial = Damage.MAX_SERIAL+1
			"metal_fire":
				invalid_record.state.states[metal].burning = true
				invalid_record.state.states[metal].burn_left = 2.0
				invalid_record.state.states[metal].charred = true
			"inconsistent_break": invalid_state.broken = true
			"bad_direction": invalid_state.direction = Vector2(20,0)
			"bad_id": invalid_record.id = "system:scenery_damage_injected"
			"missing_controller": invalid.entities.erase(invalid_record)
		var before_elapsed: float = guest.elapsed
		check(not replica.apply(invalid) and target.states==before and guest.elapsed==before_elapsed,"Malformed %s snapshot is rejected before any world mutation"%bad_case)
	var update := snapshot.duplicate(true)
	var next: Dictionary = record(update).state.states[burned]
	next.hp = 0.0
	next.broken = true
	next.serial += 1
	next.hit = target.target_point(burned)
	check(replica.apply(update) and target.state_for(burned).broken and target.state_for(burned).serial==next.serial,"Later authoritative destruction applies after initial baseline")
	await frames(3)
	var bursts: int = target.props.debris.burst_count
	check(bursts==1,"New authoritative hit produces exactly one local destruction burst")
	check(replica.apply(update) and target.state_for(burned).serial==next.serial,"Repeated snapshots preserve the event serial without extra damage")
	await frames(3)
	check(target.props.debris.burst_count==bursts,"Repeated snapshot cannot replay destruction particles or sound")
	print("SCENERY NETWORK: %d/%d checks passed; %d snapshot bytes"%[checks-failures,checks,wire.size()])
	await Cleanup.free_scene(guest,self)
	quit(1 if failures else 0)
