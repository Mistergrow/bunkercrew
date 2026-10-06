extends SceneTree
## Main-scene regression: players can deliberately choose a dropped pile beside
## a prioritized station, while one held work gesture remains on one object.

var game
var p1
var p2
var furnace
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, label: String) -> void:
	checks += 1
	print("FOCUS %s: %s" % ["PASS" if value else "FAIL", label])
	if not value:
		failures += 1
		push_error(label)

func step(frames: int = 3) -> void:
	for _frame in frames:
		await physics_frame

func tap(action_name: String) -> void:
	Input.action_press(action_name)
	await step()
	Input.action_release(action_name)
	await step()

func place_pile():
	game.spawn_pickup("ore", 2, Vector2(610, 799))
	await step()
	for pile in get_nodes_in_group("pickups"):
		if pile.kind == "ore" and not pile.is_queued_for_deletion():
			return pile
	return null

func run() -> void:
	Engine.time_scale = 2.0
	Engine.physics_ticks_per_second = 120
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.start(2)
	p1 = game.players[0]
	p2 = game.players[1]
	# Teleports set up the crowded interaction case; subsequent actions and the
	# out-of-range journey use real player processing and InputMap input.
	for worker in [p1, p2]:
		worker.position = Vector2(635, 800)
		worker.velocity = Vector2.ZERO
		worker.add_item("ore", 1)
	for station in get_nodes_in_group("stations"):
		if station.kind == "furnace":
			furnace = station
	var pile = await place_pile()
	check(is_instance_valid(pile) and game.focus_candidates(p1).size() == 2, "Only the nearby ore pile and furnace are candidates")
	check(p1.focus == furnace and p2.focus == furnace, "Furnace initially has priority for both workers carrying ore")
	await tap("p1_cycle_target")
	check(p1.focus == pile and p1.preferred_focus == pile, "P1 target-cycle selects the dropped ore beside the furnace")
	check(p2.focus == furnace and p2.preferred_focus == null, "P1 target-cycle leaves P2 selection unchanged")
	await tap("p1_interact")
	check(int(p1.inventory.get("ore", 0)) == 3 and not is_instance_valid(pile), "E operates the explicitly selected pile and collects its material")
	check(furnace.input_amount == 0 and not furnace.working, "Picking up beside the furnace does not deposit into it")
	check(p1.preferred_focus == null and p1.focus == furnace, "Deleted pickup clears preference and restores the available station")
	pile = await place_pile()
	Input.action_press("p1_interact")
	await step()
	await tap("p1_cycle_target")
	check(p1.focus == furnace and p1._locked_focus == furnace, "Target-cycle during held E cannot redirect the locked work target")
	await step(46)
	check(furnace.working and pile.amount == 2, "Held E feeds the furnace and leaves the nearby pile untouched")
	Input.action_release("p1_interact")
	await step()
	await tap("p1_cycle_target")
	check(p1.preferred_focus == pile and p1.focus == pile, "After releasing E a new target selection is allowed")
	Input.action_press("p1_left")
	await step(55)
	Input.action_release("p1_left")
	await step()
	check(p1.position.x < 505 and p1.preferred_focus == null, "Walking outside interaction reach clears the preferred target")
	Input.action_press("p1_right")
	for _frame in 90:
		await physics_frame
		if p1.position.x >= 633:
			break
	Input.action_release("p1_right")
	await step()
	check(p1.focus == furnace, "Returning within reach uses the station's normal priority")
	await tap("p1_cycle_target")
	check(p1.preferred_focus == pile, "An available pile can be selected again after returning")
	pile.queue_free()
	await step()
	check(p1.preferred_focus == null and p1.focus == furnace, "Removing a preferred object while idle safely clears selection")
	var p1_key := InputEventKey.new()
	p1_key.physical_keycode = KEY_F
	var p2_key := InputEventKey.new()
	p2_key.physical_keycode = KEY_PAGEDOWN
	var shoulder := InputEventJoypadButton.new()
	shoulder.device = 0
	shoulder.button_index = JOY_BUTTON_RIGHT_SHOULDER
	check(InputMap.event_is_action(p1_key, "p1_cycle_target") and not InputMap.event_is_action(p1_key, "p2_cycle_target"), "F maps exclusively to P1 target-cycle")
	check(InputMap.event_is_action(p2_key, "p2_cycle_target") and not InputMap.event_is_action(p2_key, "p1_cycle_target"), "PageDown maps exclusively to P2 target-cycle")
	check(InputMap.event_is_action(shoulder, "p2_cycle_target") and not InputMap.event_is_action(shoulder, "p1_cycle_target"), "Controller RB maps exclusively to P2 target-cycle")
	print("FOCUS SELECTION: %d passed, %d failed. Actions used actual InputMap processing in the main scene." % [checks - failures, failures])
	await create_timer(0.3, true, false, true).timeout
	game.queue_free()
	await process_frame
	await process_frame
	# The audio thread releases synchronized playback after the scene exits.
	await create_timer(0.25,true,false,true).timeout
	quit(1 if failures else 0)
