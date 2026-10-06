extends SceneTree
## Tier progression uses the real wall and worker inventories. Stubbed research
## and wave values isolate unlock rules from the duration of a full playthrough.

class ResearchStub extends Node:
	var unlocked: Array = []
	func has_upgrade(key: String) -> bool:
		return key in unlocked
	func carry_capacity() -> int:
		return Balance.CARRY_CAPACITY

class RoundStub extends Node:
	var wave := 1
	var phase := "build"

class TestGame extends Node2D:
	var started := false
	var rounds = RoundStub.new()
	var upgrades = ResearchStub.new()
	func _ready() -> void:
		add_child(rounds)
		add_child(upgrades)
	func sound(_kind): pass
	func fx(_position, _color, _count): pass

class RefusingWorker extends Worker:
	func take_item(kind: String, amount: int = 1) -> bool:
		return false if kind == "concrete" else super.take_item(kind, amount)

var checks := 0
var failures := 0
var game
var worker

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)
	else:
		print("WALL PASS: ", label)

func new_wall(initial_state: int = DefenseWall.State.HARD):
	var wall = load("res://scenes/wall.tscn").instantiate()
	wall.game = game
	wall.initial_state = initial_state
	game.add_child(wall)
	wall.set_process(false)
	return wall

func fund(wall, target_worker = null) -> void:
	if target_worker == null:
		target_worker = worker
	target_worker.inventory.clear()
	for kind: String in wall.upgrade_cost():
		target_worker.add_item(kind, int(wall.upgrade_cost()[kind]))

