extends SceneTree
## Real prologue and destroyed walls retain zero HP as persistent build sites.
const WORLD := preload("res://scripts/network_world.gd")
const CLEANUP := preload("res://tests/scene_cleanup.gd")
var checks := 0
var failures := 0

func _initialize() -> void: run.call_deferred()

func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error(label)

func scene() -> Node:
	var game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene=game
	game.combat_events.persistence_enabled=false
	game.story_mode=true
	game.start_scenario(2,{"environment":"mountain_pass","build_type":"bastion","position":"left"})
	return game

func run() -> void:
	var host:=scene()
	var source:=WORLD.new()
	source.bind(host)
	check(host.story.wall.state==DefenseWall.State.EMPTY and host.story.wall.hp==0 and host.story.wall.max_hp==0,"Prologue uses the actual zero-HP construction site")
	var initial: Dictionary=source.capture()
	check(source._validate(initial),"Fresh story snapshot passes unchanged: "+source.last_error)
	var wall: DefenseWall
	for node in source.entities.values():
		if node is DefenseWall and node!=host.story.wall:
			wall=node
			break
	wall.take_damage(wall.max_hp+1)
	check(wall.state==DefenseWall.State.EMPTY and wall.hp==0 and wall.max_hp==0,"Actual damage leaves a destroyed wall as an empty site")
	var destroyed: Dictionary=source.capture()
	check(source._validate(destroyed),"Snapshot accepts the destroyed real wall")
	check(await CLEANUP.free_scene(host,self),"Authoritative scene releases cleanly")
	var guest:=scene()
	var replica:=WORLD.new()
	replica.bind(guest)
	check(replica.apply(initial),"Fresh client accepts the unmodified prologue: "+replica.last_error)
	check(guest.story.wall.state==DefenseWall.State.EMPTY and guest.story.wall.max_hp==0,"Client retains the zero-HP build site")
	check(replica.apply(destroyed),"Later destroyed-wall snapshot still applies: "+replica.last_error)
	var before:=var_to_bytes(replica.capture())
	for kind in ["core","player","wall"]:
		var malformed: Dictionary=destroyed.duplicate(true)
		for entry in malformed.entities:
			if entry.type!=kind: continue
			entry.state.hp=0.0
			entry.state.max_hp=0.0
			if kind=="wall": entry.state.state=DefenseWall.State.HARD
			break
		check(not replica.apply(malformed),"Zero maximum remains invalid for "+kind+" without an empty build site")
		check(var_to_bytes(replica.capture())==before,"Rejected HP boundary leaves all replica state unchanged")
	check(await CLEANUP.free_scene(guest,self),"Replica releases cleanly")
	print("NETWORK EMPTY WALL: %d/%d checks passed"%[checks-failures,checks])
	quit(1 if failures else 0)
