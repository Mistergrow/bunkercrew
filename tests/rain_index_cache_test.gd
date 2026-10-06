extends SceneTree
## Cell membership may be retained while geometry changes within a cell. Native
## contacts and prop hull exclusions must still use the current surface/owner.
class OutlineProp extends Node2D:
	var hull: StaticBody2D
	func _ready() -> void:
		hull=StaticBody2D.new()
		hull.collision_layer=1
		var shape := CollisionShape2D.new()
		var rectangle := RectangleShape2D.new()
		rectangle.size=Vector2(20,6)
		shape.shape=rectangle
		hull.add_child(shape)
		add_child(hull)
class SurfaceSource extends Node2D:
	var entries: Array[Dictionary]=[]
	func rain_segments() -> Array[Dictionary]: return entries
class TestWeather extends Node2D:
	var game: Node
	var prop_surfaces: SurfaceSource
class CountedCollision extends RainCollision:
	var index_writes := 0
	func _index_cell_bounds(cells: Dictionary, bounds: Rect2i, index: int) -> void:
		index_writes+=1
		super._index_cell_bounds(cells,bounds,index)
var checks := 0
var failures := 0

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok: failures+=1;push_error(label)

func surface(prop: OutlineProp, material: String="metal") -> Dictionary:
	return {"from":prop.to_global(Vector2(-10,-3)),"to":prop.to_global(Vector2(10,-3)),"normal":Vector2.UP,"collider":prop,"material":material,"weather_prop":true}

func run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args() or "--no-upnp" not in OS.get_cmdline_user_args(): quit(2);return
	var weather := TestWeather.new()
	root.add_child(weather)
	weather.prop_surfaces=SurfaceSource.new()
	weather.add_child(weather.prop_surfaces)
	var first := OutlineProp.new()
	first.position=Vector2(520,40)
	weather.add_child(first)
	await physics_frame
	await process_frame
	var solver := CountedCollision.new()
	solver.weather=weather
	weather.prop_surfaces.entries=[surface(first)]
	var hit := solver.trace(Vector2(520,-20),Vector2(520,60),false)
	check(hit.get("collider")==first and is_equal_approx(float(hit.get("position",Vector2.ZERO).y),37.0),"Cold index keeps native painted surface and excludes its larger physics hull")
	check(solver.index_writes==1,"Cold static silhouette builds one cell membership")
	var original_cells := solver._static_cells.duplicate(true)
	first.position.y+=5
	weather.prop_surfaces.entries=[surface(first,"wood")]
	solver.invalidate()
	hit=solver.trace(Vector2(520,-20),Vector2(520,60),false)
	check(hit.get("collider")==first and is_equal_approx(float(hit.position.y),42.0) and hit.material=="wood","Same-cell motion and material change immediately update actual contacts")
	check(solver.index_writes==1 and solver._static_cells==original_cells,"Unchanged occupied cells reuse their complete membership")
	first.position.x+=64
	weather.prop_surfaces.entries=[surface(first)]
	solver.invalidate()
	hit=solver.trace(Vector2(584,-20),Vector2(584,60),false)
	check(hit.get("collider")==first,"A cell-crossing prop catches rain at its current location")
	check(solver.index_writes==2 and solver._static_cells!=original_cells,"Crossing a grid boundary rebuilds membership")
	check(solver.trace(Vector2(520,-20),Vector2(520,60),false).is_empty(),"Crossing a boundary removes its former rain cover")
	var replacement := OutlineProp.new()
	replacement.position=first.position
	weather.add_child(replacement)
	first.queue_free()
	weather.prop_surfaces.entries=[surface(replacement,"cloth")]
	solver.invalidate()
	hit=solver.trace(Vector2(584,-20),Vector2(584,60),false)
	check(hit.get("collider")==replacement and hit.material=="cloth","Same-cell owner replacement uses the live current prop")
	check(solver.index_writes==2 and solver._prop_rids==[replacement.hull.get_rid()],"Owner replacement retains geometry cells but refreshes actual physics exclusions")
	replacement.hide()
	check(solver.trace(Vector2(584,-20),Vector2(584,60),false).get("collider")!=replacement,"Hidden warmed painted geometry cannot catch rain")
	replacement.show()
	weather.prop_surfaces.entries=[]
	solver.invalidate()
	solver.refresh(false)
	check(solver._static_cells.is_empty() and solver._static_segments.is_empty() and solver._prop_rids.is_empty(),"Removing all surfaces clears indexed geometry and physics exclusions")
	weather.prop_surfaces.entries=[surface(replacement)]
	solver.invalidate()
	hit=solver.trace(Vector2(584,-20),Vector2(584,60),false)
	check(hit.get("collider")==replacement and solver.index_writes==3,"Restoring a removed surface rebuilds its native contact")
	replacement.queue_free()
	check(solver.trace(Vector2(584,-20),Vector2(584,60),false).get("collider")!=replacement,"Queued warmed prop cannot produce a phantom painted contact")
	check(await preload("res://tests/scene_cleanup.gd").free_scene(weather,self),"Actual World2D fixture retires without dangling prop nodes")
	print("RAIN INDEX CACHE: %d/%d passed"%[checks-failures,checks])
	quit(1 if failures else 0)
