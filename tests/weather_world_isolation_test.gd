extends SceneTree
## Actual worker silhouettes/props in distinct World2D spaces and a same-space
## second game. SceneTree groups alone must never create foreign rain cover.
const Cleanup:=preload("res://tests/scene_cleanup.gd")
const OUTPUT:="res://artifacts/final-hardening-20261004/presentation/"
class TestWeather extends Node2D:
	var game: Node
	var prop_surfaces: Node2D
	func roof_flag_visible() -> bool: return false
class TestGame extends Node2D:
	var started:=true
	var players: Array[Worker]=[]
	var weather: Node2D
var checks:=0
var failures:=0

func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1;push_error(label)
func freeze(node: Node) -> void:
	node.set_process(false);node.set_physics_process(false)
	for child in node.get_children(): freeze(child)
func make_game(view: SubViewport) -> TestGame:
	var game:=TestGame.new();view.add_child(game)
	var weather:=TestWeather.new();weather.game=game;game.weather=weather
	game.add_child(weather)
	var props:=WeatherPropSurfaces.new();props.game=game;props.weather=weather
	weather.prop_surfaces=props;weather.add_child(props)
	return game
func worker(game: TestGame,y: float) -> Worker:
	var actor:=load("res://scenes/player.tscn").instantiate() as Worker
	actor.game=game;actor.position=Vector2(1000,y)
	game.add_child(actor);game.players.append(actor);freeze(actor)
	return actor
func supply(game: TestGame,y: float) -> Supply:
	var item:=Supply.new();item.game=game;item.position=Vector2(1300,y)
	game.add_child(item);freeze(item)
	return item
func prop(game: TestGame,y: float) -> LevelProp:
	var item:=LevelProp.new();item.position=Vector2(1500,y)
	game.add_child(item);freeze(item)
	return item
func ground(game: TestGame,y: float) -> StaticBody2D:
	var body:=StaticBody2D.new();body.position=Vector2(1000,y);body.collision_layer=1
	var collider:=CollisionShape2D.new();var rectangle:=RectangleShape2D.new();rectangle.size=Vector2(100,10)
	collider.shape=rectangle;body.add_child(collider);game.add_child(body)
	return body

func run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args() or "--no-upnp" not in OS.get_cmdline_user_args(): quit(2);return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var first:=SubViewport.new();first.world_2d=World2D.new();first.size=Vector2i(320,240);root.add_child(first)
	var second:=SubViewport.new();second.world_2d=World2D.new();second.size=Vector2i(320,240);root.add_child(second)
	var own:=make_game(first);var foreign:=make_game(second);var same_space_other_game:=make_game(first)
	var own_worker:=worker(own,240);var foreign_worker:=worker(foreign,140);var sibling_worker:=worker(same_space_other_game,90)
	var own_supply:=supply(own,220);var foreign_supply:=supply(foreign,140);var sibling_supply:=supply(same_space_other_game,90)
	var own_prop:=prop(own,220);var foreign_prop:=prop(foreign,140);var sibling_prop:=prop(same_space_other_game,90)
	var own_ground:=ground(own,360);ground(foreign,320)
	await physics_frame;await process_frame
	check(own.get_world_2d().space!=foreign.get_world_2d().space,"Fixtures use genuinely separate physics spaces")
	check(own.get_world_2d().space==same_space_other_game.get_world_2d().space,"Second ownership counterexample intentionally shares the physics space")
	var solver:=RainCollision.new();solver.weather=own.weather
	solver.refresh(true)
	check(solver._actor_records.size()==1 and solver._actor_records[0].actor==own_worker,"Rain actor cache admits only the owning game's actual worker")
	var segments:=own_worker.wetness.rain_segments()
	var highest:=Vector2.ZERO;var top:=INF
	for entry: Dictionary in segments:
		var center:=Vector2(entry.from).lerp(entry.to,.5)
		if center.y<top: top=center.y;highest=center
	check(not segments.is_empty(),"Real authored worker art supplies nonempty rain contours")
	var hit:=solver.trace(highest-Vector2(0,500),highest+Vector2(0,4),true)
	check(hit.get("collider")==own_worker,"Foreign worker pixels cannot intercept rain above the real own silhouette")
	var physical:=solver.trace(Vector2(1000,300),Vector2(1000,400),false)
	check(physical.get("collider")==own_ground,"Rain terrain query keeps using the actual owning physics world")
	var helper:=own.weather.prop_surfaces as WeatherPropSurfaces
	var contours:=helper.rain_segments()
	check(contours.any(func(entry):return entry.collider==own_supply),"Own actual supply retains its painted rain cover")
	check(contours.any(func(entry):return entry.collider==own_prop),"Own actual atlas prop retains its painted rain cover")
	for other: Node2D in [foreign_supply,sibling_supply,foreign_prop,sibling_prop]:
		check(not contours.any(func(entry):return entry.collider==other),"Foreign/sibling supply or atlas prop never becomes own rain cover")
	foreign_worker.hide();sibling_worker.hide()
	foreign_prop.hide();sibling_prop.hide();foreign_supply.hide();sibling_supply.hide()
	own_worker.hide();own_prop.hide();own_supply.hide()
	solver.invalidate();helper.invalidate();solver.refresh(true)
	check(solver._actor_records.is_empty() and helper.rain_segments().is_empty(),"Invisible owning figures and props create no rain silhouettes")
	own_worker.show();own_prop.show();own_supply.show()
	solver.invalidate();helper.invalidate();solver.refresh(true)
	check(solver._actor_records.size()==1,"Restored visible own worker returns to actual rain cache")
	# Warmed contours must stop catching drops immediately when queued, before
	# SceneTree performs deferred deletion at the end of this same render frame.
	solver.trace(highest-Vector2(0,30),highest+Vector2(0,4),true)
	own_worker.queue_free();own_prop.queue_free();own_supply.queue_free()
	check(solver.trace(highest-Vector2(0,30),highest+Vector2(0,4),true).is_empty(),"A queued worker cannot intercept rain through already warmed contours")
	helper.invalidate()
	check(helper.rain_segments().is_empty(),"Queued owning supply and atlas prop are removed from regenerated cover")
	await process_frame
	var immediate_worker:=worker(own,240)
	solver.invalidate();solver.refresh(true)
	check(solver.trace(highest-Vector2(0,30),highest+Vector2(0,4),true).get("collider")==immediate_worker,"Immediate-free counterexample first warms a real live worker contour")
	immediate_worker.free()
	check(solver.trace(highest-Vector2(0,30),highest+Vector2(0,4),true).is_empty(),"Already freed worker/wetness references are safely removed from warmed cache")
	var immediate_supply:=supply(own,240)
	helper.invalidate();solver.invalidate()
	check(solver.trace(Vector2(1300,100),Vector2(1300,260),false).get("collider")==immediate_supply,"Immediate-free prop counterexample first warms real own crate geometry")
	immediate_supply.free()
	check(solver.trace(Vector2(1300,100),Vector2(1300,260),false).is_empty(),"Already freed crate cannot create a cached phantom rain contact")
	check(await Cleanup.free_scene(first,self) and await Cleanup.free_scene(second,self),"Both actual World2D fixtures retire without orphan nodes")
	var file:=FileAccess.open(OUTPUT+"weather-world-verification.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"prepared_state":"Three game roots across two real SubViewport World2D physics spaces, native worker art/ActorWetness, actual supply and atlas props, actual separate terrain colliders, warmed queued contours."},"\t")+"\n")
	print("WEATHER WORLD ISOLATION: %d/%d passed"%[checks-failures,checks])
	quit(1 if failures else 0)
