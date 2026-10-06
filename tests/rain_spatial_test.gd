extends SceneTree
## Compare the broad phase against native exhaustive segment intersections,
## including negative coordinates, cell corners and long wind-exposure rays.
var checks:=0
var failures:=0
class FullScanCollision extends RainCollision:
	func _candidate_actor_indices(_from: Vector2,_to: Vector2) -> Array[int]:
		var result: Array[int]=[]
		for index in _actor_records.size(): result.append(index)
		return result
	func _candidate_indices(cells: Dictionary, _from: Vector2, _to: Vector2, _cell_size: float = CELL_SIZE) -> Array[int]:
		var result:Array[int]=[]
		for indices: Array in cells.values():
			for index: int in indices:
				if not result.has(index): result.append(index)
		return result
func _initialize(): run.call_deferred()
func check(ok:bool,label:String):
	checks+=1
	print("RAIN GRID ","PASS " if ok else "FAIL ",label)
	if not ok:
		failures+=1
		push_error(label)
func grid_equivalence(cell_size: float) -> void:
	var solver:=RainCollision.new()
	var cells:Dictionary={}
	var segments:Array[Dictionary]=[]
	var rng:=RandomNumberGenerator.new()
	rng.seed=209301
	for pair in [[Vector2(-64,-128),Vector2(-64,256)],[Vector2(0,0),Vector2(256,256)],[Vector2(64,64),Vector2(256,64)],[Vector2(-128,-64),Vector2(128,-64)]]:
		segments.append({"from":pair[0],"to":pair[1]})
	for index in 600:
		var from:=Vector2(rng.randf_range(-700,2200),rng.randf_range(-400,850))
		segments.append({"from":from,"to":from+Vector2(rng.randf_range(-90,90),rng.randf_range(-45,45))})
	for index in segments.size(): solver._index_segment(cells,segments[index],index,cell_size)
	var rays:Array=[]
	for pair in [[Vector2(-64,-900),Vector2(-64,300)],[Vector2(-200,64),Vector2(300,64)],[Vector2(-128,-64),Vector2(256,256)],[Vector2(64,-500),Vector2(64,850)],[Vector2(-700,64),Vector2(2200,64)]]:
		rays.append(pair)
	for index in 384:
		var from:=Vector2(rng.randf_range(-750,2250),rng.randf_range(-500,900))
		var to:=from+Vector2(rng.randf_range(-230,230),rng.randf_range(-1850,1850)) if index%2 else from+Vector2(rng.randf_range(-2,2),rng.randf_range(0,14))
		rays.append([from,to])
	var covers_all:=true
	var nearest_equal:=true
	var unique:=true
	var short_candidates:=0
	var short_count:=0
	for ray in rays:
		var from:Vector2=ray[0]
		var to:Vector2=ray[1]
		var candidates:=solver._candidate_indices(cells,from,to,cell_size)
		var encountered:Dictionary={}
		for index in candidates:
			unique=unique and not encountered.has(index)
			encountered[index]=true
		var brute_nearest:=Vector2.INF
		var brute_distance:=INF
		for index in segments.size():
			var point=Geometry2D.segment_intersects_segment(from,to,segments[index].from,segments[index].to)
			if point==null: continue
			covers_all=covers_all and encountered.has(index)
			if from.distance_squared_to(point)<brute_distance:
				brute_nearest=point
				brute_distance=from.distance_squared_to(point)
		var candidate_nearest:=Vector2.INF
		var candidate_distance:=INF
		for index in candidates:
			var hit:=solver._intersect_segment(from,to,segments[index])
			if hit.is_empty(): continue
			if from.distance_squared_to(hit.position)<candidate_distance:
				candidate_nearest=hit.position
				candidate_distance=from.distance_squared_to(hit.position)
		nearest_equal=nearest_equal and (candidate_nearest==brute_nearest or candidate_nearest.distance_to(brute_nearest)<0.01)
		if from.distance_to(to)<20:
			short_count+=1
			short_candidates+=candidates.size()
	check(covers_all,"Grid includes every native intersection across 389 varied rays")
	check(nearest_equal,"Nearest contact is identical to exhaustive geometry checks")
	check(unique,"Segments spanning cells are checked once per ray")
	check(float(short_candidates)/maxi(1,short_count)<float(segments.size())*0.10,"Short rain sweeps examine under ten percent of scene segments on average")
	print("RAIN GRID METRICS: %.0fpx cells / %d segments / %.2f mean candidates per short sweep"%[cell_size,segments.size(),float(short_candidates)/maxi(1,short_count)])

