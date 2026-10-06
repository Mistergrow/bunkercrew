extends SceneTree
## Run from an empty --path with --main-pack to verify exported raw metadata,
## imported textures and the production render layers without checkout fallback.
const Plants := preload("res://scripts/living_vegetation.gd")
const Fauna := preload("res://scripts/living_fauna.gd")
const Ecology := preload("res://scripts/living_ecology_catalog.gd")
const Animals := preload("res://scripts/fauna_catalog.gd")
const Dance := preload("res://scripts/worker_dance_catalog.gd")
const Moves := preload("res://scripts/worker_dance_moves.gd")
const Cleanup := preload("res://tests/scene_cleanup.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func _run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args():
		quit(2)
		return
	check(FileAccess.file_exists(Ecology.METADATA_PATH),"Export includes vegetation source regions")
	check(FileAccess.file_exists(Animals.SOURCE_PATH),"Export includes animal frame metadata")
	check(FileAccess.file_exists("res://assets/environments/life/LICENSE.txt"),"Export includes artwork provenance notice")
	check(Ecology.asset_regions().size()==16,"All sixteen measured plant regions load from pack")
	check(Moves.IDS.size()==43,"All forty unique and three shared choreographies survive export")
	for id: String in Dance.IDS:
		check(Dance.available_styles(id,1).size()==3 and Dance.available_styles(id,10).size()==8,id+": exported unlock table retains three common and five unique moves")
	var locations := ScenarioCatalog.environments(true)
	check(locations.size()==13,"All thirteen environment profiles load from pack")
	for location: Dictionary in locations:
		var plants := Plants.new()
		plants.configure(null,str(location.id))
		root.add_child(plants)
		var wildlife := Fauna.new()
		wildlife.configure(null,str(location.id))
		root.add_child(wildlife)
		var flora_stats: Dictionary = plants.diagnostics()
		var fauna_stats: Dictionary = wildlife.debug_stats()
		check(bool(flora_stats.atlas_loaded) and int(flora_stats.active_count)>0,str(location.id)+": exported plant texture and metadata build real mesh")
		check(int(flora_stats.mesh_batches)==3 and int(flora_stats.materials)==1,str(location.id)+": shared vegetation material survives export")
		check(bool(fauna_stats.atlas_loaded),str(location.id)+": exported animal texture loads")
		check(int(fauna_stats.population)==Animals.population(str(location.id)),str(location.id)+": exported wildlife roster is complete")
		check(int(fauna_stats.population)<=2 and int(fauna_stats.airborne)==0,str(location.id)+": exported world has only rare ground animals")
		await Cleanup.free_scene(plants,self)
		await Cleanup.free_scene(wildlife,self)
	print("LIVING ECOLOGY EXPORT: %d/%d checks passed"%[checks-failures,checks])
	quit(1 if failures else 0)
