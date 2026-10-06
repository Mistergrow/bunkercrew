extends SceneTree
const Excavation := preload("res://tests/scenario_excavation_fixture.gd")
## Real room fixtures and physics, with supplied construction deltas. This
## checks ownership and routes; the separate rendered test covers presentation.
class TestRounds extends Node:
	var wave := 1
	var phase := "build"
class TestGame extends Node2D:
	var ladders: Array[Rect2] = []
	var floor_levels: Array[float] = []
	var world_right := 1400.0
	var players: Array = []
	var player_count := 1
	var started := false
	var core
	var turret
	var workshop
	var flak_station
	var medic
	var weather
	var scenery
	var combat_events
	var upgrades
	var rounds
	var stats := {"mined":0,"produced":0,"built":0,"kills":0}
	func _ready() -> void:
		rounds = TestRounds.new()
		add_child(rounds)
		upgrades = UpgradeSystem.new()
		upgrades.game = self
		add_child(upgrades)
	func _entity(scene_name: String,point: Vector2,properties: Dictionary = {}):
		var entity = load("res://scenes/"+scene_name+".tscn").instantiate()
		entity.game = self
		entity.position = point
		for key in properties:
			entity.set(key,properties[key])
		add_child(entity)
		return entity
	func add_terrain(rect: Rect2) -> StaticBody2D:
		var body := StaticBody2D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		var shape := CollisionShape2D.new()
		var box := RectangleShape2D.new()
		box.size = rect.size
		shape.shape = box
		shape.position = rect.get_center()
		body.add_child(shape)
		add_child(body)
		return body
	func sound(_kind): pass
	func fx(_position,_color,_count): pass
	func notify(_text): pass
	func spawn_pickup(_kind,_amount,_at): pass
	func impact(_at,_material,_direction,_scale): pass
	func on_core_destroyed(): pass
class TestWorker extends Node2D:
	var inventory: Dictionary = {}
	var player_id := 1
	var reject := false
	func can_act() -> bool: return true
	func take_item(kind: String,amount: int = 1) -> bool:
		if reject or int(inventory.get(kind,0))<amount: return false
		inventory[kind] = int(inventory[kind])-amount
		return true
	func add_item(kind: String,amount: int = 1) -> int:
		inventory[kind] = int(inventory.get(kind,0))+amount
		return amount
	func selected_material() -> String: return ""
	func carried_count() -> int:
		var total := 0
		for amount in inventory.values(): total += int(amount)
		return total

var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool,label: String) -> void:
	checks += 1
	print("SCENARIO ROOM %s: %s" % ["PASS" if value else "FAIL",label])
	if not value:
		failures += 1
		push_error(label)