func run() -> void:
	grid_equivalence(RainCollision.CELL_SIZE)
	grid_equivalence(RainCollision.ACTOR_CELL_SIZE)
	await scene_equivalence()
	print("RAIN GRID: %d/%d passed"%[checks-failures,checks])
	quit(1 if failures else 0)

func scene_equivalence():
	var game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene=game
	game.start(2)
	game.rounds.running=false
	game.rounds.set_process(false)
	game.weather.set_process(false)
	game.medic.set_physics_process(false)
	for worker in game.players: worker.set_physics_process(false)
	var worker=game.players[0]
	worker.position=Vector2(600,245)
	var machine=game._entity("enemy",Vector2(1170,430),{"kind":"bastion","wave":20})
	machine.set_physics_process(false)
	var aircraft=game._entity("air_enemy",Vector2(1240,160),{"kind":"sky_fortress","wave":20})
	aircraft.set_physics_process(false)
	for frame in 3:
		await physics_frame
		await process_frame
	var full:=FullScanCollision.new()
	full.weather=game.weather
	var queries:Array=[
		[Vector2(600,64),Vector2(600,256),true,null],
		[Vector2(600,64),Vector2(600,256),true,worker],
		[Vector2(600,64),Vector2(600,256),false,null],
		[Vector2(384,64),Vector2(416,256),true,null],
		[Vector2(730,-192),Vector2(736,300),true,null],
		[Vector2(760,64),Vector2(850,512),false,null],
		[Vector2(-64,-128),Vector2(-64,512),true,null],
		[Vector2(1100,-256),Vector2(1190,512),true,null],
		[Vector2(1100,-256),Vector2(1190,512),true,machine],
		[Vector2(1240,-128),Vector2(1240,512),true,null],
		[Vector2(1240,-128),Vector2(1240,512),true,aircraft],
		[Vector2(1100,-1400),Vector2(1280,512),false,null],
	]
	var same:=true
	for query in queries:
		var fast:Dictionary=game.weather.trace_rain(query[0],query[1],query[2],query[3])
		var exhaustive:Dictionary=full.trace(query[0],query[1],query[2],query[3])
		if fast.is_empty() or exhaustive.is_empty():
			same=same and fast.is_empty()==exhaustive.is_empty()
		else:
			same=same and fast.position.distance_to(exhaustive.position)<0.01 and fast.get("collider")==exhaustive.get("collider") and fast.material==exhaustive.material
	check(same,"Twelve actual-world long/border/exclusion rays match a full contour scan")
	var included:Dictionary=game.weather.trace_rain(Vector2(600,64),Vector2(600,256),true)
	var excluded:Dictionary=game.weather.trace_rain(Vector2(600,64),Vector2(600,256),true,worker)
	var static_only:Dictionary=game.weather.trace_rain(Vector2(600,64),Vector2(600,256),false)
	check(included.get("collider")==worker and excluded.get("collider")!=worker and absf(excluded.position.y-245)<0.01,"Actor exclusion reaches the real roof below the worker")
	check(static_only.get("collider")!=worker and absf(static_only.position.y-245)<0.01,"Static sky exposure ignores actor silhouettes in the indexed scene")
	await preload("res://tests/scene_cleanup.gd").free_scene(game,self)
