extends SceneTree
## Actual cosmetic ground tops, stable camera chunks, F3 and scene lifetimes.
const CATALOG := preload("res://scripts/living_ecology_catalog.gd")
const OUTSKIRTS := preload("res://scripts/vegetation_outskirts.gd")
const VEGETATION := preload("res://scripts/living_vegetation.gd")
const STRATA := preload("res://scripts/terrain_strata.gd")
const CLEANUP := preload("res://tests/scene_cleanup.gd")
var checks := 0
var failures := 0

class Bunker extends Node:
	var room_left := 90.0
	var room_right := 730.0

class Weather extends Node:
	var reduced_effects := false
	func gust_at(_point: Vector2) -> float: return .7

class World extends Node2D:
	var scenario_bunker: Node
	var scenario_options: Dictionary = {}
	var players: Array = []
	var weather: Node

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool,label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)

func _run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args():
		quit(2)
		return
	for environment: String in CATALOG.PROFILES:
		var game := World.new()
		game.scenario_bunker = Bunker.new()
		game.weather = Weather.new()
		game.add_child(game.scenario_bunker)
		game.add_child(game.weather)
		root.add_child(game)
		var vegetation := VEGETATION.new()
		vegetation.configure(game,environment)
		game.add_child(vegetation)
		vegetation.set_process(false)
		check(is_instance_valid(vegetation.outskirts),environment+": actual vegetation creates its cosmetic outskirts child")
		var child: Node2D = vegetation.outskirts
		for camera in [Rect2(-2100,150,3600,600),Rect2(500,150,3700,600),Rect2(-7000,100,15000,900)]:
			child.update_view(camera,false,2.0,.7)
			var full: Dictionary = child.diagnostics()
			check(int(full.plants)>0 and int(full.trees)>0,environment+": visible inaccessible land has habitat plants and trees on both sides")
			check(int(full.plants)<=CATALOG.MAX_OUTSKIRT_PLANTS and int(full.trees)<=CATALOG.MAX_OUTSKIRT_TREES,environment+": wide camera stays within fixed population budgets")
			check(int(full.mesh_batches)<=9 and int(full.materials)==2,environment+": both tree bands and undergrowth use at most nine shared batches and two wind materials")
			var safe := true
			for entry: Dictionary in child.plants+child.trees:
				var position: Vector2 = entry.position
				var radius := float(entry.size.x)
				safe = safe and position.y==STRATA.FIELD.position.y
				safe = safe and position.x-radius>=STRATA.FIELD.position.x and position.x+radius<=STRATA.FIELD.end.x
				safe = safe and (position.x+radius<=CATALOG.GROUND_LEFT or position.x-radius>=CATALOG.GROUND_RIGHT)
			check(safe,environment+": new silhouettes stay on painted earth outside the reachable slab, never over sky or panorama water")
			var original := var_to_str([child.plants,child.trees])
			var rebuilds := int(full.rebuilds)
			child.update_view(camera,false,2.1,.8)
			check(int(child.diagnostics().rebuilds)==rebuilds and var_to_str([child.plants,child.trees])==original,environment+": wind tick and unchanged camera do not rebuild geometry")
			child.update_view(camera,true,2.1,.8)
			var reduced: Dictionary = child.diagnostics()
			check(int(reduced.active_plants)<int(full.active_plants) and int(reduced.active_trees)<=int(full.active_trees),environment+": F3 uses prepared meshes and keeps recognizable outer growth")
			check(is_equal_approx(float(child._ground_material.get_shader_parameter("motion_scale")),.24) and is_equal_approx(float(child._tree_material.get_shader_parameter("motion_scale")),.24),environment+": same-clock F3 preview immediately reduces both wind materials")
			check(int(reduced.rebuilds)==rebuilds,environment+": F3 switches do not rebuild or respawn distant vegetation")
			child.update_view(camera,false,2.3,.8)
			check(var_to_str([child.plants,child.trees])==original,environment+": full/reduced restoration preserves exact world anchors")
		child.update_view(Rect2(-2000,1100,4000,1200),false,4.0,.7)
		check(child.plants.is_empty() and child.trees.is_empty() and child._batches.is_empty(),environment+": deep underground view submits no invisible outskirts meshes")
		child.update_view(Rect2(-2100,150,3600,600),false,5.0,.7)
		var stable := var_to_str([child.plants,child.trees])
		child.update_view(Rect2(500,150,3700,600),false,6.0,.7)
		child.update_view(Rect2(-2100,150,3600,600),false,7.0,.7)
		check(var_to_str([child.plants,child.trees])==stable,environment+": revisiting a camera chunk restores the same natural arrangement")
		var before := vegetation.elapsed
		paused = true
		vegetation._process(1.0)
		check(vegetation.elapsed==before,environment+": the outer wind remains pause safe")
		paused = false
		check(child.find_children("*","CollisionObject2D",true,false).is_empty(),environment+": outskirts add no collision bodies or damage targets")
		check(await CLEANUP.free_scene(game,self),environment+": every mesh is released with its actual owning level")
	var classic := World.new()
	root.add_child(classic)
	var outside := OUTSKIRTS.new()
	outside.configure(classic,"sector07")
	classic.add_child(outside)
	outside.update_view(Rect2(-1200,0,3900,900),false,1.0,.7)
	var supported := not outside.plants.is_empty() and not outside.trees.is_empty()
	for entry: Dictionary in outside.plants+outside.trees:
		var position: Vector2 = entry.position
		var radius := float(entry.size.x)
		supported = supported and ((position.y==245.0 and position.x-radius>=-960.0 and position.x+radius<=-30.0) or (position.y==430.0 and position.x-radius>=1440.0 and position.x+radius<=2400.0))
	check(supported,"classic outer growth follows its elevated western hillside and finite eastern road")
	check(await CLEANUP.free_scene(classic,self),"classic outskirts cleanup")
	var preview := OUTSKIRTS.new()
	preview.configure(null,"mountain_pass")
	root.add_child(preview)
	preview.update_view(Rect2(-1000,-200,3500,900),false,1.0,.5)
	check(preview._batches.is_empty(),"a panorama-only menu preview cannot float vegetation across its image")
	await CLEANUP.free_scene(preview,self)
	print("VEGETATION OUTSKIRTS: %d/%d checks passed"%[checks-failures,checks])
	quit(0 if failures==0 else 1)
