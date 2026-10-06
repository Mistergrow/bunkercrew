extends Node2D
## Visible material carried by the shared weather gust. Small, bounded batches
## stay in the camera and above real shelter; no textures or rectangular quads.
const MAX_PARTICLES := 72
const MAX_PLUMES := 8
const COVER_GRID := 8.0
const PROFILES := {
	"storm_dam":{"kind":"spray","count":44,"plumes":5,"tint":Color("9db7c1"),"haze":Color("7b919d"),"gain":1.35},
	"sulfur_refinery":{"kind":"grit","count":48,"plumes":5,"tint":Color("c9b477"),"haze":Color("9d905d"),"gain":1.05},
	"radar_highlands":{"kind":"snow","count":52,"plumes":5,"tint":Color("c5c8df"),"haze":Color("929ab9"),"gain":1.2},
	"buried_megafactory":{"kind":"grit","count":46,"plumes":5,"tint":Color("b88f7c"),"haze":Color("8c6d61"),"gain":1.0},
	"sector07":{"kind":"grit","count":44,"plumes":5,"tint":Color("a39776"),"haze":Color("777566"),"gain":1.0},
	"ash_foundry":{"kind":"ash","count":48,"plumes":6,"tint":Color("bca58a"),"haze":Color("8a7a68"),"gain":1.1},
	"abandoned_harbor":{"kind":"spray","count":32,"plumes":4,"tint":Color("94b3b4"),"haze":Color("728e92"),"gain":1.15},
	"basalt_quarry":{"kind":"grit","count":56,"plumes":7,"tint":Color("b3a49c"),"haze":Color("938c87"),"gain":.9},
	"overgrown_steelworks":{"kind":"leaf","count":42,"plumes":3,"tint":Color("a9af68"),"haze":Color("7f8861"),"gain":.9},
	"frozen_rail_yard":{"kind":"snow","count":64,"plumes":7,"tint":Color("cadcdd"),"haze":Color("a2bdc6"),"gain":1.05},
	"iron_canyon":{"kind":"grit","count":64,"plumes":8,"tint":Color("d4ab79"),"haze":Color("b58c61"),"gain":1.35},
	"flooded_power_station":{"kind":"leaf","count":30,"plumes":3,"tint":Color("9cae80"),"haze":Color("729e91"),"gain":.85},
	"mountain_pass":{"kind":"grit","count":48,"plumes":6,"tint":Color("a9b5bd"),"haze":Color("929ea9"),"gain":1.4},
}
var weather: Node2D
var environment_id := "sector07"
var elapsed := 0.0
var particles: Array[Dictionary] = []
var plumes: Array[Dictionary] = []
var visible_bounds := Rect2(0,0,1440,430)
var spawned := 0
var culled := 0
var _profile: Dictionary = PROFILES.sector07
var _rng := RandomNumberGenerator.new()
var _cover: Dictionary = {}
var _cover_clock := 1.0
var _draw_clock := 0.0
var _primed := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	z_as_relative = false
	z_index = 11
	_rng.seed = 194611

func configure_environment(environment: Dictionary) -> void:
	environment_id = str(environment.get("id","sector07"))
	_profile = PROFILES.get(environment_id,PROFILES.sector07)
	_rng.seed = 194611 + environment_id.hash()
	particles.clear()
	plumes.clear()
	_cover.clear()
	_primed = false
	_cover_clock = 1.0

func set_reduced(value: bool) -> void:
	if value:
		particles.clear()
		plumes.clear()
	_primed = false
	queue_redraw()

func _reduced() -> bool:
	return not is_instance_valid(weather) or bool(weather.reduced_effects)

func _refresh_bounds() -> void:
	# Actual camera bounds, not the much wider rain respawn area. Cap work even
	# when a deep excavation makes the screen cover several thousand pixels.
	var camera_rect := get_canvas_transform().affine_inverse()*get_viewport_rect()
	visible_bounds = camera_rect.grow(70).intersection(Rect2(-2600,-800,6600,1230))
	_cover.clear()

