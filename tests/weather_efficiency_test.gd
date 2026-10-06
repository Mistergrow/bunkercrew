extends SceneTree
## Exact visible outlines, bounded retained geometry and native query reuse.
## Current conservative envelopes are checked against actual authored art.
const Cleanup := preload("res://tests/scene_cleanup.gd")
var checks := 0
var failures := 0

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children(): freeze(child)

func same_geometry(first: Array[Dictionary], second: Array[Dictionary]) -> bool:
	if first.size() != second.size(): return false
	for index in first.size():
		var a: Dictionary = first[index]
		var b: Dictionary = second[index]
		if a.from != b.from or a.to != b.to or a.normal != b.normal or a.material != b.material or a.collider != b.collider:
			return false
	return true

func near_corner_rays() -> void:
	# These float32 endpoints make the former traversal overshoot one completed
	# axis indefinitely. Probe both grids, directions and swapped components.
	var solver := RainCollision.new()
	for cell_size: float in [16.0,64.0]:
		var cells: Dictionary = {}
		var segments: Array[Dictionary] = []
		for distance: float in [-64.0,0.0,16.0,64.0]:
			segments.append({"from":Vector2(-256,distance),"to":Vector2(256,distance)})
			segments.append({"from":Vector2(distance,-256),"to":Vector2(distance,256)})
		for index in segments.size(): solver._index_segment(cells,segments[index],index,cell_size)
		for epsilon: float in [.000004,.000008,.000016]:
			for mirror: float in [-1.0,1.0]:
				for swapped: bool in [false,true]:
					var origin := Vector2(-100,-100)*mirror
					var destination := Vector2(cell_size-epsilon,cell_size)*mirror
					if swapped: destination = Vector2(destination.y,destination.x)
					var candidates := solver._candidate_indices(cells,origin,destination,cell_size)
					var complete := true
					for index in segments.size():
						var point: Variant = Geometry2D.segment_intersects_segment(origin,destination,segments[index].from,segments[index].to)
						if point != null and not candidates.has(index): complete = false
					check(complete,"Near-corner traversal terminates and includes every exhaustive native contact: "+str([cell_size,epsilon,mirror,swapped]))

