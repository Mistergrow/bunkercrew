extends SceneTree

# Focused regression checks for inventory conservation and defensive transitions.
class TestWorker extends CharacterBody2D:
	var inventory: Dictionary = {}
	func carried_count() -> int:
		var total: int = 0
		for n in inventory.values():
			total += int(n)
		return total
	func add_item(kind: String, amount: int) -> int:
		var accepted: int = mini(amount, Balance.CARRY_CAPACITY-carried_count())
		inventory[kind] = int(inventory.get(kind,0))+accepted
		return accepted
	func take_item(kind: String, amount: int) -> bool:
		if int(inventory.get(kind,0)) < amount:
			return false
		inventory[kind] -= amount
		return true

var failures: Array[String] = []
var checks: int = 0

func _initialize() -> void:
	call_deferred("run_checks")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)

func run_checks() -> void:
	var worker: TestWorker = TestWorker.new()
	root.add_child(worker)
	var mixer: ProductionStation = load("res://scenes/station.tscn").instantiate()
	root.add_child(mixer)
	worker.inventory = {"sand":2}
	mixer.interact(worker,0.31)
	mixer.interact(worker,0.31)
	check(worker.inventory["sand"] == 0 and mixer.input_amount == 2,"Mixer transfers exact 2 sand without loss")
	mixer._process(0.0)
	check(mixer.working and mixer.input_amount == 0 and mixer.binder == 79,"Mixer starts automatically and owns the input")
	mixer._process(Balance.RECIPES.mixer.time)
	check(mixer.output_amount == 2 and not mixer.working,"Mixer makes two concrete")
	worker.inventory = {"sand":6}
	mixer.interact(worker,0.5)
	check(mixer.output_amount == 2,"Full inventory does not discard machine output")
	worker.inventory = {"sand":5}
	mixer.interact(worker,0.5)
	check(mixer.output_amount == 1 and worker.inventory["concrete"] == 1,"Partial output collection retains remaining concrete")
	var furnace: ProductionStation = load("res://scenes/station.tscn").instantiate()
	furnace.kind = "furnace"
	root.add_child(furnace)
	worker.inventory = {"ore":1,"scrap":1}
	furnace.interact(worker,0.31)
	furnace.interact(worker,0.31)
	furnace._process(0.0)
	furnace._process(Balance.RECIPES.furnace.time)
	check(furnace.output_amount == 2 and worker.inventory["ore"] == 0 and worker.inventory["scrap"] == 0,"Furnace processes ore and useful scrap into steel")
	worker.inventory = {}
	furnace.interact(worker,0.31)
	furnace.interact(worker,0.31)
	check(worker.inventory["steel"] == 2 and furnace.output_amount == 0,"Steel can be carried away")
	var wall: DefenseWall = load("res://scenes/wall.tscn").instantiate()
	root.add_child(wall)
	check(not wall.is_blocking(),"Empty construction slot is open")
	wall.interact(worker,1.1)
	check(wall.state == DefenseWall.State.FORM and wall.is_blocking(),"Constructed form blocks attackers")
	wall.interact(worker,0.8)
	check(wall.state == DefenseWall.State.REBAR and worker.inventory["steel"] == 0,"Rebar consumes exactly two steel before concrete")
	worker.inventory = {"concrete":1}
	wall.interact(worker,1.0)
	check(wall.state == DefenseWall.State.REBAR and worker.inventory["concrete"] == 1,"Insufficient concrete is not lost")
	worker.inventory = {"concrete":2}
	wall.interact(worker,0.8)
	check(wall.state == DefenseWall.State.FRESH and worker.inventory["concrete"] == 0,"Concrete is poured and becomes a fresh wall")
	var fresh_hp: float = wall.max_hp
	wall._process(Balance.CURE_TIME)
	check(wall.state == DefenseWall.State.HARD and wall.max_hp == Balance.REINFORCED_HP and wall.hp > fresh_hp,"Curing and reinforcement increase real durability")
	wall.take_damage(90)
	worker.inventory = {"concrete":1}
	wall.interact(worker,0.8)
	check(wall.hp == Balance.REINFORCED_HP-5 and worker.inventory["concrete"] == 0,"Repair consumes concrete and restores exactly 85 HP")
	wall.take_damage(10000)
	check(wall.state == DefenseWall.State.EMPTY and not wall.is_blocking(),"Destroyed wall opens the defense route")
	var pickup: ResourcePickup = load("res://scenes/resource_pickup.tscn").instantiate()
	pickup.amount = 3
	root.add_child(pickup)
	worker.inventory = {"ore":5}
	pickup.interact(worker,0.31)
	pickup.interact(worker,0.31)
	check(pickup.amount == 2 and worker.carried_count() == 6,"Pickup respects carry capacity and preserves remainder")
	var supply: Supply = load("res://scenes/supply.tscn").instantiate()
	supply.amount = 1
	root.add_child(supply)
	worker.inventory = {}
	supply.interact(worker,0.31)
	supply.interact(worker,0.31)
	check(supply.amount == 0 and worker.inventory["ammo"] == 1,"Finite supply never goes negative")
	worker.inventory = {}
	worker.position = Vector2(-40,24)
	var block: MineBlock = load("res://scenes/mine_block.tscn").instantiate()
	block.kind = "ore"
	root.add_child(block)
	await physics_frame
	await physics_frame
	check(block.can_interact(worker),"Adjacent ore tile is reachable")
	block.interact(worker,Balance.MINE_TIME+0.01)
	check(worker.inventory.get("ore",0) == 3 and block.is_queued_for_deletion(),"Held mining produces three transportable ore")
	print("ECONOMY CHECKS: %d passed, %d failed" % [checks-failures.size(),failures.size()])
	quit(0 if failures.is_empty() else 1)