func run() -> void:
	InputSetup.install()
	var game := TestGame.new()
	root.add_child(game)
	var bunker := ScenarioBunker.new()
	bunker.game = game
	bunker.configure("workshop","center")
	game.add_child(bunker)
	bunker.bootstrap()
	await physics_frame
	await physics_frame
	check(bunker.built_rooms==1 and bunker.open_depths==0 and bunker.modules.size()==1,"Exactly one finished room and one available plan at the start")
	check(bunker.room_left==400 and bunker.room_right==1040 and bunker.core_x==720,"Center placement moves the actual room, not just the camera")
	check(game.core.global_position==Vector2(720,430) and game.turret.global_position==Vector2(1028,245),"Core and roof gun follow the real bunker position")
	check(bunker.roof_guns.size()==2 and bunker.roof_guns[1].global_position==Vector2(412,245) and bunker.roof_guns[0].ammo+bunker.roof_guns[1].ammo==Balance.MAGAZINE,"A centered bunker has edge emplacements on both fronts and divides the finite starting magazine")
	check(game.flak_station.gun_position==Vector2(624,35) and game.flak_station.access.position.x==602,"Paid flak and its ladder use the chosen construction coordinates")
	check(game.floor_levels==[245.0,430.0,635.0] and game.ladders[0].end.y==640,"The initial soil footing and roof share a continuous reachable ladder")
	check(bunker.fields.size()==1 and bunker.fields[0].remaining_count()==30 and bunker.excavation_depths==1,"Thirty finite earth cells fill the future room before any paid construction")
	var worker := TestWorker.new()
	game.add_child(worker)
	worker.position = Vector2(bunker.room_left+108,635)
	var block := bunker.fields[0].cell_at(Vector2i(0,2))
	check(block.can_interact(worker),"A worker on the initial shaft footing can reach the raw seam before construction")
	block.interact(worker,block.mining_duration()+0.1)
	check(worker.carried_count()==1 and bunker.fields[0].remaining_count()==29,"Ordinary earth yields one sand unit and reveals the next solid face")
	var site := bunker.modules[0]
	site.set_process(false)
	check(not bunker.complete_room(0),"Unpaid direct completion cannot bypass construction")
	worker.inventory = {"concrete":5,"steel":4,"ore":2}
	site.interact(worker,100.0)
	check(site.materials.is_empty() and site.support_materials.is_empty() and worker.inventory.steel==4,"A full material load cannot bypass unexcavated earth")
	check(await Excavation.clear_terrain(bunker.fields[0],worker),"Every remaining cell is physically mined before supports become available")
	worker.inventory = {"concrete":5,"steel":4,"ore":2}
	site.interact(worker,0.10)
	check(site.support_materials.is_empty() and worker.inventory.steel==4,"Held filling never deducts before the transfer interval")
	worker.reject = true
	site.interact(worker,1.0)
	check(site.support_materials.is_empty() and worker.inventory.steel==4,"Failed inventory deductions never create support materials")
	worker.reject = false
	Excavation.pay_supports(site,worker)
	check(site.supported and site.support_materials=={"steel":2} and site.materials.is_empty(),"Two paid steel units build supports before any wall or machine")
	for i in 5:
		site.interact(worker,1.0)
	check(site.materials=={"concrete":4,"steel":1} and worker.inventory=={"concrete":1,"steel":1,"ore":2},"Supports plus room consume the unchanged total cost and preserve unrelated cargo")
	var before_hp: float = game.core.max_hp
	game.rounds.phase = "attack"
	site.interact(worker,ScenarioRoomCatalog.BUILD_TIME)
	check(site.curing and bunker.built_rooms==1 and game.core.max_hp==before_hp,"Building during an attack starts real curing without awarding early room benefits")
	site.interact(worker,50.0)
	check(site.can_interact(worker) and site.prompt(worker).contains("härtet") and site.curing_remaining==ScenarioRoomCatalog.CURE_TIME,"A curing room remains inspectable and held interaction cannot restart or bypass curing")
	site._process(ScenarioRoomCatalog.CURE_TIME-0.1)
	check(bunker.built_rooms==1 and not site.built,"Paid concrete waits for its entire cure time")
	site._process(0.11)
	await physics_frame
	check(site.built and bunker.built_rooms==2 and bunker.open_depths==1,"The first cured plan creates a full paid basement")
	check(game.core.max_hp==before_hp+40 and bunker.modules.size()==2,"A completed room awards its exact structural benefit and exposes the next plan")
	check(get_nodes_in_group("stations").any(func(station): return station.kind=="ammo_press"),"The new room contains a working recipe-driven ammunition press")
	check(bunker.fields[0].is_cleared() and route_clear(game,Vector2(bunker.room_left+94,635),Vector2(bunker.room_left+590,635)),"The finished room is clear across its entire width, without a leftover ore box")
	var count_before := get_nodes_in_group("scenario_terrain").size()
	site._process(100)
	check(not bunker.complete_room(0) and game.core.max_hp==before_hp+40 and get_nodes_in_group("scenario_terrain").size()==count_before,"Duplicate completion cannot duplicate floors, stations or core health")
	var second := bunker.modules[1]
	second.set_process(false)
	worker.inventory = {"concrete":10,"steel":10}
	second.interact(worker,100)
	check(second.materials.is_empty() and worker.inventory.concrete==10 and second.prompt(worker).contains("Welle 5"),"A locked deeper plan names its wave and never consumes materials")
	game.rounds.wave = 5
	bunker.ensure_excavation()
	check(bunker.excavation_depths==2 and bunker.open_depths==1 and second.position.y==840,"Wave five opens a real raw work level, separately from the finished room count")
	check(await Excavation.clear_terrain(bunker.fields[1],worker),"The second room requires its own complete excavation")
	var worker2 := TestWorker.new()
	worker2.player_id = 2
	game.add_child(worker2)
	worker2.inventory = {"steel":7}
	worker.inventory = {"concrete":9}
	Excavation.pay_supports(second,worker2)
	for i in 6:
		second.interact(worker,1.0)
		second.interact(worker2,1.0)
	check(second.supported and second.materials=={"concrete":6,"steel":2} and worker.inventory.concrete==3 and worker2.inventory.steel==3,"Co-op workers share supports and room buffers without overdrawing either inventory")
	second.interact(worker,3.0)
	second._process(6.1)
	await physics_frame
	check(bunker.built_rooms==3 and game.floor_levels.has(840.0) and game.ladders[0].end.y==845,"The next paid room extends physical floors and the same continuous shaft")
	check(get_nodes_in_group("stations").any(func(station): return station.kind=="glass" and station.input_kinds().has("limestone")),"Glass production is the existing sand-plus-limestone recipe")
	check(bunker.fields.size()==2 and bunker.fields[1].resource_map.values().any(func(value): return value.kind=="limestone"),"The glassworks exposes finite limestone deposits in its actual excavation bay")
	check(route_clear(game,Vector2(bunker.room_left+94,840),Vector2(bunker.room_left+280,840)),"The new glassworks keeps its entire production route clear of mining cells")
	game.flak_station.available = true
	game.flak_station.materials = {"steel":3,"concrete":2,"ammo":1}
	game.rounds.wave = 6
	game.flak_station._complete()
	check(game.flak_station.turret.global_position==Vector2(624,35) and game.ladders[-1]==game.flak_station.access,"Flak construction keeps turret, collision platform and climb route aligned after relocation")
	var shifted := ScenarioBunker.new()
	for key in ["left","center","right"]:
		shifted.configure("stronghold",key)
		check(shifted.room_right-shifted.room_left==640 and shifted.spawn_position(2).x>shifted.spawn_position(1).x,"%s placement preserves width and separate player spawn points" % key)
	shifted.free()
	await preload("res://tests/scene_cleanup.gd").free_scene(game,self)
	print("SCENARIO BUNKER RESULT: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func route_clear(game: Node2D,from: Vector2,to: Vector2) -> bool:
	var shape := RectangleShape2D.new()
	shape.size = Vector2(22,40)
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0,from-Vector2(0,20.5))
	query.collision_mask = 1
	query.motion = to-from
	var result := game.get_world_2d().direct_space_state.cast_motion(query)
	return result[0]>=0.999
