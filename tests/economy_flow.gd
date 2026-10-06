extends SceneTree

# Actual game integration test. Transport is isolated with explicit teleports;
# mining/production/building run through Worker -> real focus -> held InputMap E.
# This is not a visual playtest or a claim that keyboard traversal was tested here.
var game
var worker
var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run_flow")

func check(condition: bool, message: String) -> void:
	checks += 1
	print("FLOW %s: %s" % ["PASS" if condition else "FAIL",message])
	if not condition:
		failures.append(message)
		push_error(message)

func wait_game(seconds: float) -> void:
	await create_timer(seconds, false, true).timeout

func hold(seconds: float) -> void:
	Input.action_press("p1_interact")
	await wait_game(seconds)
	Input.action_release("p1_interact")
	await physics_frame
	# SceneTree.physics_frame resumes before Worker._physics_process. Allow one
	# full released tick so the next hold is a distinct interaction gesture.
	await physics_frame

func place(pos: Vector2) -> void:
	worker.position = pos
	worker.velocity = Vector2.ZERO
	worker.climbing = false
	worker.collision_mask = 1
	await physics_frame
	await physics_frame

func run_flow() -> void:
	Engine.time_scale = 6.0
	Engine.physics_ticks_per_second = 360
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.start(1)
	worker = game.players[0]
	await place(Vector2(290,800))
	var focus = game.get_focus(worker)
	check(is_instance_valid(focus) and focus.is_in_group("mine_blocks") and focus.kind == "ore" and focus.position == Vector2(250,776),"The exposed bottom ore cell is accessible beside the permanent service path")
	await hold(Balance.MINE_TIME+0.07)
	check(int(worker.inventory.get("ore",0)) == Balance.MINE_YIELD,"Actual E input mines the exposed bottom ore cell into inventory")
	focus = game.get_focus(worker)
	check(is_instance_valid(focus) and focus.is_in_group("mine_blocks") and focus.kind == "sand" and focus.position == Vector2(250,728),"Sand above the ore becomes selectable after the lower face is cleared")
	await hold(Balance.MINE_TIME+0.07)
	check(int(worker.inventory.get("ore",0)) == Balance.MINE_YIELD and int(worker.inventory.get("sand",0)) == Balance.MINE_YIELD and worker.carried_count() == 6,"Mining exposed sand fills actual worker capacity alongside the extracted ore")
	await place(Vector2(250,800))
	await hold(Balance.MINE_TIME+0.08)
	check(worker.carried_count() == Balance.CARRY_CAPACITY and get_nodes_in_group("pickups").size() > 0,"Full worker mining preserves excess ore as world pickups")
	await place(Vector2(202,800))
	focus = game.get_focus(worker)
	check(is_instance_valid(focus) and focus.is_in_group("mine_blocks"),"Uncollectable pickup pile does not hide the next mine block")
	var mixer
	var furnace
	for station in get_nodes_in_group("stations"):
		if station.kind == "mixer": mixer = station
		else: furnace = station
	await place(Vector2(640,800))
	check(game.get_focus(worker) == furnace,"Mine furnace is the clear focused interaction at service side")
	await hold(Balance.TRANSFER_TIME*Balance.RECIPES.mixer.inputs.sand+0.12)
	check(furnace.working and int(worker.inventory.get("ore",0)) == 1,"Actual E transfers ore, retains leftovers, and starts furnace")
	await wait_game(Balance.RECIPES.furnace.time+0.1)
	check(furnace.output_amount == Balance.RECIPES.mixer.amount,"Furnace retains completed steel until collection")
	await hold(Balance.TRANSFER_TIME*Balance.RECIPES.mixer.amount+0.12)
	check(int(worker.inventory.get("steel",0)) == 2 and worker.carried_count() == 6,"Actual E collects transportable steel within capacity")
	var wall
	for candidate in get_nodes_in_group("walls"):
		if candidate.state == DefenseWall.State.EMPTY: wall = candidate
	await place(wall.position+Vector2(-24,0))
	check(game.get_focus(worker) == wall,"Maintenance access clearly selects the empty defensive slot")
	await hold(Balance.FORM_TIME+0.08)
	check(wall.state == DefenseWall.State.FORM,"Held E builds an actual blocking form")
	await hold(Balance.WALL_WORK_TIME+0.08)
	check(wall.state == DefenseWall.State.REBAR and int(worker.inventory.get("steel",0)) == 0,"Mined and smelted steel is consumed by reinforcement")
	await place(Vector2(450,600))
	check(game.get_focus(worker) == mixer,"Production floor mixer is selected without supply-crate ambiguity")
	await hold(Balance.TRANSFER_TIME*Balance.RECIPES.mixer.inputs.sand+0.12)
	check(mixer.working and int(worker.inventory.get("sand",0)) == 1,"Mined sand is transferred through held E and mixed automatically")
	await wait_game(Balance.RECIPES.mixer.time+0.1)
	await hold(Balance.TRANSFER_TIME*Balance.RECIPES.mixer.amount+0.12)
	check(int(worker.inventory.get("concrete",0)) == 2,"Actual worker carries finished concrete from the mixer")
	await place(wall.position+Vector2(-24,0))
	await hold(Balance.WALL_WORK_TIME+0.08)
	check(wall.state == DefenseWall.State.FRESH and int(worker.inventory.get("concrete",0)) == 0,"Carried concrete is poured into the reinforced form")
	var fresh_hp: float = wall.max_hp
	await wait_game(Balance.CURE_TIME+0.1)
	check(wall.state == DefenseWall.State.HARD and wall.max_hp == Balance.REINFORCED_HP and wall.hp > fresh_hp,"Real game time cures fresh concrete into stronger reinforced protection")
	check(game.core.hp == Balance.CORE_HP,"Preparation leaves core intact with no unintended damage")
	print("ECONOMY FLOW: %d passed, %d failed. Teleports isolate transport; actions used actual InputMap E." % [checks-failures.size(),failures.size()])
	# Let the final generated sound finish before audio shutdown.
	await create_timer(0.3,true,false,true).timeout
	game.queue_free()
	await process_frame
	await process_frame
	# This delay uses real time even while the simulation runs six times faster.
	await create_timer(0.25, true, false, true).timeout
	quit(0 if failures.is_empty() else 1)
