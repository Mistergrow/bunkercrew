class_name ScenarioBunker
extends Node2D
## Underground rooms progress from real excavation through supports to lining.
## Open work levels and finished rooms are separate physical states.
var game: Node
var build_type := "bastion"
var position_mode := "left"
var room_left := 90.0
var room_right := 730.0
var core_x := 410.0
var ground_y := 430.0
var built_rooms := 1
var unlocked := false
var deeper_available := false
var open_depths := 0
var excavation_depths := 0
var modules: Array[ScenarioRoomSite] = []
var fields: Array[DiggableTerrain] = []
var props: Array[Node2D] = []
var roof_guns: Array[RoofTurret] = []
var passages: Array[LadderPassage] = []
var _floors: Dictionary = {}
var elapsed := 0.0
var _bootstrapped := false
var _shaft_index := -1
var _built: Dictionary = {}
var _rear_shift := Vector2.ZERO
const ROOF_Y := 245.0
const WORLD_LEFT := -250.0
const WORLD_RIGHT := 1690.0

func _ready() -> void:
	z_index = -7
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var strata = preload("res://scripts/terrain_strata.gd").new()
	if is_instance_valid(game) and "scenario_options" in game:
		strata.environment_id = str(game.scenario_options.get("environment", "sector07"))
	add_child(strata)

func configure(style_key: String,position_key: String) -> void:
	assert(not _bootstrapped,"A built bunker cannot be moved through living actors")
	build_type = style_key if ScenarioRoomCatalog.BUILD_TYPES.has(style_key) else "bastion"
	position_mode = position_key if position_key in ["left","center","right"] else "left"
	room_left = position_origin(position_mode)
	room_right = room_left+ScenarioRoomCatalog.ROOM_WIDTH
	core_x = room_left+320.0

static func position_origin(position_key: String) -> float:
	return float({"left":90.0,"center":400.0,"right":710.0}.get(position_key,90.0))

func bootstrap() -> void:
	if _bootstrapped:
		return
	configure(build_type,position_mode)
	_bootstrapped = true
	game.ladders.clear()
	game.floor_levels.assign([245.0,430.0,635.0])
	game.world_right = WORLD_RIGHT
	# Ground continues beyond both spawn points. Roof and header collisions use
	# the same cut edges as the visual frame; lower doors are destructible walls.
	_add_passage(room_left+54,ROOF_Y,18)
	_add_passage(room_left+54,ground_y,24)
	_floor(Rect2(WORLD_LEFT-160,ground_y,WORLD_RIGHT-WORLD_LEFT+320,24),"soil")
	_floor(Rect2(room_left,ROOF_Y,ScenarioRoomCatalog.ROOM_WIDTH,18),"concrete")
	_terrain(Rect2(room_left,ROOF_Y+18,25,76),"concrete")
	_terrain(Rect2(room_right-25,ROOF_Y+18,25,76),"concrete")
	_terrain(Rect2(room_left-18,430,18,225),"soil")
	_terrain(Rect2(room_right,430,18,225),"soil")
	_floor(Rect2(room_left,635,640,20),"soil")
	_shaft_index = game.ladders.size()
	game.ladders.append(Rect2(room_left+32,205,44,435))
	game.core = game._entity("core",Vector2(core_x,ground_y))
	var style := ScenarioRoomCatalog.style(build_type)
	game.core.max_hp += float(style.core_bonus)
	game.core.hp = game.core.max_hp
	game._entity("station",Vector2(room_left+167,ground_y),{"kind":"mixer"})
	game._entity("station",Vector2(room_left+516,ground_y),{"kind":"furnace"})
	# The bench belongs in the first excavated service floor, beside the future
	# ammunition press. Its own access check exposes it only after the earth clears.
	game.workshop = game._entity("field_workshop",Vector2(room_left+452,ScenarioRoomCatalog.floor_y(0)))
	game.workshop.z_index = -1
	game.workshop.refresh_access()
	# A roof gun must sit at the firing edge: a central gun would hit its own
	# solid roof on steep shots toward ground attackers. Centered bases have
	# one reachable emplacement per front and split the same starting magazine.
	var main_gun_x := room_left+12 if position_mode=="right" else room_right-12
	game.turret = game._entity("turret",Vector2(main_gun_x,ROOF_Y))
	roof_guns.append(game.turret)
	if position_mode=="right":
		game.turret.aim_angle = -PI-0.32
	elif position_mode=="center":
		var west_gun: RoofTurret = game._entity("turret",Vector2(room_left+12,ROOF_Y))
		west_gun.aim_angle = -PI-0.32
		roof_guns.append(west_gun)
		game.turret.ammo = floori(Balance.MAGAZINE/2.0)
		west_gun.ammo = floori(Balance.MAGAZINE/2.0)
	# Air-defense construction and servicing belong beside the roof access.
	# Leave the production floor for the core, machines and shelter controls.
	game.flak_station = game._entity("flak_station",Vector2(room_left+130,ROOF_Y))
	game.flak_station.gun_position = Vector2(room_left+224,35)
	game.flak_station.platform = Rect2(room_left+168,35,112,12)
	game.flak_station.access = Rect2(room_left+202,-5,44,435)
	game.medic = game._entity("field_medic",Vector2(core_x+55,ground_y))
	# Every material is a real finite crate, never a hidden global wallet.
	# Keep the future flak service bay and both tower footings clear of crates.
	for stock in [["sand",12,312],["ore",12,374],["steel",8+int(style.extra_steel),436],["concrete",8+int(style.extra_concrete),498],["ammo",18,560]]:
		game._entity("supply",Vector2(room_left+float(stock[2]),ROOF_Y),{"kind":stock[0],"amount":stock[1]})
	# Even the quiet edge has a service gate, so weather and the room outline
	# remain coherent. Both gates are traversable by crew, block real shots and
	# are targets only for enemies approaching from their own side.
	for x in [room_left+8,room_right-8]:
		var wall = game._entity("wall",Vector2(x,ground_y),{"initial_state":4})
		wall.set_meta("scenario_front",true)
	_seed_field(0,635.0,true)
	excavation_depths = 1
	_add_site(0,635.0)
	_add_prop(3,Vector2(room_left+95,ROOF_Y),Vector2(26,35))
	_add_prop(0,Vector2(room_left+612,ground_y),Vector2(29,43))
	# The radio remains on its own small control cabinet after the crafting
	# bench moves underground; there is no second crafting table upstairs.
	_add_prop(11,Vector2(room_left+229,ground_y),Vector2(38,49))
	_refresh_weather()
	queue_redraw()

