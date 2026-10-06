extends SceneTree
## Defense and legacy construction reject invalid work before consuming cargo.
const Storage = preload("res://scripts/medic_storage.gd")

class TestWorld extends Node2D:
	var started := false
	var network: Node
	var upgrades := UpgradeSystem.new()
	var rounds := ShiftRoundController.new()
	func sound(_kind: String) -> void:
		pass
	func fx(_point: Vector2, _color: Color, _amount: int) -> void:
		pass

var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(label)

func _run() -> void:
	var world := TestWorld.new()
	root.add_child(world)
	world.add_child(world.upgrades)
	world.add_child(world.rounds)
	world.rounds.wave = 20
	world.upgrades.owned = {"bunker_fortress":true}
	var player := preload("res://scenes/player.tscn").instantiate() as Worker
	player.game = world
	world.add_child(player)
	player.set_physics_process(false)
	player.inventory = {"steel":3,"concrete":2,"alloy":1}
	var cargo := player.inventory.duplicate()
	var core := BunkerCore.new()
	core.hp = core.max_hp-40.0
	for invalid in [NAN,INF,-INF,-1.0,0.0]:
		core.interact(player,invalid)
		check(core.repair_work==0.0 and core.hp==core.max_hp-40.0 and player.inventory==cargo,"Core rejects invalid repair time %s" % str(invalid))
		core.repair_work = 0.0
		core.hp = core.max_hp-40.0
		player.inventory = cargo.duplicate()
	core.interact(null,Balance.TRANSFER_TIME)
	check(core.repair_work==0.0 and core.hp==core.max_hp-40.0,"Missing worker cannot repair the core")
	var wall := preload("res://scenes/wall.tscn").instantiate() as DefenseWall
	root.add_child(wall)
	wall.set_process(false)
	for invalid in [NAN,INF,-INF,-1.0,0.0]:
		wall.interact(player,invalid)
		check(wall.state==DefenseWall.State.EMPTY and wall.work==0.0,"Invalid work never creates a wall form: %s" % str(invalid))
		wall.state = DefenseWall.State.EMPTY
		wall.work = 0.0
		wall.work_action = ""
	wall.interact(null,Balance.TRANSFER_TIME)
	check(wall.state==DefenseWall.State.EMPTY and wall.work==0.0,"Missing worker cannot construct a wall")
	var dome := DomeController.new()
	dome.game = world
	dome.available = true
	var flak := FlakStation.new()
	flak.game = world
	flak.available = true
	var extension := ExpansionSite.new()
	extension.kind = "depot"
	extension.game = world
	var shaft := preload("res://scripts/excavation_site.gd").new()
	shaft.game = world
	for site: Node in [dome,flak,extension,shaft]:
		for invalid in [NAN,INF,-INF,-1.0,0.0]:
			site.interact(player,invalid)
			check(site.materials.is_empty() and site.transfer.is_empty() and player.inventory==cargo,"%s rejects invalid construction time %s" % [site.get_script().resource_path.get_file(),str(invalid)])
			site.materials.clear()
			site.transfer.clear()
			player.inventory = cargo.duplicate()
		site.interact(null,Balance.TRANSFER_TIME)
		check(site.materials.is_empty() and site.transfer.is_empty(),"Missing worker cannot mutate %s construction" % site.get_script().resource_path.get_file())
		site.free()
	var pane := DomeSegment.new()
	pane.stage = DomeSegment.Stage.GLASS
	pane.hp = 60.0
	wall.state = DefenseWall.State.HARD
	wall.hp = 60.0
	wall.max_hp = 100.0
	for defense: Node in [core,wall,pane]:
		for invalid in [NAN,INF,-INF,-1.0,0.0]:
			var previous_hp: float = defense.hp
			defense.take_damage(invalid)
			check(defense.hp==previous_hp,"Invalid damage preserves %s health (%s)" % [defense.get_script().resource_path.get_file(),str(invalid)])
			defense.hp = previous_hp
	for invalid in [NAN,INF,-INF,-1.0,0.0]:
		pane.repair(invalid)
		check(pane.hp==60.0,"Invalid pane repair cannot heal glass (%s)" % str(invalid))
		pane.hp = 60.0
	world.set_meta(Storage.RESERVE_META,{"steel":1})
	check(not Storage.add_reserve(world,"steel",9223372036854775807),"Warehouse rejects integer overflow before changing stock")
	check(Storage.reserved(world)=={"steel":1},"Rejected overflow preserves the warehouse")
	world.set_meta(Storage.RESERVE_META,{"steel":CampaignState.MAX_STOCK_PER_KIND-1})
	check(Storage.add_reserve(world,"steel",1),"Last legal warehouse unit fits")
	check(not Storage.add_reserve(world,"steel",1) and Storage.reserve_amount(world,"steel")==CampaignState.MAX_STOCK_PER_KIND,"Full warehouse rejects another unit without loss")
	# Exercise normal health transitions after malformed input.
	core.take_damage(10.0)
	check(core.hp==core.max_hp-50.0,"Core still takes exact valid damage")
	pane.take_damage(10.0)
	check(pane.hp==50.0,"Pane still takes exact valid damage")
	pane.repair(10.0)
	check(pane.hp==60.0,"Pane still accepts an exact valid repair")
	core.free()
	pane.free()
	wall.queue_free()
	check(await preload("res://tests/scene_cleanup.gd").free_scene(world,self),"Defense fixture releases all nodes")
	await process_frame
	print("DEFENSE INPUT HARDENING: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
