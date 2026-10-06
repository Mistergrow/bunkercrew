extends SceneTree
## Actual immutable startup fixture uses explicitly reviewed layers and masks.
const Content := preload("res://scripts/content_registry.gd")
const Layers := preload("res://scripts/parallax_catalog.gd")
const Surfaces := preload("res://scripts/background_surface_catalog.gd")
const Skyline := preload("res://scripts/cloud_skyline.gd")
const Cleanup := preload("res://tests/scene_cleanup.gd")
var checks := 0
var failures := 0

func _initialize() -> void: _run.call_deferred()

func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func _run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args(): quit(2); return
	check(Content.diagnostics().is_empty(),"Startup registry accepts the installed environment fixture: "+str(Content.diagnostics()))
	if "--extension-fixture" not in OS.get_cmdline_user_args():
		print("SCENARIO CONTENT EXTENSION: fixture not requested; core registry checked")
		quit(1 if failures else 0)
		return
	var id := "beta.fixture:yard"
	check(Content.contains("environments",id),"Fixture environment exists before any game scene is allocated")
	if not Content.diagnostics().is_empty() or not Content.contains("environments",id):
		quit(1)
		return
	var selected := ScenarioCatalog.validate({"environment":id,"position":"middle","build_type":"workshop"})
	check(selected.environment==id,"Selection retains the stable namespaced environment ID")
	check(ScenarioCatalog.environment(id).id==id and ScenarioCatalog.environments(true).any(func(entry):return entry.id==id),"Indexed lookup and selection list both enumerate the same new ID")
	check(Layers.available(id) and Layers.paths(id)==Layers.paths("ash_foundry"),"Reviewed same-panorama background alias resolves all three real layers")
	check(Layers.definition(id)==Layers.definition("ash_foundry"),"Background alias preserves the existing layer motion parameters")
	check(Layers.sky_mask_path(id)==Layers.sky_mask_path("ash_foundry") and Skyline.texture(id)==Skyline.texture("ash_foundry") and Skyline.points(id)==Skyline.points("ash_foundry"),"Cloud occlusion and outlines resolve the reviewed panorama alias without building a namespaced filename")
	check(Surfaces.available(id),"Reviewed same-panorama surface alias accepts the authored mask validation")
	check(Surfaces.mask_path(id)==Surfaces.mask_path("ash_foundry") and Surfaces.definition(id)==Surfaces.definition("ash_foundry"),"Surface animation uses reviewed mask and region definitions instead of unsafe filename interpolation")
	LocaleText.set_locale("de",false)
	var german := ScenarioCatalog.environment(id)
	LocaleText.set_locale("en",false)
	var english := ScenarioCatalog.environment(id)
	check(german.title=="Prüfhof" and english.title=="Test yard","Pack title translations update without rereading environment JSON")
	check(english.id==id and english.path==german.path,"Localization keeps stable ID and explicit art path unchanged")
	LocaleText.set_locale("de",false)
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.campaign.persistence_enabled = false
	game.combat_events.persistence_enabled = false
	game.start_scenario(1,selected)
	game.rounds.set_process(false)
	check(game.started and game.scenario_options.environment==id and game.scenery!=null,"Actual world startup retains the new environment rather than silently falling back")
	check(game.scenery.panorama.texture==ScenarioCatalog.texture(str(english.path)),"Actual world loads the registered full panorama resource")
	paused = false
	check(await Cleanup.free_scene(game,self),"Add-on world fixture releases its real scene, decoder and audio")
	print("SCENARIO CONTENT EXTENSION: %d/%d passed" % [checks-failures,checks])
	quit(1 if failures else 0)