func _shelter_y(x: float) -> float:
	var column := floori(x/COVER_GRID)
	if _cover.has(column): return float(_cover[column])
	var left := float(column)*COVER_GRID
	var ceiling := minf(430.0,minf(weather.rain_surface(left),weather.rain_surface(left+COVER_GRID)))
	var game = weather.get("game")
	if is_instance_valid(game):
		var bunker = game.get("scenario_bunker")
		if is_instance_valid(bunker):
			# Wind skims an open hatch instead of dropping into its mine shaft.
			if left+COVER_GRID>=bunker.room_left and left<=bunker.room_right:
				ceiling = minf(ceiling,245.0)
		elif left<873.0:
			ceiling = minf(ceiling,weather._bunker_surface(left))
	_cover[column] = ceiling
	return ceiling

func outdoors(point: Vector2,margin: float=3.0) -> bool:
	return visible_bounds.has_point(point) and point.y+margin<minf(430.0,_shelter_y(point.x))

func _birth(plume: bool,distributed: bool=false) -> Dictionary:
	for attempt in 8:
		var x := _rng.randf_range(visible_bounds.position.x+12,visible_bounds.end.x-12)
		var ceiling := _shelter_y(x)
		# Material is close to a real exterior surface. A built high flak deck
		# can therefore interrupt a gust instead of leaving it inside its steel.
		var altitude := _rng.randf_range(10,25) if plume else _rng.randf_range(9,106)
		var point := Vector2(x,ceiling-altitude)
		if not outdoors(point,5) or weather.gust_at(point)<.08: continue
		var life := _rng.randf_range(3.4,5.6) if plume else _rng.randf_range(2.4,4.8)
		spawned += 1
		return {"point":point,"age":_rng.randf_range(.3,life*.65) if distributed else 0.0,
			"life":life,"phase":_rng.randf_range(0,TAU),"speed":_rng.randf_range(.75,1.35),
			"size":_rng.randf_range(.8,1.4),"kind":str(_profile.kind),"base_y":point.y}
	return {}

func _process(delta: float) -> void:
	if get_tree().paused or _reduced() or not is_finite(delta) or delta<=0.0: return
	elapsed = float(weather.elapsed)
	_cover_clock += delta
	if _cover_clock>=.12:
		_cover_clock = 0.0
		_refresh_bounds()
	if visible_bounds.size.x<24 or visible_bounds.size.y<8:
		particles.clear()
		plumes.clear()
		return
	var step := minf(delta,.1)
	_move(particles,step,false)
	_move(plumes,step,true)
	# Sample a few positions, not only the camera centre: a traveling gust may
	# be entering one edge while the centre is still calm. Pool caps stay fixed.
	var activity := 0.0
	for sample in 5:
		activity = maxf(activity,weather.gust_at(Vector2(lerpf(visible_bounds.position.x,visible_bounds.end.x,float(sample)/4.0),350)))
	for bucket: Array[Dictionary] in [particles,plumes]:
		var plume := is_same(bucket,plumes)
		var limit := mini(int(_profile.plumes),MAX_PLUMES) if plume else mini(int(_profile.count),MAX_PARTICLES)
		limit = ceili(float(limit)*smoothstep(.06,.65,activity))
		var births := clampi(limit-bucket.size(),0,limit if not _primed else 3)
		for index in births:
			var item := _birth(plume,not _primed)
			if not item.is_empty(): bucket.append(item)
	_primed = true
	_draw_clock += delta
	if _draw_clock>=1.0/30.0:
		_draw_clock = 0.0
		queue_redraw()

func _move(bucket: Array[Dictionary],delta: float,plume: bool) -> void:
	for index in range(bucket.size()-1,-1,-1):
		var item := bucket[index]
		item.age += delta
		var point: Vector2 = item.point
		var gust: float = weather.gust_at(point)
		var speed: float = weather.wind_at(point).x*(.72 if plume else 1.05)
		point.x += speed*float(item.speed)*delta
		var lift := 3.0 if plume else 15.0 if item.kind=="leaf" else 8.0
		point.y = float(item.base_y)+sin(elapsed*(1.6 if plume else 2.5)+float(item.phase))*lift*gust
		item.point = point
		if float(item.age)>=float(item.life) or not outdoors(point,5):
			bucket.remove_at(index)
			culled += 1

