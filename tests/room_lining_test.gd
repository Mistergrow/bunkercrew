extends SceneTree
## Isolated excavation gate and real worker inventories/core exercise paid lining.
## Construction/cure deltas are supplied directly; no campaign playthrough claim.

class TestSite extends ExpansionSite:
	var cleared := false
	func _ready() -> void: pass
	func _draw() -> void: pass
	func excavated() -> bool: return cleared

class TestGame extends Node2D:
	var started := false
	var upgrades: UpgradeSystem
	var core: BunkerCore
	func _ready() -> void:
		upgrades = UpgradeSystem.new()
		add_child(upgrades)
		core = BunkerCore.new()
		core.game = self
		add_child(core)
	func fx(_at,_color,_count): pass
	func sound(_kind): pass

class RefusingWorker extends Worker:
	func take_item(_kind: String,_amount: int = 1) -> bool: return false

var checks := 0
var failures := 0
var game: TestGame
var signal_state := {"count":0}

func _initialize() -> void:
	call_deferred("run")

func check(value: bool,label: String) -> void:
	checks += 1
	print("LINING %s: %s" % ["PASS" if value else "FAIL",label])
	if not value:
		failures += 1
		push_error(label)

func cargo(player,cost: Dictionary) -> void:
	player.inventory.clear()
	for kind: String in cost:
		player.add_item(kind,int(cost[kind]))

func lining_for(site: TestSite) -> RoomLining:
	var lining := RoomLining.new()
	lining.game = game
	lining.site = site
	lining.position = Vector2(-70,0)
	site.add_child(lining)
	lining.set_process(false)
	return lining

