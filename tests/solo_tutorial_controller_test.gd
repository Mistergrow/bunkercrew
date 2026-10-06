extends SceneTree
## Prepared isolated worlds exercise observation, suspension and safe contexts.
const Controller := preload("res://scripts/solo_tutorial_controller.gd")
const Records := preload("res://scripts/solo_tutorial_state.gd")
const Journey := preload("res://scripts/convoy_journey.gd")
const Cleanup := preload("res://tests/scene_cleanup.gd")
const OUTPUT := "res://artifacts/solo-tutorial-20261005/controller-verification.json"
var checks := 0
var failures := 0

class PartyWorld extends Node2D:
	var started := true
	var player_count := 1
	var players: Array = []
	var network: Node
	var hud: Node
	var rounds: Node
	var story: Node
	var medic: Node2D
	var workshop: Node2D
	var core: Node2D
	var expedition: Node
	var combat_events: Node
	var travel_cinematic: Node
	var _restart_pending := false
	func _ready() -> void: assert(not _restart_pending)

class PartyLink extends Node:
	var active := false

class MenuState extends Node:
	var overlay := ""
	func blocks_gameplay_input() -> bool: return not overlay.is_empty()

class RoundState extends Node:
	var phase := "build"
	var wave := 1
	var running := false
	var time_left := 57.0

class StoryState extends Node:
	var enabled := false
	var stage := 0
	var wall: Node2D
	var relay: Node2D
	func objective() -> String: return "Feldfunk im Bunker: 2 Stahl bringen und E halten."

class EventState extends Node:
	signal event(kind: String,data: Dictionary)
	var counters := {"mined":0}
	func publish(kind: String,data: Dictionary) -> void: event.emit(kind,data)

class WorkerState extends Node2D:
	var game: Node
	var player_id := 1
	var inventory: Dictionary = {}
	var mounted_turret: Node2D
	var climbing := false
	var can_work := true
	func action(suffix: String) -> String: return "p1_"+suffix
	func can_act() -> bool: return can_work
	func carried_count() -> int:
		var result := 0
		for value: int in inventory.values(): result += value
		return result
	func capacity() -> int: return 6

class StockState extends Node2D:
	var game: Node
	var kind := "sand"
	var amount := 12
	func interaction_point() -> Vector2: return global_position-Vector2(0,20)

class VehicleState extends Node2D:
	var game: Node
	var journey_state: Dictionary = Journey.new_state("driving")
	var seated := false
	var service_medic: Node2D
	func seat_for(_worker: Node) -> Node2D: return self if seated else null
	func _solo_service_medic() -> Node2D: return service_medic
	func interaction_point() -> Vector2: return global_position

class TripState extends Node:
	var stage := "defense"
	var vehicle: Node2D

func _initialize() -> void: _run.call_deferred()

func check(value: bool,label: String) -> void:
	checks += 1
	print("SOLO TUTORIAL CONTROLLER %s: %s" % ["PASS" if value else "FAIL",label])
	if not value:
		failures += 1
		push_error(label)

func _world() -> PartyWorld:
	var world := PartyWorld.new()
	world.network = PartyLink.new()
	world.hud = MenuState.new()
	world.rounds = RoundState.new()
	world.story = StoryState.new()
	world.expedition = TripState.new()
	world.combat_events = EventState.new()
	world.core = Node2D.new()
	for node: Node in [world.network,world.hud,world.rounds,world.story,world.expedition,world.combat_events,world.core]: world.add_child(node)
	root.add_child(world)
	var worker := WorkerState.new()
	worker.game = world
	world.add_child(worker)
	worker.add_to_group("players")
	world.players.append(worker)
	return world