func run() -> void:
	# Prompt assertions are German; do not inherit the user's saved locale.
	LocaleText.set_locale("de", false)
	game = TestGame.new()
	root.add_child(game)
	worker = load("res://scenes/player.tscn").instantiate()
	worker.game = game
	game.add_child(worker)
	worker.set_physics_process(false)
	var wall = new_wall()
	check(wall.tier == 1 and wall.max_hp == Balance.WALL_HP, "Tier I keeps the existing plain-concrete durability")
	check(wall.collision_layer == 2 and wall.collider.shape.size == Vector2(30, 90), "Upgrade work preserves existing projectile and worker collision geometry")
	check(wall.upgrade_cost() == {"steel": 2, "concrete": 2}, "Tier II requires exactly two steel and two concrete")
	fund(wall)
	game.upgrades.unlocked = ["bunker_armor"]
	wall.interact(worker, DefenseWall.UPGRADE_TIME + 0.1)
	check(wall.tier == 1 and worker.carried_count() == 4 and not wall.upgrade_unlocked(), "Research alone cannot bypass the wave-six construction gate")
	game.rounds.wave = 5
	wall.interact(worker, DefenseWall.UPGRADE_TIME + 0.1)
	check(wall.tier == 1 and worker.carried_count() == 4 and wall.prompt(worker).contains("Welle 6"), "Tier II remains locked throughout the fifth wave")
	game.rounds.wave = 6
	game.upgrades.unlocked.clear()
	wall.interact(worker, DefenseWall.UPGRADE_TIME + 0.1)
	check(wall.tier == 1 and worker.carried_count() == 4 and wall.prompt(worker).contains("Technik"), "Wave six still requires bunker armor research without consuming cargo")
	game.upgrades.unlocked = ["bunker_armor"]
	wall.interact(worker, DefenseWall.UPGRADE_TIME * 0.5)
	check(wall.tier == 1 and wall.work > 0 and worker.carried_count() == 4, "Held construction shows progress and charges nothing before completion")
	worker.take_item("concrete", 1)
	var before: Dictionary = worker.inventory.duplicate()
	wall.interact(worker, DefenseWall.UPGRADE_TIME + 0.1)
	check(wall.tier == 1 and worker.inventory == before and wall.prompt(worker).contains("Beton 1/2"), "Missing concrete is explained and cannot partially consume an upgrade recipe")
	worker.add_item("concrete", 1)
	wall.interact(worker, DefenseWall.UPGRADE_TIME + 0.1)
	check(wall.tier == 2 and wall.max_hp == 500 and wall.hp == 500 and worker.carried_count() == 0, "Tier II consumes exactly two steel and two concrete and adds real durability")
	check(wall.upgrade_cost() == {"alloy": 2, "concrete": 3}, "Tier III introduces two deep-mine alloy and three concrete")
	game.rounds.wave = 11
	fund(wall)
	wall.take_damage(200)
	check(wall.action_for(worker) == "repair", "Damage gives repair priority even with a complete tier-III recipe")
	wall.interact(worker, Balance.WALL_WORK_TIME + 0.1)
	check(wall.tier == 2 and wall.hp == 385 and worker.inventory.get("alloy", 0) == 2 and worker.inventory.get("concrete", 0) == 2, "Repair spends one concrete, preserves alloy and restores only its specified HP")
	wall.interact(worker, Balance.WALL_WORK_TIME + 0.1)
	wall.interact(worker, Balance.WALL_WORK_TIME + 0.1)
	check(wall.hp == wall.max_hp and wall.tier == 2 and worker.inventory.get("concrete", 0) == 0, "A damaged upgraded wall needs all repair material before further construction")
	fund(wall)
	game.rounds.wave = 10
	wall.interact(worker, DefenseWall.UPGRADE_TIME + 0.1)
	check(wall.tier == 2 and worker.carried_count() == 5 and wall.prompt(worker).contains("Welle 11"), "Tier III remains locked throughout the tenth wave")
	game.rounds.wave = 11
	game.upgrades.unlocked.clear()
	wall.interact(worker, DefenseWall.UPGRADE_TIME + 0.1)
	check(wall.tier == 2 and worker.carried_count() == 5 and wall.prompt(worker).contains("Verbundwände"), "Tier III requires armor research as well as its wave unlock")
	game.upgrades.unlocked = ["bunker_armor"]
	wall.interact(worker, DefenseWall.UPGRADE_TIME * 0.5)
	wall.take_damage(10)
	for _frame in 5:
		await physics_frame
	wall.interact(worker, Balance.WALL_WORK_TIME + 0.1)
	check(wall.tier == 2 and wall.hp == 500 and worker.inventory.get("alloy", 0) == 2 and worker.inventory.get("concrete", 0) == 2, "Damage during construction switches back to paid repair without a free upgrade heal")
	worker.add_item("concrete", 1)
	wall.interact(worker, DefenseWall.UPGRADE_TIME + 0.1)
	check(wall.tier == 3 and wall.max_hp == 900 and wall.hp == 900 and worker.carried_count() == 0, "Tier III consumes two alloy and three concrete without requiring fortress research")
	check(wall.upgrade_cost() == {"alloy": 3, "concrete": 3}, "Tier IV requires exactly three alloy and three concrete, fitting six carry slots")
	fund(wall)
	game.upgrades.unlocked = ["bunker_armor", "bunker_fortress"]
	game.rounds.wave = 15
	wall.interact(worker, DefenseWall.UPGRADE_TIME + 0.1)
	check(wall.tier == 3 and worker.carried_count() == 6 and wall.prompt(worker).contains("Welle 16"), "Even fortress research cannot build tier IV during wave fifteen")
	game.rounds.wave = 16
	game.upgrades.unlocked = ["bunker_armor"]
	wall.interact(worker, DefenseWall.UPGRADE_TIME + 0.1)
	check(wall.tier == 3 and worker.carried_count() == 6 and wall.prompt(worker).contains("Festung"), "Tier IV separately requires fortress research without spending materials")
	game.upgrades.unlocked = ["bunker_armor", "bunker_fortress"]
	wall.interact(worker, DefenseWall.UPGRADE_TIME * 0.5)
	worker.take_item("alloy", 1)
	before = worker.inventory.duplicate()
	wall.interact(worker, DefenseWall.UPGRADE_TIME + 0.1)
	check(wall.tier == 3 and worker.inventory == before and wall.prompt(worker).contains("Panzerstahl 2/3"), "A missing late-game alloy preserves both materials and explains the shortfall")
	worker.add_item("alloy", 1)
	wall.interact(worker, DefenseWall.UPGRADE_TIME + 0.1)
	check(wall.tier == 4 and wall.max_hp == 1400 and wall.hp == 1400 and worker.carried_count() == 0, "Tier IV spends the six-unit recipe for real 1400-HP defense")
	check(wall.action_for(worker).is_empty() and wall.prompt(worker).contains("Vollausbau") and wall.upgrade_cost().is_empty(), "Completed tier IV has no fifth upgrade or hidden cost")
	var reinforced = new_wall(DefenseWall.State.REBAR)
	worker.add_item("concrete", 2)
	reinforced.interact(worker, Balance.WALL_WORK_TIME + 0.1)
	check(not reinforced.upgrade_unlocked() and reinforced.tier == 1, "Fresh concrete cannot skip curing through an upgrade")
	reinforced._process(Balance.CURE_TIME)
	check(reinforced.max_hp == Balance.REINFORCED_HP, "Reinforced tier I retains its original 450 HP")
	fund(reinforced)
	reinforced.interact(worker, DefenseWall.UPGRADE_TIME + 0.1)
	check(reinforced.max_hp == 700 and reinforced.reinforced, "Early reinforcement still benefits tier II")
	fund(reinforced)
	reinforced.interact(worker, DefenseWall.UPGRADE_TIME + 0.1)
	check(reinforced.max_hp == 1100 and reinforced.tier == 3, "Reinforcement remains useful at tier III")
	fund(reinforced)
	reinforced.interact(worker, DefenseWall.UPGRADE_TIME + 0.1)
	check(reinforced.max_hp == 1600 and reinforced.tier == 4 and reinforced.reinforced, "Early reinforcement retains its 200-HP benefit at maximum tier IV")
	reinforced.take_damage(42)
	check(reinforced.hp == 1558, "Completed armor remains a real damageable obstacle")
	reinforced.take_damage(10000)
	await physics_frame
	await physics_frame
	check(reinforced.state == DefenseWall.State.EMPTY and reinforced.tier == 1 and not reinforced.reinforced and reinforced.collider.disabled, "Destruction resets all tier benefits and reopens the collision route")
	reinforced.interact(worker, Balance.FORM_TIME + 0.1)
	worker.add_item("concrete", 2)
	reinforced.interact(worker, Balance.WALL_WORK_TIME + 0.1)
	reinforced._process(Balance.CURE_TIME)
	check(reinforced.tier == 1 and reinforced.max_hp == Balance.WALL_HP, "Rebuilding a destroyed tier-IV segment starts again at ordinary tier I")
	var refusing := RefusingWorker.new()
	refusing.game = game
	game.add_child(refusing)
	refusing.set_physics_process(false)
	var rollback = new_wall()
	fund(rollback, refusing)
	rollback.interact(refusing, DefenseWall.UPGRADE_TIME + 0.1)
	check(rollback.tier == 1 and refusing.inventory.get("steel", 0) == 2 and refusing.inventory.get("concrete", 0) == 2, "A rejected inventory transaction refunds prior deductions atomically")
	rollback.tier = 3
	rollback.max_hp = rollback.completed_max_hp()
	rollback.hp = rollback.max_hp
	fund(rollback, refusing)
	rollback.interact(refusing, DefenseWall.UPGRADE_TIME + 0.1)
	check(rollback.tier == 3 and refusing.inventory.get("alloy", 0) == 3 and refusing.inventory.get("concrete", 0) == 3, "A rejected tier-IV payment also refunds its precious alloy atomically")
	await preload("res://tests/scene_cleanup.gd").free_scene(game,self)
	print("WALL UPGRADES: %d passed, %d failed" % [checks - failures, failures])
	quit(1 if failures else 0)