func run() -> void:
	game = TestGame.new()
	root.add_child(game)
	game.core.hp = 350.0
	var players: Array[Worker] = []
	for id in [1,2]:
		var worker: Worker = load("res://scenes/player.tscn").instantiate()
		worker.game = game
		worker.player_id = id
		game.add_child(worker)
		worker.set_physics_process(false)
		players.append(worker)
	var p1 := players[0]
	var p2 := players[1]
	var site := TestSite.new()
	site.position = Vector2(550,1020)
	game.add_child(site)
	var lining := lining_for(site)
	lining.changed.connect(func(): signal_state.count += 1)
	check(lining.is_in_group("interactables") and lining.is_in_group("room_linings") and lining.interaction_point() == Vector2(480,994), "The separate lining target exposes its own groups and reachable interaction point")
	check(lining.tier == 0 and lining.target_tier == 1 and lining.spec().cost == {"concrete":2,"steel":1}, "Initial back-wall recipe is exactly two concrete and one steel")
	cargo(p1,{"concrete":2,"steel":1})
	lining.interact(p1,100)
	check(not lining.can_interact(p1) and p1.carried_count() == 3 and lining.materials.is_empty() and lining.construction == 0, "Unexcavated rooms cannot accept material or construction")
	check(lining.prompt(p1).contains("zuerst den Raum vollständig ausheben"), "The blocked prompt explains excavation before lining")
	site.cleared = true
	check(lining.can_interact(p1) and game.upgrades.owned.is_empty(), "Excavation alone unlocks structural lining without a research gate")
	cargo(p1,{"ore":2,"glass":1})
	lining.interact(p1,100)
	check(p1.carried_count() == 3 and lining.materials.is_empty() and lining.construction == 0, "Unrelated materials stay in worker inventory")
	cargo(p1,{"concrete":3})
	cargo(p2,{"steel":3})
	lining.interact(p1,0.15)
	check(lining.materials.is_empty() and p1.carried_count() == 3 and lining.interaction_progress(p1) > 0, "Filling uses held progress and makes no early deduction")
	lining.interact(p1,0.16)
	lining.interact(p2,0.31)
	check(lining.materials == {"concrete":1,"steel":1} and p1.carried_count() == 2 and p2.carried_count() == 2, "Two workers own one shared buffer while keeping independent transfer timers")
	var partial: Dictionary = lining.materials.duplicate()
	lining.interact(p2,100)
	lining._process(100)
	check(lining.materials == partial and p2.carried_count() == 2 and lining.tier == 0, "A partial recipe persists without consuming surplus steel or granting free progress")
	check(lining.prompt(p1).contains("Beton 1/2") and lining.prompt(p1).contains("+30 HP"), "The selected back-wall prompt shows missing material and its real benefit")
	lining.interact(p1,0.31)
	check(lining.complete_materials() and p1.carried_count() == 1 and p2.carried_count() == 2, "Full tier-one buffer accepts only the exact recipe")
	lining.interact(p1,0.6)
	lining.interact(p2,0.7)
	check(lining.construction > 1.2 and lining.curing_remaining == 0 and lining.tier == 0 and p1.carried_count() == 1 and p2.carried_count() == 2, "Cooperative building advances without charging already buffered material again")
	lining.interact(p1,0.11)
	check(lining.curing_remaining == 8 and lining.materials.is_empty() and lining.construction == 0 and lining.tier == 0 and lining.target_tier == 1, "Building consumes the paid buffer and begins the full eight-second cure")
	check(game.core.max_hp == 450 and game.core.hp == 350, "Fresh back-wall concrete grants no immediate core protection")
	var p1_before: Dictionary = p1.inventory.duplicate()
	var p2_before: Dictionary = p2.inventory.duplicate()
	lining.interact(p1,100)
	lining.interact(p2,100)
	check(not lining.can_interact(p1) and p1.inventory == p1_before and p2.inventory == p2_before and lining.curing_remaining == 8, "Neither partner can deposit or finish the same layer again during curing")
	check(lining.prompt(p1).contains("härtet 8.0 s"), "The curing prompt gives remaining time")
	lining._process(7.9)
	check(lining.tier == 0 and game.core.max_hp == 450 and lining.interaction_progress(p1) > 0.98, "Curing progression is visible but the bonus waits for completion")
	lining._process(0.2)
	check(lining.tier == 1 and lining.target_tier == 2 and lining.curing_remaining == 0 and game.core.max_hp == 480 and game.core.hp == 380, "Cured back wall grants exactly thirty current and maximum core HP")
	var signals_after_cure: int = signal_state.count
	lining._process(100)
	lining._process(100)
	check(game.core.max_hp == 480 and game.core.hp == 380 and signal_state.count == signals_after_cure, "Completed layers never repeat their bonus or emit idle-frame changes")
	check(lining.can_interact(p1) and lining.materials.is_empty() and lining.spec().cost == {"concrete":3,"steel":2} and lining.prompt(p1).contains("TRAGWERK"), "Second structural layer starts with its own empty three-concrete/two-steel buffer")
	var refusing := RefusingWorker.new()
	refusing.game = game
	game.add_child(refusing)
	refusing.set_physics_process(false)
	cargo(refusing,{"concrete":3})
	lining.interact(refusing,1)
	check(refusing.carried_count() == 3 and lining.materials.is_empty(), "A rejected inventory deduction cannot create buffered material")
	cargo(p1,{"concrete":4})
	cargo(p2,{"steel":3})
	for count in 2:
		lining.interact(p1,0.31)
		lining.interact(p2,0.31)
	check(lining.materials == {"concrete":2,"steel":2} and p1.carried_count() == 2 and p2.carried_count() == 1, "Second-layer partial payments conserve both workers' inventories")
	lining.interact(p2,2.1)
	check(lining.construction == 0 and lining.tier == 1 and p2.carried_count() == 1, "Missing concrete prevents construction and preserves extra second-layer steel")
	lining.interact(p1,0.31)
	check(lining.complete_materials() and p1.carried_count() == 1 and p2.carried_count() == 1, "Second-layer buffer caps at exactly five paid units")
	lining.interact(p1,0.9)
	lining.interact(p2,0.9)
	check(lining.curing_remaining == 0 and is_equal_approx(lining.construction,1.8), "Second layer takes its full two-second shared construction time")
	lining.interact(p2,0.3)
	lining.interact(p1,100)
	check(lining.curing_remaining == 12 and lining.tier == 1 and lining.target_tier == 2 and p1.carried_count() == 1 and p2.carried_count() == 1, "Second-layer curing lasts twelve seconds and ignores duplicate cooperative completion")
	check(game.core.max_hp == 480 and game.core.hp == 380, "Fresh structural concrete cannot prematurely increase bunker stability")
	lining._process(11.9)
	check(lining.tier == 1 and game.core.max_hp == 480, "Second-layer HP remains locked until its complete cure")
	lining._process(0.2)
	check(lining.tier == 2 and game.core.max_hp == 525 and game.core.hp == 425, "Cured structural layer adds exactly forty-five HP, preserving the existing damage deficit")
	lining._process(1000)
	lining.interact(p1,1000)
	lining.interact(p2,1000)
	check(not lining.can_interact(p1) and lining.materials.is_empty() and p1.carried_count() == 1 and p2.carried_count() == 1 and game.core.max_hp == 525, "Maximum lining neither consumes extra cargo nor duplicates durability")
	check(lining.prompt(p1).contains("+75 HP") and lining.interaction_progress(p1) == 1, "Completed lining reports its exact permanent total benefit")
	check(signal_state.count > 10, "Material, construction, curing and tier changes notify the parent room")
	var another_site := TestSite.new()
	another_site.cleared = true
	game.add_child(another_site)
	var another := lining_for(another_site)
	cargo(p1,{"concrete":2,"steel":1})
	for item in 3:
		another.interact(p1,0.31)
	another.interact(p1,1.5)
	another._process(8)
	check(another.tier == 1 and lining.tier == 2 and game.core.max_hp == 555 and game.core.hp == 455, "A second paid room adds its own stability without altering the first room's tier")
	print("ROOM LINING: %d passed, %d failed" % [checks-failures,failures])
	game.queue_free()
	await process_frame
	quit(1 if failures else 0)
