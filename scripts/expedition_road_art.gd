extends Node2D
## Cached roadside furniture. It uses the bunker material palette at world scale.
var game
var controller
const DEPOT:=preload("res://assets/expedition/fuel_depot_v1.png")
const LANDMARKS:=preload("res://assets/expedition/roadside_landmarks_v1.png")
var elapsed:=0.0
var _clock:=0.0
var depth: Node2D
var _last_reduced:=false
var _travel_view:=false
var _legacy_visibility: Dictionary={}
const BUNKER_ART := ["core.gd","station.gd","recipe_station.gd","turret.gd","flak_station.gd","flak_turret.gd","wall.gd","supply.gd","field_workshop.gd","diggable_terrain.gd","mine_block.gd","resource_pickup.gd","expansion_site.gd","excavation_site.gd","dome_controller.gd","dome_segment.gd","scenario_lighting.gd","scenery_fire_lighting.gd"]
const REGIONS:=[Rect2(36,265,775,245),Rect2(886,12,610,498),Rect2(40,575,864,365),Rect2(930,571,574,377)]
const INK:=Color("171e20")
const STEEL:=Color("596157")
const EDGE:=Color("929782")
const AMBER:=Color("bf9956")

func _ready() -> void:
	process_mode=Node.PROCESS_MODE_PAUSABLE
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	depth=preload("res://scripts/expedition_depth.gd").new()
	depth.name="TravelDepthPlates"
	depth.game=game
	depth.controller=controller
	add_child(depth)
	for index in 8:
		var kind:=index%3
		if index==2: continue # Give the selected supply stop a clear silhouette.
		_place_landmark(LANDMARKS,REGIONS[kind],Vector2(1500+index*285,430),[130,125,190][kind],kind==2)
	var stop_id: String=controller.state.expedition.selected_stop
	if stop_id.ends_with(":fuel"):
		_place_landmark(DEPOT,Rect2(65,12,2008,650),Vector2(2210,430),280)
	elif stop_id.ends_with(":weapon"):
		_place_landmark(LANDMARKS,REGIONS[3],Vector2(2200,430),100)
	else:
		_place_landmark(LANDMARKS,REGIONS[2],Vector2(2250,430),200,true)
	_sync_travel_view()

func _draw() -> void:
	var road_left: float=float(game.get("world_left")) if is_instance_valid(game) else 740.0
	var road_right: float=float(game.get("world_right")) if is_instance_valid(game) else 3700.0
	var road_width: float=maxf(0.0,road_right-road_left)
	# Wheel contact remains the real y=430 collision plane. The darker fascia
	# gives the carriageway thickness without changing its playable geometry.
	draw_rect(Rect2(road_left,430,road_width,24),Color("242d2b"))
	draw_rect(Rect2(road_left,430,road_width,7),Color("737869"))
	draw_rect(Rect2(road_left,430,road_width,2),Color("b4b19a"))
	draw_rect(Rect2(road_left,438,road_width,2),Color("131d1e"))
	for x in range(floori(road_left),ceili(road_right),64):
		draw_line(Vector2(x,431),Vector2(x+3,453),INK,1,false)
		for i in 3: draw_rect(Rect2(x+12+i*11,432+(i%2)*2,5,1),Color("90937c"))
		draw_rect(Rect2(x+8,442,45,6),Color("39433a"))
		draw_line(Vector2(x+8,441),Vector2(x+51,441),Color("5c6759"),1,false)
		if posmod(x,192)==0:
			for slot in 5: draw_rect(Rect2(x+15+slot*5,440,2,10),INK)
	for index in 11:
		var x:=1550.0+index*192
		# Low crash barriers leave aiming silhouettes unobstructed.
		for post in [0,86]:
			draw_rect(Rect2(x+post,396,6,34),INK)
			draw_rect(Rect2(x+post+1,397,3,31),EDGE)
		var length:=70 if index%4==1 else 94
		draw_rect(Rect2(x,398,length,9),INK)
		draw_rect(Rect2(x+1,399,length-2,3),STEEL)
		draw_line(Vector2(x+2,399),Vector2(x+length-1,399),EDGE,1,false)
		if index%3==0:
			draw_rect(Rect2(x+39,404,13,10),AMBER)
			draw_line(Vector2(x+41,412),Vector2(x+48,405),INK,2)
		# Survey markers are small and readable at the normal gameplay zoom.
		if index%2==0:
			draw_rect(Rect2(x+126,380,4,50),STEEL)
			draw_rect(Rect2(x+111,375,33,19),INK)
			draw_rect(Rect2(x+113,377,29,15),STEEL)
			Art.text(self,Vector2(x+117,388),"%02d"%(index+1),9,EDGE)
	# Sparse large route signs read as equipment on the actual roadside rather
	# than repeating decorative UI cards. The catalog localizes the destination.
	var destination: String=str(controller.state.pending_node)
	var title: String=str(CampaignCatalog.node(destination).get("title",""))
	if not title.is_empty():
		for x in [1770.0,2970.0]:
			draw_rect(Rect2(x+7,350,4,80),INK)
			draw_rect(Rect2(x+8,350,2,80),EDGE)
			draw_rect(Rect2(x-22,342,124,28),INK)
			draw_rect(Rect2(x-21,343,122,25),Color("4b584b"))
			draw_line(Vector2(x-20,344),Vector2(x+98,344),EDGE,1,false)
			Art.text(self,Vector2(x-14,355),title,7,Color("d2ceb0"))
			draw_line(Vector2(x+77,361),Vector2(x+89,361),AMBER,2,false)
			draw_polyline(PackedVector2Array([Vector2(x+85,357),Vector2(x+90,361),Vector2(x+85,365)]),AMBER,2,false)