func _fade(item: Dictionary) -> float:
	return clampf(minf(float(item.age)*2.8,(float(item.life)-float(item.age))*1.8),0,1)

func _draw() -> void:
	if _reduced(): return
	for item in plumes:
		_draw_plume(item)
	for item in particles:
		_draw_particle(item)

func _draw_plume(item: Dictionary) -> void:
	var center: Vector2 = item.point
	var size := float(item.size)
	var alpha := _fade(item)*smoothstep(.03,.35,weather.gust_at(center))*.21
	var tint: Color = _profile.haze
	# Overlapping jagged ellipses form irregular, feathered dust/snow banks.
	# Each tiny piece is independently clipped above shelter, including its
	# entire lower edge. No opaque background or rectangular card exists.
	for puff in 7:
		var phase := float(item.phase)+puff*1.9
		var at := center+Vector2((puff-3)*13.0*size,sin(phase+elapsed*1.8)*3)
		for ring in 2:
			var width := (18.0+sin(phase)*4.0)*size*(1.0-ring*.25)
			var height := (5.0+cos(phase)*1.5)*size*(1.0-ring*.24)
			if not outdoors(at+Vector2(-width,height),2) or not outdoors(at+Vector2(width,height),2) or not outdoors(at+Vector2(0,height),2): continue
			var polygon := PackedVector2Array()
			for corner in 10:
				var angle := TAU*corner/10.0
				polygon.append((at+Vector2(cos(angle)*width,sin(angle)*height)).round())
			var color := tint.lightened(.10 if ring==1 else 0.0)
			color.a = alpha*(.48 if ring==0 else .64)*(1.0-absf(float(puff-3))*.13)
			draw_colored_polygon(polygon,color)

func _draw_particle(item: Dictionary) -> void:
	var point: Vector2 = Vector2(item.point).round()
	if not outdoors(point,5): return
	var tint: Color = _profile.tint
	tint = tint.darkened(.18*(.5+.5*sin(float(item.phase))))
	tint.a = _fade(item)*smoothstep(.01,.25,weather.gust_at(point))*(.82 if item.kind in ["leaf","snow"] else .62)
	var size := float(item.size)
	if item.kind=="leaf":
		var angle := elapsed*4.5+float(item.phase)
		var wide := maxf(1,absf(cos(angle))*5.0)*size
		var vertices := PackedVector2Array([point+Vector2(-wide,0),point+Vector2(-1,-3),point+Vector2(wide,-1),point+Vector2(1,2)])
		draw_colored_polygon(vertices,tint)
		draw_line(point-Vector2(1,0),point+Vector2(2,-1),Color(tint.r*.5,tint.g*.5,tint.b*.5,tint.a),1,false)
	elif item.kind=="snow":
		draw_rect(Rect2(point,Vector2(2,2)*size),tint)
		if size>1.15: draw_rect(Rect2(point+Vector2(-1,1),Vector2(4,1)),Color(tint.r,tint.g,tint.b,tint.a*.7))
	else:
		draw_rect(Rect2(point,Vector2(2 if size>1 else 1,1 if item.kind=="spray" else 2)),tint)
		if size>1.1: draw_rect(Rect2(point+Vector2(-3,1),Vector2(1,1)),Color(tint.r,tint.g,tint.b,tint.a*.45))

func diagnostics() -> Dictionary:
	return {"environment":environment_id,"kind":_profile.kind,"particles":particles.size(),"plumes":plumes.size(),
		"visible":particles.size()+plumes.size(),"elapsed":elapsed,"spawned":spawned,"culled":culled,"reduced":_reduced(),"cover_columns":_cover.size()}
