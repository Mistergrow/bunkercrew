extends SceneTree
## Exercise existing methods with fixed owners; time repeatable calls rather
## than changing simulation speeds or caching a mutable resource ledger.
const Storage := preload("res://scripts/medic_storage.gd")
const OUTPUT := "res://artifacts/code-optimization-20261004/gameplay"

class World extends Node2D:
	var players: Array[Node2D] = []
	var network: Node
	var expedition: Node
class Human extends Node2D:
	var focus: Node
	func _ready() -> void: add_to_group("players")
class Cell extends MineBlock:
	func _ready() -> void: pass # Actual selection method; no unrelated geology startup.
class Robot extends FieldMedic:
	func _ready() -> void: pass
	func notice_task(_kind: String, _destination: Node2D) -> void: pass
class Station extends ProductionStation:
	func _ready() -> void: add_to_group("stations")
class Crate extends Supply:
	func _ready() -> void: add_to_group("supplies")
class Navigation extends MedicNavigation:
	var exclusion_scans := 0
	func _planning_exclusions() -> Array[RID]:
		exclusion_scans += 1
		return super._planning_exclusions()
class Logistics extends "res://scripts/medic_logistics.gd":
	var blocked_station: Node2D
	var chosen_crate: Node2D
	var station_route_queries := 0
	var crate_route_queries := 0
	func _in_reach(_node: Node2D) -> bool: return false
	func _route_to(node: Node2D) -> Array[Dictionary]:
		var path: Array[Dictionary] = []
		if node is ProductionStation:
			station_route_queries += 1
			if node != blocked_station: path.append({"point":node.global_position,"kind":"walk"})
			return path
		crate_route_queries += 1
		if node == chosen_crate: path.append({"point":node.global_position,"kind":"walk"})
		return path

var checks := 0
var failures := 0
var measurements: Dictionary = {}
var before := false
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	print("GAMEPLAY LOOP %s: %s" % ["PASS" if ok else "FAIL",label])
	if not ok:
		failures += 1
		push_error(label)
func median_us(samples: Array[int]) -> float:
	samples.sort()
	return float(samples[samples.size() >> 1])