func _place_landmark(texture: Texture2D,region: Rect2,at: Vector2,width: float,wind: bool=false) -> void:
	var sprite:=Sprite2D.new()
	sprite.texture=texture
	sprite.region_enabled=true
	sprite.region_rect=region
	sprite.centered=false
	var ratio:=width/region.size.x
	sprite.scale=Vector2.ONE*ratio
	sprite.position=at-Vector2(width*.5,region.size.y*ratio)
	var shader_material:=ShaderMaterial.new()
	shader_material.shader=preload("res://shaders/convoy_landmark.gdshader")
	shader_material.set_shader_parameter("cloth_motion",wind)
	shader_material.set_shader_parameter("sprite_height",region.size.y)
	shader_material.set_shader_parameter("phase",at.x*.019)
	sprite.material=shader_material
	add_child(sprite)

func _process(delta: float) -> void:
	_sync_travel_view()
	var weather=game.get("weather") if is_instance_valid(game) else null
	var reduced: bool=is_instance_valid(weather) and weather.get("reduced_effects")==true
	if not reduced: elapsed+=delta
	_clock+=delta
	if _clock<.05 and reduced==_last_reduced: return
	_clock=0
	_last_reduced=reduced
	var truck=controller.get("vehicle") if is_instance_valid(controller) else null
	var animation: float=float(truck.animation_time) if is_instance_valid(truck) else elapsed
	for child in get_children():
		if child is Sprite2D:
			child.material.set_shader_parameter("motion_gain",0.0 if reduced else 1.0)
			if not reduced: child.material.set_shader_parameter("animation_time",animation)

func _sync_travel_view() -> void:
	var active: bool=is_instance_valid(controller) and controller.stage in ["travel","stop","failed"]
	if active==_travel_view: return
	_travel_view=active
	if not active:
		_restore_bunker_art()
		return
	# Keep authoritative nodes and collisions alive. Only the visual bunker is
	# suppressed in the dedicated journey composition; none of this is saved.
	for node in game.get_children():
		if not node is CanvasItem or node==self: continue
		if node.is_in_group("convoy_vehicles") or node.is_in_group("players") or node.is_in_group("medics"): continue
		var script: Script=node.get_script()
		var filename: String=script.resource_path.get_file() if script!=null else ""
		if filename in BUNKER_ART or node==game.get("scenario_bunker") or node==game.get("scenery") or node==game.get("dressing") or node==game.get("environment_growth"):
			_legacy_visibility[node.get_instance_id()]={"node":weakref(node),"visible":node.visible}
			node.hide()

func _restore_bunker_art() -> void:
	for value: Dictionary in _legacy_visibility.values():
		var node=value.node.get_ref()
		if is_instance_valid(node): node.visible=value.visible
	_legacy_visibility.clear()

func _exit_tree() -> void:
	_restore_bunker_art()
