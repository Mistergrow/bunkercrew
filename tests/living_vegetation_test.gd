extends SceneTree
## Habitat identity, rooted art, bounded batches and actual F3/pause behavior.
const CATALOG := preload("res://scripts/living_ecology_catalog.gd")
const VEGETATION := preload("res://scripts/living_vegetation.gd")
const CLEANUP := preload("res://tests/scene_cleanup.gd")

class Weather extends Node:
	var reduced_effects := false
	func gust_at(_point: Vector2) -> float: return .8

class Bunker extends Node:
	var room_left := 90.0
	var room_right := 730.0

class World extends Node2D:
	var weather: Node
	var scenario_bunker: Node
	var scenario_options := {"position":"left"}
	var players: Array = []

var checks := 0
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(value: bool,label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)

func run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args():
		push_error("Run with --no-profile-save")
		quit(1)
		return
	root.size = Vector2i(1440,900)
	var regions := CATALOG.asset_regions()
	check(regions.size()==16,"all sixteen generated sprites have measured source regions")
	var biomes: Dictionary = {}
	for environment: String in CATALOG.PROFILES:
		var profile := CATALOG.profile(environment)
		biomes[profile.biome] = true
		check(profile.flora.size()==profile.weights.size(),environment+": flora and weights agree")
		for species: String in profile.flora:
			check(CATALOG.SPECIES.has(species) and regions.has(species),environment+": habitat species exists in the authored atlas")
		for placement in [Vector2(90,730),Vector2(400,1040),Vector2(710,1350),Vector2(0,873)]:
			var entries := CATALOG.layout(environment,placement.x,placement.y)
			var repeated := CATALOG.layout(environment,placement.x,placement.y)
			var reduced_entries := CATALOG.layout(environment,placement.x,placement.y,true)
			check(var_to_str(entries)==var_to_str(repeated),environment+": layout is deterministic for this bunker footprint")
			check(entries.size()>20 and entries.size()<=CATALOG.MAX_PLANTS,environment+": vegetation population has a fixed upper bound")
			check(reduced_entries.size()>0 and reduced_entries.size()<entries.size()*.7,environment+": F3 retains habitat identity while removing optional clumps")
			var grounded := true
			var clear := true
			for entry: Dictionary in entries:
				var position: Vector2 = entry.position
				var width := float(entry.size.x)
				grounded = grounded and is_equal_approx(position.y,CATALOG.GROUND_Y) and position.x-width>=CATALOG.GROUND_LEFT and position.x+width<=CATALOG.GROUND_RIGHT
				clear = clear and (position.x+width<=placement.x-CATALOG.BUNKER_CLEARANCE or position.x-width>=placement.y+CATALOG.BUNKER_CLEARANCE)
			check(grounded,environment+": every plant is supported by actual finite outdoor terrain")
			check(clear,environment+": complete silhouettes clear both doors and the bunker interior")
		var world := World.new()
		world.weather = Weather.new()
		world.scenario_bunker = Bunker.new()
		world.add_child(world.weather)
		world.add_child(world.scenario_bunker)
		root.add_child(world)
		var vegetation := VEGETATION.new()
		vegetation.configure(world,environment)
		world.add_child(vegetation)
		vegetation.set_process(false)
		var state := vegetation.diagnostics()
		check(state.atlas_loaded and state.active_count==vegetation.entries.size(),environment+": the generated alpha atlas renders every authored plant")
		check(state.mesh_batches==3 and state.materials==1,environment+": all plants share exactly three batches and one shader material")
		var rooted := true
		var source_valid := true
		for mesh: ArrayMesh in vegetation._full_meshes:
			check(mesh.get_surface_count()==1,environment+": each depth is a single surface")
			var arrays := mesh.surface_get_arrays(0)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
			var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
			for index in vertices.size():
				if is_equal_approx(vertices[index].y,CATALOG.GROUND_Y): rooted = rooted and is_zero_approx(colors[index].b)
				rooted = rooted and vertices[index].y<=CATALOG.GROUND_Y+.001
				source_valid = source_valid and uvs[index].x>=0 and uvs[index].x<=1 and uvs[index].y>=0 and uvs[index].y<=1
		check(rooted,environment+": mesh roots stay fixed while only above-ground bands can bend")
		check(source_valid,environment+": every sampled UV stays inside the real alpha atlas")
		var full_count: int = state.active_count
		world.weather.reduced_effects = true
		vegetation._process(.2)
		check(vegetation.diagnostics().reduced and vegetation.active_count<full_count*.7,environment+": real weather F3 switches to prepared reduced meshes")
		world.weather.reduced_effects = false
		vegetation._process(.2)
		check(not vegetation.diagnostics().reduced and vegetation.active_count==full_count,environment+": returning from F3 restores full plants without respawning")
		var clock: float = vegetation.elapsed
		paused = true
		vegetation._process(1.0)
		check(vegetation.elapsed==clock,environment+": pause freezes the wind clock")
		paused = false
		var outside := Node2D.new()
		outside.position = Vector2(1100,430)
		world.add_child(outside)
		var indoor := Node2D.new()
		indoor.position = Vector2(410,430)
		world.add_child(indoor)
		var roof := Node2D.new()
		roof.position = Vector2(1100,245)
		world.add_child(roof)
		world.players = [outside,indoor,roof]
		var feet: PackedVector4Array = vegetation._actor_feet()
		check(feet[0].x==1100 and feet[0].z==1 and feet[1]==Vector4.ZERO,environment+": only outdoor ground feet bend nearby undergrowth")
		world.scenario_bunker.room_left = 710.0
		world.scenario_bunker.room_right = 1350.0
		vegetation.refresh_bunker_clearance()
		check(vegetation.bunker_left==710 and vegetation.bunker_right==1350,environment+": changed bunker placement updates the complete ecological clearance")
		check(await CLEANUP.free_scene(world,self),environment+": all batches leave with their scene")
	check(biomes.size()==13,"each of the thirteen levels has its own habitat")
	check(CATALOG.layout("overgrown_steelworks").size()>CATALOG.layout("sulfur_refinery").size(),"lush regrowth is denser than hostile sulfur ground")
	check(CATALOG.profile("frozen_rail_yard").flora.has("snow_bush") and not CATALOG.profile("sulfur_refinery").flora.has("fern"),"frost plants and lush ferns respect the actual climate")
	var classic := CATALOG.layout("sector07",0,873,false,75,1440)
	var classic_grounded := not classic.is_empty()
	for entry: Dictionary in classic:
		classic_grounded = classic_grounded and float(entry.position.x)-float(entry.size.x)>=75 and float(entry.position.x)+float(entry.size.x)<=1440
	check(classic_grounded,"the classic bunker uses its own actual x75..1440 slab, without plants over unsupported scenery")
	print("LIVING VEGETATION: %d/%d checks passed" % [checks-failures,checks])
	quit(0 if failures==0 else 1)