func _terrain(rect: Rect2,terrain_material: String) -> StaticBody2D:
	var body: StaticBody2D = game.add_terrain(rect)
	body.set_meta("weather_material",terrain_material)
	body.add_to_group("scenario_terrain")
	return body

func _floor(rect: Rect2,terrain_material: String) -> void:
	var key:=roundi(rect.position.y)
	if _floors.has(key):
		for body in _floors[key].bodies:
			if is_instance_valid(body):
				game.remove_child(body)
				body.queue_free()
	_floors[key]={"rect":rect,"material":terrain_material,"bodies":[]}
	_rebuild_floor(key)

func _rebuild_floor(key: int) -> void:
	if not _floors.has(key): return
	var data: Dictionary=_floors[key]
	for body in data.bodies:
		game.remove_child(body)
		body.queue_free()
	data.bodies.clear()
	var rect: Rect2=data.rect
	var holes: Array[Rect2]=[]
	for passage in passages:
		if absf(passage.global_position.y-rect.position.y)<1: holes.append(passage.aperture())
	holes.sort_custom(func(a: Rect2,b: Rect2): return a.position.x<b.position.x)
	var cursor:=rect.position.x
	for hole in holes:
		if hole.position.x>cursor:
			data.bodies.append(_terrain(Rect2(cursor,rect.position.y,hole.position.x-cursor,rect.size.y),data.material))
		cursor=maxf(cursor,hole.end.x)
	if cursor<rect.end.x:
		data.bodies.append(_terrain(Rect2(cursor,rect.position.y,rect.end.x-cursor,rect.size.y),data.material))

func _add_passage(x: float,y: float,depth: float,rung_start: float=219.0) -> LadderPassage:
	for existing in passages:
		if existing.position.distance_to(Vector2(x,y))<1: return existing
	var passage:=LadderPassage.new()
	passage.game=game
	passage.position=Vector2(x,y)
	passage.slab_depth=depth
	passage.rung_origin=rung_start
	game.add_child(passage)
	passages.append(passage)
	_rebuild_floor(roundi(y))
	return passage

func add_flak_passages(station: FlakStation) -> void:
	_add_passage(station.access.get_center().x,ROOF_Y,18,20)
	_add_passage(station.access.get_center().x,station.platform.position.y,station.platform.size.y,20)
	_floor(station.platform,"metal")
	_refresh_weather()
	queue_redraw()

func passage_rects() -> Array[Rect2]:
	var result: Array[Rect2]=[]
	for passage in passages: result.append(passage.aperture())
	return result

func spawn_position(id: int) -> Vector2:
	return Vector2(core_x+66+(id-1)*40,ground_y)

func world_bounds() -> Rect2:
	return Rect2(WORLD_LEFT,-130,WORLD_RIGHT-WORLD_LEFT,maxf(800.0,430.0+excavation_depths*205.0+90.0)+130.0)

