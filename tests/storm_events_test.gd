extends SceneTree
## Real exposed/covered trees, authority, pause, snapshot idempotence and finite
## presentation. Held scenario: mountain pass, left bastion, waves stopped.
const Storm := preload("res://scripts/storm_events.gd")
const Cleanup := preload("res://tests/scene_cleanup.gd")
var checks := 0
var failures := 0

func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks += 1
	print("STORM %s: %s" % ["PASS" if ok else "FAIL",label])
	if not ok:
		failures += 1
		push_error(label)

func run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args():
		quit(1)
		return
	root.size = Vector2i(1440,900)
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.start_scenario(1,{"environment":"mountain_pass","position":"left","build_type":"bastion"})
	game.set_process(false)
	game.rounds.set_process(false)
	game.rounds.running = false
	game.audio.settings_path = "user://storm-test.cfg"
	for worker in game.players: worker.set_physics_process(false)
	for frame in 4: await physics_frame
	var props = game.scenery.props_layer
	var reactions = props.reactions
	var storm = game.weather.storm_events
	storm.set_process(false)
	reactions.set_process(false)
	check(storm!=null and storm.serial==0 and storm.bolt.is_empty(),"A fresh scenario has one idle event controller")
	var damage_before := var_to_str(reactions.states)
	game.weather._start_lightning()
	check(var_to_str(reactions.states)==damage_before and storm.serial==0,"Ambient sky lightning does not damage scenery")
	check(not storm.trigger_tree_strike(95),"A missing tree cannot receive a strike")
	game.network.active = true
	game.network.is_host = false
	check(not storm.trigger_tree_strike(),"A network guest cannot ignite a tree")
	game.network.active = false
	game.weather.lightning_enabled = false
	check(not storm.trigger_tree_strike(),"Non-storm climate rejects a story strike")
	game.weather.lightning_enabled = true
	check(storm.trigger_tree_strike(),"Host/offline strike selects an actual visible exposed tree")
	if storm.target_index<0:
		await Cleanup.free_scene(game,self)
		quit(1)
		return
	var entry: Dictionary = props.entries[storm.target_index]
	var state: Dictionary = reactions.state_for(storm.target_index)
	check(entry.kind=="tree" and state.burning and state.charred and state.hp==18.0 and not state.broken,"The real scenery controller owns damage, burning and charcoal state")
	var closest := INF
	for index in entry.emit_points.size(): closest = minf(closest,storm.target.distance_to(props.to_global(props.canopy_point(entry,index))))
	check(closest<.001,"Strike endpoint lies on the actual bent source canopy")
	check(storm.bolt.size()==13 and storm.bolt[-1]==storm.target and storm.branches.size()<=3,"Arc and branches have strict geometry bounds and reach the crown")
	var clear := true
	for index in range(1,storm.bolt.size()): clear = clear and storm._clear_path(storm.bolt[index-1],storm.bolt[index])
	for column: Rect2 in storm.flash_columns: clear = clear and column.end.y<=game.weather.rain_surface(column.get_center().x)+.001
	check(clear,"Rendered arc and local flash respect actual shelter geometry")
	check(not storm.trigger_tree_strike() and storm.serial==1,"Cooldown prevents a burst of destructive strikes")
	storm._process(.08)
	var snapshot: Dictionary = storm.capture_state()
	check(Storm.valid_state(snapshot),"Bounded snapshot contains only allowed serial, vectors and clocks")
	var invalid := snapshot.duplicate()
	invalid.age = NAN
	var rejects: bool = not Storm.valid_state(invalid)
	invalid = snapshot.duplicate()
	invalid.target_index = 96
	rejects = rejects and not Storm.valid_state(invalid)
	invalid = snapshot.duplicate()
	invalid.origin = Vector2(INF,0)
	rejects = rejects and not Storm.valid_state(invalid)
	invalid = snapshot.duplicate()
	invalid.extra = true
	rejects = rejects and not Storm.valid_state(invalid)
	check(rejects,"Malformed clocks, vectors, indices and extra fields are rejected")
	paused = true
	storm._process(2.0)
	check(storm.capture_state()==snapshot and storm.thunder_count==0,"Pause freezes flash, delayed thunder and cooldown")
	paused = false
	var delay: float = game.weather.thunder_delay(storm.target,Storm.THUNDER_SECONDS)
	storm._process(maxf(.001,delay-storm.age-.001))
	check(storm.thunder_count==0,"Positioned thunder waits for its listener-distance delay")
	storm._process(.01)
	check(storm.thunder_count==1,"Exactly one delayed local thunder accompanies the new event")
	storm._process(.20)
	check(storm.visual_strength()==0.0 and storm.thunder_count==1,"Flash ends within .42 seconds without another hard pulse")
	storm._process(NAN)
	check(is_finite(storm.age),"Invalid delta cannot poison the event clock")
	var replica = Storm.new()
	replica.weather = game.weather
	game.weather.add_child(replica)
	replica.set_process(false)
	damage_before = var_to_str(reactions.states)
	check(replica.apply_state(snapshot,true) and replica.visual_strength()==0.0,"Joining during a strike suppresses its historical presentation")
	replica._process(.5)
	check(replica.thunder_count==0 and not replica.trigger_tree_strike(),"Late join neither replays thunder nor gains ignition authority")
	check(replica.apply_state(snapshot) and replica.visual_strength()==0.0,"Repeated snapshots cannot rewind an old strike")
	var next := snapshot.duplicate()
	next.serial = 2
	next.age = .04
	check(replica.apply_state(next) and replica.visual_strength()>0.0,"A subsequent new host event becomes visible on a guest")
	replica._process(delay+.1)
	replica.apply_state(next)
	replica._process(.3)
	check(replica.thunder_count==1 and var_to_str(reactions.states)==damage_before,"Replicated presentation plays once and applies no duplicate damage")
	check(not replica.apply_state(snapshot),"An older event serial is rejected")
	game.weather.set_reduced_effects(true)
	storm.cooldown = 0.0
	var second_index := -1
	for candidate: Dictionary in props.entries:
		if candidate.kind=="tree" and not candidate.optional and int(candidate.index)!=storm.target_index:
			second_index = candidate.index
			break
	check(second_index>=0,"A second ordinary standing tree is available for shelter testing")
	if second_index>=0:
		var second: Dictionary = props.entries[second_index]
		var roof := StaticBody2D.new()
		roof.collision_layer = 1
		var shape := CollisionShape2D.new()
		shape.shape = RectangleShape2D.new()
		shape.shape.size = Vector2(260,16)
		roof.position = props.to_global(second.position)-Vector2(0,240)
		roof.add_child(shape)
		game.add_child(roof)
		for frame in 2: await physics_frame
		game.weather.refresh_collision_cache()
		check(not storm.trigger_tree_strike(second_index),"An actual physics roof protects the standing tree")
		roof.queue_free()
		for frame in 2: await physics_frame
		game.weather.refresh_collision_cache()
		check(storm.trigger_tree_strike(second_index),"Removing the real cover permits ignition even with F3 reduced visuals")
		storm._process(.5)
		check(storm.visual_strength()==0.0,"Reduced effects retain the finite event lifetime")
	game.weather.set_reduced_effects(false)
	reactions._process(2.1)
	check(bool(reactions.state_for(int(entry.index)).broken),"Existing burning damage breaks the lightning-weakened tree")
	storm.reset()
	check(storm.serial==0 and storm.cooldown==0.0 and storm.bolt.is_empty() and Storm.valid_state(storm.capture_state()),"Scene reset clears strike, cooldown and presentation")
	replica.queue_free()
	print("STORM EVENTS: %d/%d checks passed" % [checks-failures,checks])
	await Cleanup.free_scene(game,self)
	quit(1 if failures else 0)
