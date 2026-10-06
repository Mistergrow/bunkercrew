extends SceneTree
## Real story scenes in all three bunker layouts. Workers walk to the prologue
## and collect its finite crate. Later waves/inventory are prepared fixtures;
## this verifies the complete objective state machine, not a 20-wave playthrough.
const Cleanup := preload("res://tests/scene_cleanup.gd")
const Director := preload("res://scripts/story_director.gd")
const ObjectivePanel := preload("res://scripts/story_objective_panel.gd")
var checks := 0
var failures := 0
var game
var worker
var layout := ""

func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks += 1
	print("STORY %s [%s]: %s" % ["PASS" if ok else "FAIL",layout,label])
	if not ok:
		failures += 1
		push_error(label)

func frames(count: int = 3) -> void:
	for frame in count: await physics_frame

func skip_build() -> void:
	var event := InputEventAction.new()
	event.action = "skip_build"
	event.pressed = true
	game.hud._unhandled_input(event)

func walk_to(x: float) -> bool:
	var direction := signf(x-float(worker.position.x))
	var action := "p1_right" if direction>0 else "p1_left"
	Input.action_press(action)
	var reached := false
	for frame in 420:
		await physics_frame
		if (x-float(worker.position.x))*direction<=3:
			reached = true
			break
	Input.action_release(action)
	await frames(3)
	return reached and absf(worker.position.x-x)<20 and absf(worker.position.y-430)<2

func hold_relay(relay,seconds: float) -> void:
	# Direct work slices preserve real interaction validation and the .2s cap.
	for tick in ceili(seconds/.1): relay.interact(worker,.1)

func set_phase(wave: int,phase: String) -> void:
	game.rounds.wave = wave
	game.rounds.phase = phase
	game.rounds.time_left = 60.0
	game.story._scan_clock = .1
	game.story._process(.001)

func check_marker(target: Vector2,label: String) -> void:
	var point: Vector2 = game.hud.world_to_ui(target)
	check(target.is_finite() and point.y>220 and point.y<700 and point.x>22 and point.x<1418,label)