func excavated_rects() -> Array[Rect2]:
	var result: Array[Rect2] = [Rect2(room_left,ROOF_Y,640,185)]
	for index in excavation_depths:
		result.append(Rect2(room_left,ScenarioRoomCatalog.floor_y(index)-205,640,205))
	return result

func raw_rect(index: int) -> Rect2:
	return Rect2(room_left,ScenarioRoomCatalog.floor_y(index)-205,640,205)

func ensure_excavation() -> void:
	# Only the announced blueprint may expose the next depth's resources.
	if is_instance_valid(game.get("network")) and game.network.active and not game.network.is_host: return
	if open_depths < modules.size() and modules[open_depths].wave_ready():
		prepare_excavation(open_depths)

func prepare_excavation(index: int) -> bool:
	if index < 0 or index >= ScenarioRoomCatalog.ROOMS.size(): return false
	if index < excavation_depths: return true
	if index != open_depths or index != excavation_depths or index >= modules.size(): return false
	if not modules[index].wave_ready(): return false
	var floor_y := ScenarioRoomCatalog.floor_y(index)
	_add_passage(room_left+54,floor_y-205,20)
	_floor(Rect2(room_left,floor_y,640,20),"soil")
	_terrain(Rect2(room_left-18,floor_y-185,18,205),"soil")
	_terrain(Rect2(room_right,floor_y-185,18,205),"soil")
	_seed_field(index,floor_y,false)
	excavation_depths += 1
	modules[index].position = Vector2(room_left+107,floor_y)
	if not game.floor_levels.has(floor_y):
		game.floor_levels.append(floor_y)
		game.floor_levels.sort()
	game.ladders[_shaft_index] = Rect2(room_left+32,205,44,floor_y-200)
	if game.has_method("update_scenario_camera"): game.update_scenario_camera()
	_refresh_weather()
	queue_redraw()
	return true

func on_view_stage(stage: int) -> void:
	unlocked = stage>=2
	deeper_available = stage>=3
	queue_redraw()

func unlock() -> void:
	on_view_stage(2)

func unlock_deeper() -> void:
	on_view_stage(3)

func _add_site(index: int,floor_y: float) -> void:
	if index >= ScenarioRoomCatalog.ROOMS.size():
		return
	var site := ScenarioRoomSite.new()
	site.game = game
	site.bunker = self
	site.room_index = index
	site.position = Vector2(room_left+107,floor_y)
	game.add_child(site)
	modules.append(site)

func complete_room(index: int) -> bool:
	if index != open_depths or _built.has(index) or index<0 or index>=ScenarioRoomCatalog.ROOMS.size():
		return false
	var site: ScenarioRoomSite = modules[index] if index<modules.size() else null
	if not is_instance_valid(site) or not site.excavated() or not site.supported or not site.support_complete_materials() or not site.complete_materials() or not site.curing or site.curing_remaining>0.0 or not site.wave_ready():
		return false
	_built[index] = true
	open_depths += 1
	built_rooms = 1+open_depths
	var floor_y := ScenarioRoomCatalog.floor_y(index)
	# Excavation already supplied a safe footing and ladder. Only the finished
	# floor material changes now; no new ore is spawned inside a built room.
	_floor(Rect2(room_left,floor_y,640,20),"concrete")
	var spec := ScenarioRoomCatalog.spec(index)
	game._entity(spec.station,Vector2(room_left+268,floor_y))
	game.core.max_hp += float(spec.core_bonus)
	game.core.hp = minf(game.core.max_hp,game.core.hp+float(spec.core_bonus))
	if index == 3:
		for gun in roof_guns:
			if is_instance_valid(gun):
				gun.damage_multiplier += 0.25
	_add_prop(7,Vector2(room_left+354,floor_y),Vector2(33,30))
	_add_site(index+1,floor_y)
	if game.has_method("update_scenario_camera"):
		game.update_scenario_camera()
	_refresh_weather()
	queue_redraw()
	return true

func _seed_field(index: int,floor_y: float,initial: bool) -> void:
	var kinds: Array = ScenarioRoomCatalog.spec(index).seams
	var resource_map := {}
	var bonus: int = ScenarioRoomCatalog.style(build_type).ore_bonus
	for row in 3:
		for col in 10:
			# Most of the future room is ordinary earth. Ten mineral pockets
			# preserve a useful finite supply without thirty high-yield ore cells.
			var pocket := (col+index)%3 == row
			var kind: String = kinds[col%kinds.size()] if pocket else "sand"
			resource_map[Vector2i(col,row)] = {"kind":kind,"yield":((6 if index<2 else 8)+bonus) if pocket else 1}
	var field := DiggableTerrain.new()
	field.setup(game,Rect2(room_left+128,floor_y-144,480,144),resource_map)
	field.set_meta("starter_raw_seam",initial)
	field.set_meta("scenario_room_index",index)
	game.add_child(field)
	fields.append(field)

