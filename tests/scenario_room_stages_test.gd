extends SceneTree
## Real construction sites with controlled excavation and inventory boundaries.
## Mining geometry and the finished room are covered by scenario_bunker_test.

class TestField extends Node:
	var cleared := false
	func is_cleared() -> bool: return cleared

class TestRounds extends Node:
	var wave := 1

class TestGame extends Node2D:
	var rounds: TestRounds
	var notifications := 0
	func _ready() -> void:
		rounds = TestRounds.new()
		add_child(rounds)
	func sound(_kind: String) -> void: pass
	func notify(_message: String) -> void: notifications += 1
	func fx(_at: Vector2,_color: Color,_count: int) -> void: pass

class TestBunker extends Node2D:
	var fields: Array = []
	var sites: Array[ScenarioRoomSite] = []
	var completions := 0
	var completed: Dictionary = {}
	func complete_room(index: int) -> bool:
		var site := sites[index]
		if completed.has(index) or not site.excavated() or not site.supported or not site.complete_materials() or not site.curing or site.curing_remaining > 0.0:
			return false
		completed[index] = true
		completions += 1
		return true

class TestWorker extends Node2D:
	var inventory: Dictionary = {}
	var selected := ""
	var can_work := true
	var refuse := false
	func can_act() -> bool: return can_work
	func selected_material() -> String: return selected
	func take_item(kind: String,amount: int = 1) -> bool:
		if refuse or int(inventory.get(kind,0)) < amount: return false
		inventory[kind] = int(inventory[kind])-amount
		return true

var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool,label: String) -> void:
	checks += 1
	print("ROOM STAGES %s: %s" % ["PASS" if value else "FAIL",label])
	if not value:
		failures += 1
		push_error(label)

