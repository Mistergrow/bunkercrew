extends SceneTree
## Actual host kills and serialized snapshots applied to a separate game scene.
## This exercises NetworkWorld integration; socket transport has its own suite.
const World := preload("res://scripts/network_world.gd")
const Schema := preload("res://scripts/network_replication_schema.gd")
const Cleanup := preload("res://tests/scene_cleanup.gd")
const CASES := [
	{"label":"ground strider","scene":"enemy","kind":"strider","schema":"enemy"},
	{"label":"shield specialist","scene":"enemy","kind":"shield_guard","schema":"enemy"},
	{"label":"final boss","scene":"boss_enemy","kind":"siege","schema":"boss_machine"},
	{"label":"aircraft","scene":"air_enemy","kind":"scout_drone","schema":"air_machine"},
]
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool,label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)

func _stop_simulation(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children():
		_stop_simulation(child)

func _scene() -> Node:
	var game: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.start_scenario(2,{"environment":"ash_foundry","build_type":"bastion","position":"left"})
	_stop_simulation(game)
	return game

func _wire(snapshot: Dictionary) -> Dictionary:
	return bytes_to_var(var_to_bytes(snapshot))

func _pickups(game: Node) -> Dictionary:
	var result := {}
	for node in get_nodes_in_group("pickups"):
		if game.is_ancestor_of(node) and not node.is_queued_for_deletion():
			result[node.kind] = int(result.get(node.kind,0))+int(node.amount)
	return result

func _wrecks(game: Node) -> Array[Node]:
	var result: Array[Node] = []
	for node in get_nodes_in_group("enemy_motion_wrecks"):
		if game.is_ancestor_of(node) and not node.is_queued_for_deletion(): result.append(node)
	return result

func _flush() -> void:
	for frame in 3:
		await process_frame

func _run() -> void:
	var host := _scene()
	var authority := World.new()
	authority.bind(host)
	var machines: Array[Node] = []
	var ids: Array[String] = []
	for index in CASES.size():
		var spec: Dictionary = CASES[index]
		var location := Vector2(900+index*115,150 if spec.schema=="air_machine" else 430)
		var machine: Node = host._entity(spec.scene,location,{"kind":spec.kind,"wave":20})
		_stop_simulation(machine)
		machines.append(machine)
		ids.append(authority._id(machine))
		check(Schema.kind(machine)==spec.schema,"%s uses the real replicated entity factory"%spec.label)
	var initial := _wire(authority.capture())
	var snapshots: Array[Dictionary] = []
	var rewards: Array[Dictionary] = []
	for index in CASES.size():
		var machine: Node = machines[index]
		var label: String = CASES[index].label
		var hp_before: float = machine.hp
		var kills_before: int = host.players[0].progression.kills
		var applied: float = host.combat_hit(machine,100000.0,host.players[0])
		check(applied==hp_before and machine.dead and machine.is_queued_for_deletion(),label+" dies through the authoritative combat-hit path")
		check(host.players[0].progression.kills==kills_before+1,label+" awards exactly one authoritative kill")
		check(not machine.is_in_group("enemies") and machine.collision_layer==0,label+" host collision and wave membership retire immediately")
		await _flush()
		var snapshot := _wire(authority.capture())
		check(not snapshot.entities.any(func(record):return record.id==ids[index]),label+" is absent from its post-death wire snapshot")
		check(not snapshot.entities.any(func(record):return record.type=="enemy_motion_wreck"),label+" visual wreck remains outside the gameplay wire schema")
		snapshots.append(snapshot)
		rewards.append({
			"pickups":_pickups(host),"level":host.players[0].progression.level,
			"xp":host.players[0].progression.xp,"kills":host.players[0].progression.kills,
			"stats":host.stats.duplicate(true),
		})
	check(await Cleanup.free_scene(host,self),"Authoritative scene and host wreck delegates clean up")
	check(get_nodes_in_group("enemy_motion_wrecks").is_empty(),"Host wrecks do not leak into the independent guest world")
	var guest := _scene()
	var replica := World.new()
	replica.bind(guest)
	check(replica.apply(initial),"Guest reconstructs the live host world: "+replica.last_error)
	if not replica.last_error.is_empty():
		await Cleanup.free_scene(guest,self)
		quit(1)
		return
	var credit_events: Array[String] = []
	guest.players[0].progression.event.connect(func(event_name: String,_payload: Dictionary): credit_events.append(event_name))
	check(_wrecks(guest).is_empty(),"Initial alive snapshot creates no destruction visuals")
	var wreck_delegates: Array[WeakRef] = []
	for index in CASES.size():
		var label: String = CASES[index].label
		var machine: Node = replica.entities[ids[index]]
		check(not machine.is_physics_processing(),label+" guest actor is presentation-only before removal")
		var before_wrecks := _wrecks(guest)
		var old_machine: WeakRef = weakref(machine)
		var snapshot: Dictionary = snapshots[index]
		check(replica.apply(snapshot),label+" guest accepts the genuine post-death host snapshot: "+replica.last_error)
		check(not replica.entities.has(ids[index]) and not replica._targets.has(ids[index]),label+" leaves entity and interpolation maps in the same apply call")
		check(not machine.is_inside_tree() and machine.is_queued_for_deletion(),label+" gameplay entity is immediately detached before deferred free")
		check(not machine in get_nodes_in_group("enemies"),label+" cannot hold the guest wave open during destruction")
		var after_wrecks := _wrecks(guest)
		check(after_wrecks.size()==before_wrecks.size()+1,label+" produces exactly one guest wreck")
		var new_wreck: Node = after_wrecks.back()
		check(new_wreck.airborne==(CASES[index].schema=="air_machine"),label+" retains the correct grounded or airborne rig")
		check(new_wreck.identity==("boss" if CASES[index].schema=="boss_machine" else CASES[index].kind),label+" retains its exact class identity in the detached rig")
		check(not new_wreck is CollisionObject2D and not new_wreck.is_in_group("enemies"),label+" detached visual has no gameplay collision or enemy membership")
		for delegate in [new_wreck.artist,new_wreck.artist_motion,new_wreck.artist_ability]:
			if is_instance_valid(delegate): wreck_delegates.append(weakref(delegate))
		var wreck_count := after_wrecks.size()
		check(replica.apply(snapshot) and replica.apply(snapshot),label+" accepts repeated complete snapshots")
		check(_wrecks(guest).size()==wreck_count,label+" repeated removal creates no duplicate wreck")
		await _flush()
		check(old_machine.get_ref()==null,label+" original guest actor is freed without waiting for the animation")
		var expected: Dictionary = rewards[index]
		check(_pickups(guest)==expected.pickups,label+" guest contains exactly the host's replicated drop totals")
		check(guest.players[0].progression.level==expected.level and guest.players[0].progression.xp==expected.xp and guest.players[0].progression.kills==expected.kills,label+" guest progression equals host level, XP and kill totals")
		check(guest.stats==expected.stats,label+" guest match statistics equal the authoritative snapshot")
		check(credit_events.is_empty(),label+" destruction does not award any local hit, kill or level-up event")
		# This is a real SceneTree pause, not a direct zero-delta method call.
		new_wreck.set_process(true)
		paused = true
		var paused_time: float = new_wreck.elapsed
		await _flush()
		check(new_wreck.elapsed==paused_time,label+" visual destruction freezes during the actual game pause")
		paused = false
		await _flush()
		check(new_wreck.elapsed>paused_time,label+" detached visual resumes while replicated simulation stays frozen")
		new_wreck._process(new_wreck.duration)
		await _flush()
		check(not is_instance_valid(new_wreck),label+" transient wreck expires and frees")
		check(wreck_delegates.all(func(reference):return reference.get_ref()==null),label+" expires all unparented drawing delegates")
		print("NETWORK MOTION PASS: ",label)
	check(await Cleanup.free_scene(guest,self),"Guest scene teardown completes without hanging audio or visual delegates")
	check(get_nodes_in_group("enemy_motion_wrecks").is_empty() and get_nodes_in_group("enemies").is_empty(),"Both worlds leave no enemy or wreck nodes behind")
	check(wreck_delegates.all(func(reference):return reference.get_ref()==null),"No detached drawing delegate survives teardown")
	print("NETWORK MOTION: %d/%d checks passed; genuine host kills, four replicated enemy categories"%[checks-failures,checks])
	quit(1 if failures else 0)