func _add_prop(kind: int,point: Vector2,size: Vector2) -> void:
	var prop: LevelProp = preload("res://scenes/level_prop.tscn").instantiate()
	prop.kind_index = kind as LevelProp.Kind
	prop.display_size = size
	prop.position = point
	prop.z_index = -6
	game.add_child(prop)
	props.append(prop)

func _refresh_weather() -> void:
	if is_instance_valid(game.get("weather")) and game.weather.has_method("refresh_collision_cache"):
		game.weather.refresh_collision_cache()

func _process(delta: float) -> void:
	elapsed += delta
	ensure_excavation()
	if is_instance_valid(game.get("scenery")) and "offset" in game.scenery:
		_rear_shift = (game.scenery.offset*0.45).round()
	queue_redraw()

func _draw() -> void:
	if not _bootstrapped:
		return
	# The cached TerrainStrata child draws the continuous earth first. Actual
	# rooms and mine recesses cut through it at the same physical coordinates.
	ScenarioBunkerArt.draw_room(self,Rect2(room_left,ROOF_Y,640,185),build_type,0,elapsed,_rear_shift,true,passage_rects())
	_draw_floor_details(ground_y,0)
	for index in excavation_depths:
		var floor_y := ScenarioRoomCatalog.floor_y(index)
		if index < open_depths:
			ScenarioBunkerArt.draw_room(self,raw_rect(index),build_type,index+1,elapsed,_rear_shift,true,passage_rects())
			_draw_floor_details(floor_y,index+1)
		else:
			preload("res://scripts/excavation_room_art.gd").draw_room(self,self,index,elapsed,_rear_shift)
	_draw_ladder()
	_draw_outer_edge()

func _draw_floor_details(floor_y: float,depth: int) -> void:
	var label: String = LocaleText.text("LEBENSRAUM / 00") if depth==0 else str(ScenarioRoomCatalog.spec(depth-1).title)
	Art.text(self,Vector2(room_left+93,floor_y-(185 if depth==0 else 205)+12),label,9,Color("cec3a0"))
	# Cabling, drains and inset landing grates follow the shared shaft. Room
	# labels are painted on the wall, so active machine prompts remain readable.
	draw_line(Vector2(room_left+89,floor_y-137),Vector2(room_left+89,floor_y-11),Color("373e32"),5)
	draw_line(Vector2(room_left+87,floor_y-137),Vector2(room_left+87,floor_y-11),Color("92764e"),2)
	if depth>0:
		draw_rect(Rect2(room_left+370,floor_y-80,25,67),Color("252f2d"))
		draw_rect(Rect2(room_left+373,floor_y-77,19,62),Color("626c55"))
		for x in range(int(room_left)+376,int(room_left)+389,5):
			draw_line(Vector2(x,floor_y-69),Vector2(x,floor_y-31),Color("303d35"),2)
		draw_rect(Rect2(room_left+388,floor_y-39,3,8),Color("aaa27c"))

func _draw_ladder() -> void:
	var bottom := maxf(635.0,ground_y+205.0*excavation_depths)
	var x := room_left+54
	draw_rect(Rect2(x-20,246,40,bottom-246),Color(0.025,0.035,0.035,0.52))
	for side in [-12,12]:
		draw_line(Vector2(x+side,209),Vector2(x+side,bottom),Color("182120"),7)
		draw_line(Vector2(x+side-1,209),Vector2(x+side-1,bottom),Color("ae8b55"),3)
	for y in range(219,int(bottom),14):
		draw_line(Vector2(x-12,y),Vector2(x+12,y),Color("c5a064"),3)
		draw_line(Vector2(x-10,y+2),Vector2(x+12,y+2),Color("4b4835"),1)

func _draw_outer_edge() -> void:
	for x in [room_left+8,room_right-8]:
		for y in range(345,422,18):
			draw_rect(Rect2(x-20,y,4,11),Color("c09e58"))
			var phase := 0.7+sin(elapsed*5.0+x)*0.3
			draw_rect(Rect2(x-7,325,14,7),Color("b44830").lightened(phase*0.13))
	# Hand-worn edge highlights make the roof a usable platform in the same
	# concrete vocabulary as the later underground floor extensions.
	for x in range(int(room_left)+31,int(room_right)-25,31):
		var in_opening:=false
		for passage in passages:
			if absf(passage.position.y-ROOF_Y)<1 and x+10>passage.aperture().position.x and x<passage.aperture().end.x: in_opening=true
		if in_opening: continue
		draw_rect(Rect2(x,249,10,2),Color("96947e"))