func run() -> void:
	LocaleText.set_locale("de",false)
	var game := TestGame.new()
	root.add_child(game)
	var bunker := TestBunker.new()
	game.add_child(bunker)
	var site := ScenarioRoomSite.new()
	site.game = game
	site.bunker = bunker
	bunker.add_child(site)
	site.set_process(false)
	bunker.sites.append(site)
	var p1 := TestWorker.new()
	var p2 := TestWorker.new()
	game.add_child(p1)
	game.add_child(p2)
	p1.inventory = {"steel":5,"concrete":5,"ore":3}
	p2.inventory = {"steel":4,"concrete":4}
	check(not site.excavated() and site.can_interact(p1),"A missing excavation cannot be built but its plan remains inspectable")
	site.interact(p1,100)
	check(site.materials.is_empty() and site.support_materials.is_empty() and p1.inventory.steel == 5,"A missing field consumes no cargo")
	var field := TestField.new()
	bunker.add_child(field)
	bunker.fields.append(field)
	site.interact(p1,100)
	check(not site.excavated() and site.support_work == 0 and site.construction == 0 and p1.inventory.concrete == 5,"Raw earth blocks all construction and keeps worker cargo intact")
	check(site.prompt(p1).contains("AUSHUB") and site.prompt(p1).contains("Rohstoffe") and site.interaction_progress(p1) == 0,"The first prompt explains excavation and recovered resources")
	for index in ScenarioRoomCatalog.ROOMS.size():
		site.room_index = index
		var combined := site.room_cost()
		for kind: String in site.support_cost():
			combined[kind] = int(combined.get(kind,0))+int(site.support_cost()[kind])
		check(combined == site.spec().cost,"Room %d supports and fit-out preserve the advertised total cost" % index)
	site.room_index = 0
	field.cleared = true
	check(site.excavated() and site.prompt(p1).contains("Stahl 0/2") and not site.complete_materials(),"Cleared earth exposes the separate two-steel support stage")
	p1.selected = "concrete"
	site.interact(p1,0.1)
	check(site.support_materials.is_empty() and site.interaction_progress(p1) > 0 and site.interaction_progress(p2) == 0,"Support deliveries keep separate held timers for each worker")
	p1.refuse = true
	site.interact(p1,1.0)
	check(site.support_materials.is_empty() and p1.inventory.steel == 5,"A rejected inventory deduction never produces free support material")
	p1.refuse = false
	p1.can_work = false
	site.interact(p1,100)
	check(site.support_materials.is_empty(),"Workers unable to act cannot pay for supports")
	p1.can_work = true
	site.interact(p1,INF)
	site.interact(p1,-1.0)
	site.interact(p1,0.0)
	check(site.support_materials.is_empty() and site.support_work == 0,"Non-finite and non-positive interaction deltas do no work")
	site.interact(p1,1.0)
	site.interact(p2,1.0)
	check(site.support_materials == {"steel":2} and site.materials.is_empty() and p1.inventory.steel == 4 and p2.inventory.steel == 3 and p1.inventory.concrete == 5,"Two workers pay exactly two shared steel before any fit-out material is accepted")
	check(site.support_complete_materials() and not site.supported and site.prompt(p1).contains("Stahlstützen montieren"),"Delivered support material still requires actual assembly")
	site.interact(p1,0.8)
	site.interact(p2,0.7)
	check(not site.supported and is_equal_approx(site.support_work,1.5) and is_equal_approx(site.interaction_progress(p1),0.75),"Shared support assembly reports its own progress")
	site.interact(p2,0.5)
	check(site.supported and site.support_work == ScenarioRoomCatalog.SUPPORT_TIME and site.transfer.is_empty() and site.materials.is_empty(),"Two full assembly seconds finish supports and begin an empty fit-out stage")
	check(site.prompt(p1).contains("RAUMBAU") and site.prompt(p1).contains("Stahl 0/1") and site.prompt(p1).contains("Beton 0/4"),"Fit-out lists only the remaining one steel and four concrete")
	p1.selected = "steel"
	site.interact(p1,1.0)
	check(site.materials == {"steel":1} and p1.inventory.steel == 3 and site.support_materials == {"steel":2},"Fit-out honors the selected material without charging supports twice")
	for index in 2:
		site.interact(p1,1.0)
		site.interact(p2,1.0)
	check(site.complete_materials() and site.materials == {"steel":1,"concrete":4} and p1.inventory.concrete == 3 and p2.inventory.concrete == 2,"Co-op delivery caps fit-out at its exact recipe")
	check(p1.inventory.ore == 3 and p1.inventory.steel+p2.inventory.steel == 6,"Unrelated materials and extra steel remain in worker inventories")
	site.interact(p1,1.2)
	site.interact(p2,1.4)
	check(not site.curing and site.construction > 2.5 and bunker.completions == 0,"Fitting walls and equipment takes the full shared construction time")
	site.interact(p1,0.3)
	check(site.curing and site.curing_remaining == ScenarioRoomCatalog.CURE_TIME and not site.built,"Completed fitting starts the entire concrete cure")
	var cargo_before: Dictionary = p1.inventory.duplicate()
	site.interact(p1,100)
	site.interact(p2,100)
	check(p1.inventory == cargo_before and site.curing_remaining == 6.0 and site.can_interact(p1),"A curing room stays inspectable and cannot consume duplicate payments")
	site._process(5.9)
	check(not site.built and bunker.completions == 0 and site.interaction_progress(p1) > 0.98,"The room is not awarded before its final cure fraction")
	site._process(0.11)
	check(site.built and bunker.completions == 1 and game.notifications == 1 and not site.is_in_group("interactables"),"A fully cured room completes once and removes its obsolete work target")
	site._process(100)
	site.interact(p1,100)
	check(bunker.completions == 1 and game.notifications == 1 and p1.inventory == cargo_before,"Repeat updates never duplicate room benefits or take more cargo")
	var deeper := ScenarioRoomSite.new()
	deeper.game = game
	deeper.bunker = bunker
	deeper.room_index = 1
	bunker.add_child(deeper)
	deeper.set_process(false)
	bunker.sites.append(deeper)
	var deeper_field := TestField.new()
	deeper_field.cleared = true
	bunker.add_child(deeper_field)
	bunker.fields.append(deeper_field)
	deeper.interact(p1,100)
	check(not deeper.wave_ready() and deeper.support_materials.is_empty() and deeper.prompt(p1).contains("Welle 5"),"Excavating a deeper floor cannot bypass its blueprint wave")
	game.rounds.wave = 5
	deeper.interact(p1,1.0)
	check(deeper.support_materials == {"steel":1} and deeper.support_work == 0,"The fifth wave unlocks deeper supports without skipping assembly")
	LocaleText.set_locale("en",false)
	check(deeper.prompt(p1).contains("SUPPORTS") and deeper.prompt(p1).contains("Steel 1/2") and not deeper.prompt(p1).contains("ABSTÜTZEN"),"Support prompts and resource names are fully translated into English")
	deeper_field.cleared = false
	check(deeper.prompt(p1).contains("EXCAVATE") and deeper.prompt(p1).contains("recover materials"),"The English excavation prompt explains the real resource reward")
	LocaleText.set_locale("de",false)
	await preload("res://tests/scene_cleanup.gd").free_scene(game,self)
	print("SCENARIO ROOM STAGES: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