func _run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args(): quit(2); return
	InputSetup.install()
	var world := _world()
	var worker: WorkerState = world.players[0]
	var guide := Controller.new()
	guide.game = world
	world.add_child(guide)
	guide.set_process(false)
	guide.observe()
	check(guide.is_available() and guide.active and guide.current_step().id=="move","Fresh offline one-worker world starts passive guidance")
	var before_rounds := [world.rounds.wave,world.rounds.phase,world.rounds.time_left]
	worker.position.y += 12.0
	guide.observe()
	check("move" not in guide.records.learned,"Spawn settling does not demonstrate movement")
	Input.action_press("p1_right")
	guide.observe()
	check("move" not in guide.records.learned,"A button press without displacement does not demonstrate movement")
	worker.position.x += 20.0
	guide.observe()
	worker.position.x += 20.0
	guide.observe()
	Input.action_release("p1_right")
	check("move" in guide.records.learned,"Matching physical displacement and actual routed movement input demonstrate walking")
	check([world.rounds.wave,world.rounds.phase,world.rounds.time_left]==before_rounds,"Guidance neither pauses nor rewrites a round")
	var foreign := _world()
	var foreign_stock := StockState.new()
	foreign_stock.game = foreign
	foreign.add_child(foreign_stock)
	foreign_stock.add_to_group("supplies")
	guide.observe()
	foreign.combat_events.publish("hit",{"player_id":1,"damage":12.0})
	check("defend" not in guide.records.learned,"Another world's confirmed combat event cannot teach this guide")
	foreign_stock.amount -= 1
	worker.inventory = {"sand":1}
	guide.observe()
	check("gather" not in guide.records.learned,"A foreign world's stock and an unrelated inventory change cannot demonstrate gathering")
	var stock := StockState.new()
	stock.game = world
	world.add_child(stock)
	stock.add_to_group("supplies")
	guide.observe()
	stock.amount -= 1
	worker.inventory.sand = 2
	guide.observe()
	check("gather" in guide.records.learned,"A real owned stock debit and matching inventory gain demonstrate gathering")
	var saved := guide.session_records()
	guide.stop()
	check(not guide.enabled and guide.current_step().is_empty(),"Stop hides the card without discarding learned actions")
	guide.set_enabled(true)
	check(guide.records.learned==saved.learned,"Resume preserves learned actions")
	world.network.active = true
	guide.observe()
	check(not guide.is_available() and not guide.active and guide.current_step().is_empty(),"Even a one-player online room suppresses the solo guide")
	world.network.active = false
	var extra := WorkerState.new()
	extra.game = world
	extra.player_id = 2
	world.add_child(extra)
	world.players.append(extra)
	world.player_count = 2
	guide.observe()
	check(not guide.is_available() and not guide.active,"Local co-op also suppresses the solo guide")
	world.players.pop_back()
	world.player_count = 1
	extra.free()
	guide.observe()
	world.hud.overlay = "options"
	guide.observe()
	check(not guide.active and guide.current_step().is_empty(),"A modal options screen receives no tutorial actions or target markers")
	world.hud.overlay = ""
	guide.observe()
	world.rounds.phase = "attack"
	guide.observe()
	check(guide.current_step().id=="danger" and "defend" not in guide.records.learned,"An attack displays defense context without pretending the wave was completed")
	world.rounds.phase = "salvage"
	guide.observe()
	check("defend" in guide.records.learned,"An observed attack-to-salvage transition demonstrates a defended wave")
	world.story.enabled = true
	world.story.stage = 2
	guide.observe()
	check(guide.current_step().id=="signal","The real story relay takes priority over optional crafting")
	world.story.enabled = false
	worker.inventory = {"sand":6}
	guide.observe()
	check(guide.current_step().id=="full","Full hands receive usable storage and drop guidance instead of impossible pickup requests")
	worker.inventory.clear()
	worker.can_work = false
	guide.observe()
	check(guide.current_step().id=="downed","Incapacitation yields to medical guidance without healing the worker")
	worker.can_work = true
	var vehicle := VehicleState.new()
	vehicle.game = world
	world.add_child(vehicle)
	world.expedition.vehicle = vehicle
	world.expedition.stage = "travel"
	guide.observe()
	check("departure" not in guide.records.learned,"A moving empty vehicle cannot demonstrate the player's departure")
	vehicle.seated = true
	guide.observe()
	check("departure" in guide.records.learned,"Actual driving with this worker seated demonstrates departure")
	Journey.begin_breakdown(vehicle.journey_state)
	guide.observe()
	check(guide.current_step().id=="repair" and "repair" not in guide.records.learned,"A real breakdown state offers wheel instructions without faking completion")
	vehicle.journey_state.solo_assist = true
	vehicle.service_medic = StockState.new()
	vehicle.service_medic.game = world
	world.add_child(vehicle.service_medic)
	guide.observe()
	check(str(guide.current_step().title)==LocaleText.text("SAN-1 arbeitet, du verteidigst"),"Available SAN-1 changes the current role to covering the repair")
	vehicle.service_medic = null
	guide.observe()
	check(str(guide.current_step().title)!=LocaleText.text("SAN-1 arbeitet, du verteidigst"),"Busy or unavailable SAN-1 is never promised as an active mechanic")
	vehicle.journey_state.breakdown_done = true
	vehicle.journey_state.repair_step = "done"
	vehicle.journey_state.phase = "reboarding"
	guide.observe()
	check("repair" in guide.records.learned,"A completed repair after an observed breakdown demonstrates the lesson")
	var before_inventory := worker.inventory.duplicate()
	guide.restart()
	check(guide.enabled and worker.inventory==before_inventory and world.rounds.time_left==before_rounds[2],"Restart resets guidance without changing resources, timers or gameplay")
	check(not guide.restore_session_records({"enabled":false}) and guide.enabled,"Invalid session metadata cannot stop or corrupt a running tutorial")
	guide.stop()
	var stopped := guide.session_records()
	guide.restart()
	check(guide.restore_session_records(stopped) and not guide.enabled,"Validated scene restart state retains the stop preference")
	check(Records.valid(guide.session_records()),"Runtime produces only the local tutorial schema")
	check(await Cleanup.free_scene(foreign,self),"Foreign world releases cleanly")
	check(await Cleanup.free_scene(world,self),"Observer signals and both owned worlds release cleanly")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT.get_base_dir()))
	FileAccess.open(OUTPUT,FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"fixture":"Prepared separate Node2D game worlds and real input route. Economy and round properties are observed, never owned by the guide. Actual full-game crate/production/defense controls are covered separately by solo_tutorial_playthrough_test."},"  "))
	quit(1 if failures else 0)