func run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args() or "--no-upnp" not in OS.get_cmdline_user_args():
		quit(2)
		return
	near_corner_rays()
	var game: Node2D = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.start_scenario(4,{"environment":"mountain_pass","build_type":"bastion","position":"left"})
	freeze(game)
	await physics_frame
	await process_frame
	var helper: WeatherPropSurfaces = game.weather.prop_surfaces
	helper.invalidate()
	var original := helper.rain_segments().duplicate()
	var builds := helper.geometry_builds
	helper.invalidate()
	var repeated := helper.rain_segments()
	check(same_geometry(original,repeated),"Warm fixed prop geometry retains every exact endpoint, normal, material and owner")
	check(helper.geometry_builds == builds and helper.geometry_reuses > 0,"An unchanged actual scene reuses mapped prop polygons without rebuilding their dictionaries")
	var supply: Supply = get_nodes_in_group("supplies")[0]
	var old := repeated.filter(func(segment): return segment.collider == supply)
	supply.position += Vector2(13,-7)
	helper.invalidate()
	var moved := helper.rain_segments().filter(func(segment): return segment.collider == supply)
	check(not old.is_empty() and old.size() == moved.size() and Vector2(moved[0].from).is_equal_approx(Vector2(old[0].from)+Vector2(13,-7)),"Same-frame world movement invalidates only the actual moved outline")
	var gun: RoofTurret = game.turret
	var before := helper.rain_segments().filter(func(segment): return segment.collider == gun)
	gun.barrel.rotation += .37
	gun.recoil = 4.0
	helper.invalidate()
	var turned := helper.rain_segments().filter(func(segment): return segment.collider == gun)
	check(not before.is_empty() and before != turned,"Cached artillery geometry follows simultaneous live aiming and recoil")
	var supply_id := supply.get_instance_id()
	supply.hide()
	helper.invalidate()
	check(not helper.rain_segments().any(func(segment): return segment.collider == supply) and not helper._polygon_cache.has(supply_id),"Same-frame hide removes retained polygons, rather than leaving a phantom roof")
	supply.show()
	helper.invalidate()
	check(helper.rain_segments().any(func(segment): return segment.collider == supply),"Restored actual equipment returns its current native outline")
	supply.queue_free()
	helper.invalidate()
	check(not helper.rain_segments().any(func(segment): return segment.collider == supply) and not helper._polygon_cache.has(supply_id),"Same-frame queued equipment releases its persistent geometry entry")
	var solver: RainCollision = game.weather.collision
	var kinds: Array = EnemyCatalog.GROUND_CLASSES.duplicate()
	kinds.append_array(AirEnemyCatalog.CLASS_ORDER)
	for kind: String in kinds:
		var air := AirEnemyCatalog.is_air(kind)
		var machine: Node2D = game._entity("air_enemy" if air else ("ground_infantry" if EnemyCatalog.is_human(kind) else "enemy"),Vector2(1120,160 if air else 430),{"kind":kind,"wave":20})
		freeze(machine)
		for index in 12:
			var phase := float(index)*.43
			machine.rotation = phase*.11
			machine.scale = Vector2(-.85 if index%2 else 1.13,.72+phase*.06)
			machine.age = phase
			machine.weapon_recoil = phase
			if machine is SiegeMachine:
				machine.gait = phase
				machine.moving = true
			machine._pose_parts()
			var envelope := solver.actor_bounds(machine).grow(.11)
			var machine_contours: Array[Dictionary] = machine.wetness.rain_segments()
			check(machine_contours.all(func(segment): return envelope.has_point(segment.from) and envelope.has_point(segment.to)),kind+": current rotated, mirrored and nonuniformly scaled bounds contain every real art edge at phase "+str(index))
		machine.free()
	var target: Node2D = game._entity("enemy",Vector2(1120,430),{"kind":"colossus","wave":20})
	freeze(target)
	var contours: Array[Dictionary] = target.wetness.rain_segments()
	var top := Vector2.ZERO
	var height := INF
	for segment in contours:
		var center: Vector2 = Vector2(segment.from).lerp(segment.to,.5)
		if center.y < height:
			height = center.y
			top = center
	solver.invalidate()
	solver.refresh(true)
	check(solver._actor_records.all(func(entry): return not entry.sampled and entry.cells.is_empty()),"Four crew and the live target remain lazy before any actual ray reaches them")
	var first := solver.trace(top-Vector2(0,16),top+Vector2(0,3),true)
	var record: Dictionary = solver._actor_records.filter(func(entry): return entry.actor == target)[0]
	check(first.get("collider") == target and record.sampled and not record.cells.is_empty(),"The first isolated short ray indexes only the reached real art")
	var index_cells: Dictionary = record.cells
	var current_contours: Array = record.segments
	var second := solver.trace(top-Vector2(0,16),top+Vector2(0,3),true)
	check(second.get("position") == first.get("position"),"A second short sweep preserves its exact nearest painted contact")
	var third := solver.trace(top-Vector2(0,16),top+Vector2(0,3),true)
	check(third.get("position") == first.get("position"),"Repeated native grid queries preserve the same exact contact")
	for index in 8: solver.trace(top-Vector2(0,16),top+Vector2(0,3),true)
	check(is_same(record.cells,index_cells) and is_same(record.segments,current_contours),"A reached actor retains its exact contour and grid arrays within the same pose frame")
	var terrain_query := solver._terrain_query
	var actor_query := solver._actor_query
	var body := StaticBody2D.new()
	body.position = Vector2(1450,400)
	body.collision_layer = 1
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = Vector2(18,20)
	shape.shape = box
	body.add_child(shape)
	game.add_child(body)
	await physics_frame
	await process_frame
	solver.invalidate()
	var blocked := solver.trace(Vector2(1450,380),Vector2(1450,450),false)
	var excluded := solver.trace(Vector2(1450,380),Vector2(1450,450),false,body)
	var blocked_again := solver.trace(Vector2(1450,380),Vector2(1450,450),false)
	check(blocked.get("collider") == body and excluded.get("collider") != body and is_equal_approx(float(excluded.get("position",Vector2.ZERO).y),430.0),"An explicit solid-body exclusion reaches the real support below")
	check(blocked_again.get("collider") == body and not terrain_query.exclude.has(body.get_rid()),"A one-shot exclusion cannot contaminate the next shared terrain query")
	check(solver._terrain_query == terrain_query and solver._actor_query == actor_query,"Repeated native contacts retain the same bounded per-world query resources")
	var courtyard: Node2D = game.perimeter.get_node("ServiceCourtyard")
	check(not courtyard.sections.is_empty(),"Actual active-front court supplies a paved surface interval")
	for section: Dictionary in courtyard.sections:
		var ground_y: float = section.ground
		var court_x := (float(section.start)+float(section.end))*.5
		var feet := courtyard.to_global(Vector2(court_x,ground_y))
		var contact: Dictionary = game.weather.surface_effects.sample_contact(feet)
		check(contact.get("material")=="concrete" and contact.get("kind")=="dry" and contact.get("supported")==true,"Actual paved ground contacts are concrete while remaining supported by the original slab")
		check(solver.material_for(null,courtyard.to_global(Vector2(float(section.end)+12,ground_y)))=="soil","Unpaved approach beyond the live court keeps its original soil contact")
		check(not solver._courtyard_pavement_at(courtyard.to_global(Vector2(court_x,ground_y-185))) and not solver._courtyard_pavement_at(courtyard.to_global(Vector2(court_x,ground_y+205))),"The same horizontal position cannot pave the roof or the mine floor")
		var original_transform := courtyard.transform
		courtyard.transform = Transform2D(.17,Vector2(41,-23)).scaled_local(Vector2(.8,1.1))
		check(solver._courtyard_pavement_at(courtyard.to_global(Vector2(court_x,ground_y))) and not solver._courtyard_pavement_at(feet),"Pavement lookup follows the visible court's actual rotation, scale and world position")
		courtyard.transform = original_transform
		courtyard.hide()
		check(not solver._courtyard_pavement_at(feet),"A hidden courtyard cannot override its former earth material")
		courtyard.show()
	check(helper._polygon_cache.size() <= helper._polygon_slots.size(),"Retained prop entries stay bounded by the current eligible scene")
	check(await Cleanup.free_scene(game,self),"Actual rainy main world releases its weather, retained nodes and audio handles")
	print("WEATHER EFFICIENCY: %d/%d passed"%[checks-failures,checks])
	quit(1 if failures else 0)
