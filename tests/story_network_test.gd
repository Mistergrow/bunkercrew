extends SceneTree
const World := preload("res://scripts/network_world.gd")
const Cleanup := preload("res://tests/scene_cleanup.gd")
var checks := 0
var failures := 0

func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	print("STORY NETWORK %s: %s" % ["PASS" if ok else "FAIL",label])
	if not ok:
		failures += 1
		push_error(label)

func freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children(): freeze(child)

func scene(host: bool) -> Node:
	var game: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.story_mode = true
	game.start_scenario(2,{"environment":"mountain_pass","position":"left","build_type":"bastion"})
	game.network.set_process(false)
	game.network.active = true
	game.network.is_host = host
	game.rounds.running = false
	game.audio.set_music_volume(0)
	game.audio.set_voice_volume(0)
	return game

func run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args() or "--no-upnp" not in OS.get_cmdline_user_args():
		quit(1)
		return
	var host := scene(true)
	for frame in 4: await physics_frame
	freeze(host)
	var authority := World.new()
	authority.bind(host)
	var wall_states: Array[Dictionary] = []
	for stage in [DefenseWall.State.EMPTY,DefenseWall.State.FORM,DefenseWall.State.FRESH,DefenseWall.State.HARD]:
		host.story.wall.state = stage
		host.story.wall.hp = 100.0
		host.story.wall.max_hp = 100.0
		host.story.wall.collider.disabled = stage == DefenseWall.State.EMPTY
		host.story._process(.11)
		wall_states.append(authority.capture())
	check(host.story.stage == 1,"Authoritative hardened prologue wall opens the first act")
	host.rounds.wave = 4
	host.rounds.phase = "build"
	host.story._process(.11)
	host.players[1].position = host.story.relay.position
	host.players[1].inventory = {"steel":2}
	for tick in 5: host.story.relay.interact(host.players[1],.1)
	var partial := authority.capture()
	check(partial.story.stage == 2 and partial.story.relay_progress > 0 and partial.story.relay_progress < 1,"Snapshot carries paid-objective progress before payment")
	for tick in 17: host.story.relay.interact(host.players[1],.1)
	host.story._process(.11)
	check(host.story.stage == 3 and host.players[1].inventory.is_empty(),"Actual relay transaction advances once and consumes exactly two steel")
	var first_strike := authority.capture()
	check(first_strike.storm.serial == 1 and first_strike.storm.age < .34,"Mountain objective creates a real new tree strike")
	host.weather.storm_events.cooldown = 0.0
	check(host.weather.storm_events.trigger_tree_strike(),"A second exposed healthy tree supports the next storm event")
	var next_strike := authority.capture()
	var wire := var_to_bytes(next_strike)
	check(bytes_to_var(wire)==next_strike and wire.size()<512*1024,"Full story and storm state survives ordinary snapshot serialization")
	host.network.active = false
	await Cleanup.free_scene(host,self)

	var guest := scene(false)
	for frame in 4: await physics_frame
	freeze(guest)
	var replica := World.new()
	replica.bind(guest)
	for index in wall_states.size():
		check(replica.apply(wall_states[index]),"Actual guest accepts prologue wall snapshot %d: %s" % [index,replica.last_error])
		check(guest.story.wall.state == [0,1,3,4][index] and guest.story.stage == wall_states[index].story.stage,"Wall construction and story gate agree on the guest")
	check(replica.apply(partial) and guest.story.stage==2 and is_equal_approx(guest.story.relay.progress,partial.story.relay_progress),"Partly held relay and act stage replicate together")
	var inventory: Dictionary = guest.players[1].inventory.duplicate()
	var progress: float = guest.story.relay.progress
	guest.players[1].position = guest.story.relay.position
	for tick in 30: guest.story.relay.interact(guest.players[1],.1)
	guest.story.complete_relay()
	check(guest.story.stage==2 and guest.players[1].inventory==inventory and guest.story.relay.progress==progress,"Direct guest calls cannot finish or pay an authoritative relay")
	var damage_before: Dictionary = guest.scenery.props_layer.reactions.states.duplicate(true)
	var tree_index := int(first_strike.storm.target_index)
	guest.scenery.props_layer.reactions.damage_entry(tree_index,999,"fire")
	check(not guest.weather.storm_events.trigger_tree_strike(tree_index) and guest.scenery.props_layer.reactions.states==damage_before,"Guest cannot burn scenery or create a storm event")
	# Rebinding models the first current-state snapshot of a newly loaded peer.
	replica.bind(guest)
	check(replica.apply(first_strike),"Late-join baseline accepts current story and burning-tree state")
	var storm = guest.weather.storm_events
	storm._process(.5)
	check(storm.thunder_count==0 and storm.visual_strength()==0 and guest.story.stage==3,"Late join shows current damage without historical thunder, bolt or dialogue")
	check(guest.dialogue.pending.is_empty() and guest.dialogue.active.is_empty(),"First snapshot clears obsolete local prologue dialogue")
	var stable_story: Dictionary = guest.story.capture_state()
	var stable_storm: Dictionary = storm.capture_state()
	var stable_damage: Dictionary = guest.scenery.props_layer.reactions.states.duplicate(true)
	var elapsed: float = guest.elapsed
	for kind in ["story_stage","story_nan","story_missing_field","story_mode","story_missing","story_rewind","storm_nan","storm_index","storm_missing","storm_rewind","storm_target","storm_object"]:
		replica.bind(guest)
		replica.apply(first_strike)
		storm._process(.5)
		stable_story=guest.story.capture_state()
		stable_storm=storm.capture_state()
		stable_damage=guest.scenery.props_layer.reactions.states.duplicate(true)
		elapsed=guest.elapsed
		var invalid: Dictionary = first_strike.duplicate(true)
		invalid.game.elapsed = 9999.0
		match kind:
			"story_stage": invalid.story.stage=10
			"story_nan": invalid.story.relay_progress=NAN
			"story_missing_field": invalid.story.erase("serial")
			"story_mode": invalid.story.enabled=false
			"story_missing": invalid.erase("story")
			"story_rewind": invalid.story.serial=0
			"storm_nan": invalid.storm.age=NAN
			"storm_index": invalid.storm.target_index=95
			"storm_missing": invalid.erase("storm")
			"storm_target": invalid.storm.target += Vector2(500,0)
			"storm_object":
				for entry in guest.scenery.props_layer.entries:
					if entry.kind!="tree":
						invalid.storm.target_index=int(entry.index)
						break
			"storm_rewind":
				invalid.storm.serial=0
				invalid.storm.target_index=-1
		check(not replica.apply(invalid) and guest.elapsed==elapsed and guest.story.capture_state()==stable_story and storm.capture_state()==stable_storm and guest.scenery.props_layer.reactions.states==stable_damage,"Malformed %s is rejected before any partial world mutation" % kind)
	check(replica.apply(next_strike),"A later real strike advances the replicated event")
	# Thunder now includes distance to this guest's listener. A fixed .4s
	# assertion was invalid for a distant tree; advance the local audio deadline.
	var delay: float = guest.weather.thunder_delay(storm.target,storm.THUNDER_SECONDS)
	storm._process(maxf(.001,delay-storm.age-.01))
	check(storm.thunder_count==0,"Distant replicated thunder waits for the guest's actual listener delay")
	storm._process(.02)
	check(storm.thunder_count==1,"New replicated strike schedules one local positioned thunder")
	check(replica.apply(next_strike),"Repeating a snapshot remains valid")
	storm._process(.4)
	check(storm.thunder_count==1,"Repeated state cannot replay thunder")
	guest.weather.set_reduced_effects(true)
	guest.scenery.props_layer.debris._process(.1)
	check(guest.scenery.props_layer.debris.fire_lighting.active_entries.is_empty() and guest.scenery.props_layer.reactions.state_for(int(next_strike.storm.target_index)).burning,"F3 reduces local fire lighting while preserving authoritative burning state")
	stable_story=guest.story.capture_state()
	stable_storm=storm.capture_state()
	paused=true
	guest.story._process(2)
	storm._process(2)
	check(guest.story.capture_state()==stable_story and storm.capture_state()==stable_storm,"Shared pause freezes story and storm presentation clocks")
	paused=false
	guest.network.active=false
	await Cleanup.free_scene(guest,self)
	print("STORY NETWORK: %d/%d checks passed" % [checks-failures,checks])
	quit(1 if failures else 0)