func run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args() or "--no-upnp" not in OS.get_cmdline_user_args(): quit(1); return
	before = "--before" in OS.get_cmdline_user_args()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var game := World.new()
	root.add_child(game)
	for index in 4:
		var actor := Human.new()
		game.add_child(actor)
		game.players.append(actor)
	var cells: Array[MineBlock] = []
	for index in 1024:
		var cell := Cell.new()
		cell.game = game
		game.add_child(cell)
		cell.set_process(false)
		cells.append(cell)
	var last: Human = game.players[-1]
	last.focus = cells[-1]
	check(cells[-1].is_selected() and not cells[0].is_selected(),"All four crew slots retain live mining focus selection")
	last.focus = cells[0]
	check(cells[0].is_selected() and not cells[-1].is_selected(),"A focus change inside one frame is observed without a stale frame cache")
	var samples: Array[int] = []
	var selected_count := 0
	for repeat in 7:
		var started := Time.get_ticks_usec()
		for frame in 30:
			for cell in cells:
				if cell.is_selected(): selected_count += 1
		samples.append(Time.get_ticks_usec()-started)
	check(selected_count == 210,"Every repeat selects exactly one live rock cell")
	measurements.mining = {"cells":1024,"frames_per_repeat":30,"repeats":7,"median_us":median_us(samples),"per_frame_us":median_us(samples)/30.0}
	# Ownerless test entities still use the supported global player group path.
	var orphan := Cell.new()
	game.add_child(orphan)
	orphan.set_process(false)
	last.focus = orphan
	check(orphan.is_selected(),"Ownerless entities retain global-group selection compatibility")
	last.focus = null
	var replacement := Human.new()
	game.add_child(replacement)
	game.players.append(replacement)
	replacement.focus = cells[0]
	check(cells[0].is_selected(),"A newly appended actor is observed immediately")
	replacement.queue_free()
	await process_frame
	check(not cells[0].is_selected(),"A freed actor in the owner's temporary roster is harmless")
	game.players.pop_back()
	var robot := Robot.new()
	robot.game = game
	game.add_child(robot)
	robot.set_process(false)
	robot.set_physics_process(false)
	var ground := StaticBody2D.new()
	ground.position = Vector2(500,10)
	ground.collision_layer = 1
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(2000,20)
	collision.shape = shape
	ground.add_child(collision)
	game.add_child(ground)
	var navigation := Navigation.new(robot,game)
	await physics_frame
	var start_navigation := Time.get_ticks_usec()
	var supported := 0
	for index in 600:
		if navigation.support_at(Vector2(500,0)): supported += 1
	measurements.navigation = {"calls":600,"exclusion_scans":navigation.exclusion_scans,"duration_us":Time.get_ticks_usec()-start_navigation}
	check(supported == 600,"All three real support rays keep the same actual floor result")
	if not before: check(navigation.exclusion_scans == 600,"One exclusion scan is shared by each three-ray support query")
	var first := Station.new()
	first.game = game
	first.kind = "furnace"
	game.add_child(first)
	first.set_process(false)
	var second := Station.new()
	second.game = game
	second.kind = "furnace"
	game.add_child(second)
	second.set_process(false)
	var crates: Array[Supply] = []
	for index in 24:
		var crate := Crate.new()
		crate.game = game
		crate.kind = "ore"
		crate.amount = 4
		game.add_child(crate)
		crate.set_physics_process(false)
		crates.append(crate)
	var logistics := Logistics.new(robot)
	logistics.blocked_station = first
	logistics.chosen_crate = crates[-1]
	check(logistics._find_supply_job() and logistics.station == second and logistics.source == crates[-1],"Station rotation and the first reachable physical crate stay unchanged")
	check(logistics.crate_route_queries == 24,"Each necessary crate route remains evaluated; no unreachable cargo is accepted")
	measurements.logistics = {"stations":2,"matching_crates":24,"station_route_queries":logistics.station_route_queries,"crate_route_queries":logistics.crate_route_queries}
	if not before: check(logistics.station_route_queries == 2,"A station's identical delivery route is checked once per synchronous job search")
	var stock := {"sand":80,"limestone":80,"ore":80,"tungsten":80,"steel":80,"alloy":80,"concrete":80,"glass":80,"ammo":80,"scrap":80}
	game.set_meta(Storage.RESERVE_META,stock.duplicate())
	for crate in crates: crate.amount = Balance.PICKUP_STACK_MAX
	samples.clear()
	for repeat in 7:
		var started := Time.get_ticks_usec()
		for tick in 1000:
			for crate in crates: Storage.refill(crate)
		samples.append(Time.get_ticks_usec()-started)
	measurements.storage = {"crates":24,"ticks_per_repeat":1000,"repeats":7,"median_us":median_us(samples),"per_tick_us":median_us(samples)/1000.0}
	check(game.get_meta(Storage.RESERVE_META) == stock and crates[0].amount == Balance.PICKUP_STACK_MAX,"No-op reserve refills never mutate or lose stored resources")
	var observed: Dictionary = game.get_meta(Storage.RESERVE_META)
	crates[0].amount -= 3
	Storage.refill(crates[0])
	check(crates[0].amount == Balance.PICKUP_STACK_MAX and Storage.reserve_amount(game,"ore") == 77,"A real refill still moves exactly three finite units")
	check(observed.ore == 80,"Committing a refill retains copy-on-write ownership for older reserve observers")
	var public_copy := Storage.reserved(game)
	public_copy.ore = 0
	check(Storage.reserve_amount(game,"ore") == 77,"Public snapshot copies remain detached from authoritative stored quantities")
	game.queue_free()
	await process_frame
	var result := {"checks":checks,"failures":failures,"measurements":measurements,"mode":"before" if before else "after","fixture":"1024 real MineBlock selection methods/four actor roster; real physics support rays; real supply job logic with deterministic navigation responses;24 real Supply refill methods/10-kind ledger; isolated no-profile-save/no-upnp"}
	FileAccess.open(OUTPUT+("/before.json" if before else "/after.json"),FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("GAMEPLAY LOOP OPTIMIZATION: %d/%d checks passed" % [checks-failures,checks])
	quit(1 if failures else 0)