func run_story(position: String) -> void:
	layout = position
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.story_mode = true
	game.start_scenario(1,{"environment":"mountain_pass","position":position,"build_type":"bastion"})
	game.rounds.set_process(false)
	game.story.set_process(false)
	game.audio.settings_path = "user://story-mode-test.cfg"
	game.weather.set_reduced_effects(true)
	worker = game.players[0]
	await frames(5)
	var story = game.story
	var wall = story.wall
	var relay = story.relay
	var bunker = game.scenario_bunker
	wall.set_process(false)
	var side := -1.0 if position=="right" else 1.0
	var edge: float = bunker.room_left if side<0 else bunker.room_right
	check(story.enabled and story.stage==0 and wall.state==DefenseWall.State.EMPTY,"Story begins with an actual empty construction site")
	check(is_equal_approx(wall.position.x,edge+side*84) and wall.position.y==430 and wall.get_meta("story_wall",false),"Tutorial wall is 84px outside the active approach edge")
	check(relay.position.x>bunker.room_left and relay.position.x<bunker.room_right and relay.position.y==bunker.ground_y-39,"Radio sits on the physical workbench inside the occupied room")
	check_marker(story.target_position(),"Prologue marker is visible in the normal camera")
	var stock
	var stock_count := 0
	for supply in get_nodes_in_group("supplies"):
		if supply.kind=="concrete" and supply.position.y==430 and game.is_ancestor_of(supply):
			stock = supply
			stock_count += 1
	check(stock_count==1 and stock.amount==2 and absf(stock.position.x-wall.position.x)==44,"Exactly two concrete units exist in one physical crate beside the wall")
	var initial_time: float = game.rounds.time_left
	game.rounds._process(10.0)
	skip_build()
	check(game.rounds.time_left==initial_time and game.rounds.phase=="build","Prologue holds the preparation timer and rejects the actual N shortcut")
	check(not relay.can_interact(worker),"Radio cannot skip the wall objective")
	check(await walk_to(wall.position.x-side*35) and game.valid_focus(worker,wall),"Real walking reaches the empty wall through the normal room exit")
	wall.interact(worker,Balance.FORM_TIME+.01)
	check(wall.state==DefenseWall.State.FORM and wall.is_blocking(),"Actual wall interaction creates a blocking form")
	await frames(5)
	check(game.valid_focus(worker,stock) and stock.can_interact(worker),"Finite tutorial concrete is reachable from the work site")
	stock.interact(worker,Balance.TRANSFER_TIME+.01)
	stock.interact(worker,Balance.TRANSFER_TIME+.01)
	check(stock.amount==0 and int(worker.inventory.get("concrete",0))==2,"Two real transfers empty the finite crate into the player's inventory")
	stock.interact(worker,10.0)
	check(stock.amount==0 and int(worker.inventory.get("concrete",0))==2,"An empty tutorial crate cannot create extra concrete")
	wall.interact(worker,Balance.WALL_WORK_TIME+.01)
	check(wall.state==DefenseWall.State.FRESH and int(worker.inventory.get("concrete",0))==0,"Pouring debits exactly two concrete and starts actual curing")
	wall.interact(worker,10.0)
	check(wall.state==DefenseWall.State.FRESH and int(worker.inventory.get("concrete",0))==0,"Repeated interaction neither double-pays nor bypasses curing")
	wall._process(Balance.CURE_TIME-.01)
	story._process(.11)
	check(wall.state==DefenseWall.State.FRESH and story.stage==0 and story.blocks_build(),"The complete 18-second cure is required before the objective advances")
	wall._process(.02)
	story._process(.11)
	check(wall.state==DefenseWall.State.HARD and story.stage==1 and not story.blocks_build(),"A hardened physical wall advances to the first defense objective")
	var resumed_time: float = game.rounds.time_left
	game.rounds._process(1.0)
	check(resumed_time<=35 and game.rounds.time_left==resumed_time-1.0,"Normal preparation resumes after wall completion")
	skip_build()
	check(game.rounds.phase=="warning","N is available once the physical prologue is complete")
	set_phase(4,"attack")
	check(story.stage==1,"Wave number alone does not unlock the radio during combat")
	set_phase(4,"build")
	check(story.stage==2 and story.blocks_build() and relay.can_interact(worker),"Wave 4 build phase activates and gates the antenna objective")
	check_marker(story.target_position(),"First radio marker is visible in the normal camera")
	game.rounds._process(2.0)
	skip_build()
	check(game.rounds.phase=="build" and game.rounds.time_left==60.0,"Wave 4 cannot begin before the antenna has been funded")
	worker.inventory = {"steel":2}
	var far_progress: float = relay.progress
	hold_relay(relay,2.2)
	check(not game.valid_focus(worker,relay) and relay.progress==far_progress and worker.inventory.steel==2,"Steel cannot be spent on a distant radio")
	check(await walk_to(relay.position.x) and game.valid_focus(worker,relay),"Real walking returns the worker to the indoor radio")
	worker.inventory = {"steel":1}
	hold_relay(relay,2.2)
	check(story.stage==2 and worker.inventory.steel==1 and relay.progress==0,"Insufficient steel preserves the entire inventory and objective")
	worker.inventory = {"steel":2}
	game.network.active = true
	game.network.is_host = false
	hold_relay(relay,2.2)
	check(story.stage==2 and relay.progress==0 and worker.inventory.steel==2,"A guest cannot advance or pay for an authoritative radio objective")
	game.network.active = false
	var paused_state: Dictionary = story.capture_state()
	var pulse: float = relay.pulse
	paused = true
	await frames(4)
	story._process(2.0)
	check(story.capture_state()==paused_state and relay.pulse==pulse,"Actual tree pause freezes story state and the physical radio display")
	paused = false
	relay.interact(worker,NAN)
	relay.interact(worker,-1.0)
	check(relay.progress==0 and worker.inventory.steel==2,"Invalid work deltas cannot charge or advance the objective")
	hold_relay(relay,1.0)
	check(story.stage==2 and worker.inventory.steel==2 and relay.progress>0 and relay.progress<1,"Partial radio work preserves both steel units")
	worker.take_item("steel",1)
	hold_relay(relay,1.2)
	check(story.stage==2 and worker.inventory.steel==1,"Losing materials during work prevents a partial or unpaid transaction")
	worker.add_item("steel",1)
	hold_relay(relay,1.2)
	check(story.stage==3 and int(worker.inventory.get("steel",0))==0 and relay.progress==0,"Radio completion atomically consumes two steel and advances once")
	hold_relay(relay,2.2)
	check(story.stage==3 and worker.inventory.is_empty(),"Repeated completed-radio interaction does not charge again")
	story._process(.11)
	check(not story._storm_pending and game.weather.storm_events.serial==1,"Mountain-pass radio completion causes one real tree lightning strike")
	set_phase(11,"warning")
	check(story.stage==3,"Repair is not announced in a warning phase")
	set_phase(11,"build")
	check(story.stage==4 and story.blocks_build(),"Wave 11 build phase activates the failed-relay repair")
	check_marker(story.target_position(),"Repair marker is visible in the normal camera")
	hold_relay(relay,2.2)
	check(story.stage==4 and worker.inventory.is_empty(),"Repair cannot complete without one steel")
	worker.inventory = {"steel":2}
	hold_relay(relay,2.2)
	check(story.stage==5 and worker.inventory.steel==1 and not story.blocks_build(),"Repair consumes exactly one steel and releases the preparation timer")
	hold_relay(relay,2.2)
	check(worker.inventory.steel==1 and story.stage==5,"Repeated repair interaction preserves the spare steel")
	set_phase(16,"salvage")
	check(story.stage==5,"The final send objective waits for the build phase")
	set_phase(16,"build")
	check(story.stage==6 and story.blocks_build(),"Wave 16 build phase gates combat on sending the distress call")
	check_marker(story.target_position(),"Final transmission marker is visible in the normal camera")
	for tick in 48:
		await physics_frame
		relay.interact(worker,.1)
	check(story.stage==6 and relay.progress<1 and worker.inventory.steel==1,"A 4.8-second hold is insufficient and consumes no material")
	for tick in 3:
		await physics_frame
		relay.interact(worker,.1)
	check(story.stage==7 and relay.progress==0 and worker.inventory.steel==1,"Five seconds of actual radio work sends the call without another charge")
	check(not story.target_position().is_finite() and not story.blocks_build(),"Final defense removes the work marker and permits the remaining waves")
	var lines := ObjectivePanel._wrap_lines(story.objective(),438,12)
	check(lines.size()<=3 and not lines.is_empty(),"Final objective fits the existing three-line panel")
	var captured: Dictionary = story.capture_state()
	check(Director.valid_state(captured),"Finished objectives produce bounded serializable story state")
	var invalid := captured.duplicate()
	invalid.stage = 10
	check(not Director.valid_state(invalid),"Out-of-range story stages are rejected")
	game.rounds.wave = 20
	game.rounds.running = true
	game.rounds.victory()
	check(story.stage==8 and game.rounds.phase=="victory" and game.hud.overlay=="victory","Actual round victory publishes the final story outcome")
	await Cleanup.free_scene(game,self)
	paused = false

func run_free() -> void:
	layout = "free"
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.start_scenario(1,{"environment":"sector07","position":"left","build_type":"bastion"})
	game.rounds.set_process(false)
	game.story.set_process(false)
	check(not game.story.enabled and not is_instance_valid(game.story.wall) and not is_instance_valid(game.story.relay),"Free mode has no tutorial construction or radio objective")
	check(get_nodes_in_group("supplies").size()==5,"Free mode retains exactly its five normal finite crates")
	var initial: float = game.rounds.time_left
	game.rounds._process(1.0)
	check(game.rounds.time_left==initial-1.0 and not game.story.blocks_build(),"Free-mode preparation keeps its normal timer")
	skip_build()
	check(game.rounds.phase=="warning","Free-mode N shortcut remains available immediately")
	await Cleanup.free_scene(game,self)
	paused = false

func run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args():
		quit(1)
		return
	root.size = Vector2i(1440,900)
	for position in ["left","center","right"]: await run_story(position)
	await run_free()
	print("STORY MODE: %d/%d checks passed; 3 real layouts, prepared later-wave phases, not a full combat playthrough" % [checks-failures,checks])
	quit(1 if failures else 0)
