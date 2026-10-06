extends SceneTree
## Real site centers are the authority; all27 biome/layout combinations must
## preserve scenery identities while keeping solid prop feet off their sites.
const Catalog=preload("res://scripts/scenario_prop_catalog.gd")
const Cleanup=preload("res://tests/scene_cleanup.gd")
var checks:=0
var failures:=0
func _initialize() -> void: run.call_deferred()
func check(value: bool,label: String) -> void:
	checks+=1
	print("PROP CLEARANCE %s: %s"%["PASS" if value else "FAIL",label])
	if not value: failures+=1; push_error(label)
func run() -> void:
	for placement in ["left","center","right"]:
		var game=preload("res://scenes/main.tscn").instantiate()
		root.add_child(game)
		game.combat_events.persistence_enabled=false
		game.start_scenario(1,{"environment":"sector07","position":placement,"build_type":"bastion"})
		game.rounds.set_process(false)
		for unused in 3: await physics_frame
		var centers: Array[float]=[]
		for site in game.perimeter.sites: centers.append(site.global_position.x)
		check(centers.size()==(6 if placement=="center" else 3),placement+" actual controller exposes the correct active fronts")
		for environment in ScenarioCatalog.environments():
			var entries:=Catalog.layout(environment.id,game.scenario_bunker.room_left,game.scenario_bunker.room_right)
			var repeated:=Catalog.layout(environment.id,game.scenario_bunker.room_left,game.scenario_bunker.room_right)
			check(entries==repeated,environment.id+"/"+placement+" layout is deterministic for peers and restarts")
			var identities:=entries.size()==16
			var clear:=true
			var grounded:=true
			for index in entries.size():
				var entry: Dictionary=entries[index]
				identities=identities and entry.index==index and ((entry.kind=="tree")== (index in [0,6,12,14]))
				grounded=grounded and entry.position.x>=-410 and entry.position.x<=1850 and entry.position.y in [429.0,430.0]
				grounded=grounded and entry.bounds.has_point(entry.position-Vector2(0,2))
				if entry.kind in ["rubble","brush","grass","frost_grass","reeds"]: continue
				var half_foot: float=22.0 if entry.kind=="tree" else entry.size.x*.5
				grounded=grounded and entry.position.x-half_foot>=-410.0 and entry.position.x+half_foot<=1850.0
				grounded=grounded and (entry.position.x<game.scenario_bunker.room_left or entry.position.x>game.scenario_bunker.room_right)
				for center in centers:
					clear=clear and absf(entry.position.x-center)>=56.0+half_foot
					if absf(entry.position.x-center)<56.0+half_foot: print("OVERLAP ",entry.kind,entry.position," site ",center)
			check(identities,environment.id+"/"+placement+" preserves all16 indices and four original tree identities")
			check(clear and grounded,environment.id+"/"+placement+" solid roots/bases clear every real site and stay on supported outdoor bounds")
		var props=game.scenery.props_layer
		var anchors_match:=true
		for entry in props.entries:
			if entry.kind!="tree": continue
			anchors_match=anchors_match and Vector2(entry.trunk_points[0]).distance_to(entry.position)<.01
			anchors_match=anchors_match and props._tree_by_index[entry.index].position==entry.position
		check(anchors_match,placement+" actual meshes, canopy/trunk metadata and relocated entry anchors agree")
		await Cleanup.free_scene(game,self)
	print("Perimeter prop clearance: %d/%d checks passed"%[checks-failures,checks])
	quit(1 if failures else 0)
